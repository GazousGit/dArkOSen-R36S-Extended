#!/bin/bash
# Install the test cores on a dArkOSen device (over SSH, from WSL) and offer them in
# EmulationStation right after ArkOS's flycast32_rumble, wherever that core is listed
# (Dreamcast, Naomi, Atomiswave; retroarch32 and retrorun32). Nothing is replaced:
#   flycast32_rumble_hack  metallic77's core + our fixes (out/gazous-v2)
#   flycast32_modern       flyinghead flycast, dArkOSen branch (out/modern-dArkOSen)
# es_systems.cfg is backed up once to es_systems.cfg.before-flycast32 and ES restarted.
#
# usage: device-install.sh [host]      (default 192.168.1.159, user ark / ark)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOST=${1:-192.168.1.159}
SSH=(sshpass -p ark ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ark@$HOST")
SCP=(sshpass -p ark scp -o StrictHostKeyChecking=no -o ConnectTimeout=5)
CORES=("$HERE/out/gazous-v2/flycast32_rumble_hack_libretro.so"
       "$HERE/out/modern-dArkOSen/flycast32_modern_libretro.so")

for c in "${CORES[@]}"; do
    [ -f "$c" ] || { echo "missing $c, build it first" >&2; exit 1; }
done

"${SCP[@]}" "${CORES[@]}" "ark@$HOST:/home/ark/.config/retroarch32/cores/"

"${SSH[@]}" 'bash -s' <<'REMOTE'
set -euo pipefail
cores=/home/ark/.config/retroarch32/cores
chmod 755 "$cores/flycast32_rumble_hack_libretro.so" "$cores/flycast32_modern_libretro.so"

# RetroArch .info files, from ArkOS's flycast32_rumble one
for pair in "flycast32_rumble_hack:Flycast32 Rumble Hack" "flycast32_modern:Flycast32 Modern"; do
    core=${pair%%:*}; name=${pair#*:}
    sed -e "s|^display_name = .*|display_name = \"Sega - Dreamcast/Naomi ($name)\"|" \
        -e "s|^corename = .*|corename = \"$name\"|" \
        "$cores/flycast32_rumble_libretro.info" > "$cores/${core}_libretro.info"
done

cfg=/etc/emulationstation/es_systems.cfg
[ -f "$cfg.before-flycast32" ] || sudo cp -p "$cfg" "$cfg.before-flycast32"
tmp=$(mktemp)
awk '
/<core>flycast32_rumble_hack<\/core>|<core>flycast32_modern<\/core>/ { next }
{ print }
/<core>flycast32_rumble<\/core>/ {
    indent = $0; sub(/<core>.*/, "", indent)
    print indent "<core>flycast32_rumble_hack</core>"
    print indent "<core>flycast32_modern</core>"
}' "$cfg" > "$tmp"
sudo cp "$tmp" "$cfg"
rm -f "$tmp"
echo "core lists now offering the new cores: $(grep -c '<core>flycast32_modern</core>' "$cfg")"
sudo systemctl restart emulationstation
REMOTE
echo "installed on $HOST"
