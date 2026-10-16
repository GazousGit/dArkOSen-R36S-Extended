#!/bin/bash
# Remove the two test cores (flycast32_rumble_hack, flycast32_modern) from a dArkOSen
# device, over SSH from WSL: the core files and .info files, their lines in the ES core
# lists, the ES per-system core choices that named them (ES then falls back to its
# default), their RetroArch per-core config/remap folders and the flycast_* keys the
# modern core added to the shared retroarch32 options file. ArkOS's flycast32_rumble and
# everything else are left alone. EmulationStation is stopped while the files change
# (it rewrites es_settings.cfg on exit) and started again. Refuses to run while a game runs.
# Safe to run twice.
#
# usage: device-remove.sh [host]      (default 192.168.1.159, user ark / ark)

set -euo pipefail

HOST=${1:-192.168.1.159}
SSH=(sshpass -p ark ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ark@$HOST")

"${SSH[@]}" 'bash -s' <<'REMOTE'
set -euo pipefail
cores=/home/ark/.config/retroarch32/cores
cfg=/etc/emulationstation/es_systems.cfg
ess=/home/ark/.emulationstation/es_settings.cfg
opts=/home/ark/.config/retroarch32/retroarch-core-options.cfg

if pgrep -x retroarch32 >/dev/null || pgrep -x retrorun32 >/dev/null; then
    echo "an emulator is running, not touching anything:"; pgrep -a "retroarch32|retrorun32"
    echo "(quit it first; if it is stuck: sudo pkill -9 -x retroarch32)"
    exit 3
fi
sudo systemctl stop emulationstation

# core files and RetroArch per-core folders
for c in flycast32_rumble_hack flycast32_modern; do
    rm -f "$cores/${c}_libretro.so" "$cores/${c}_libretro.info"
done
rm -rf "/home/ark/.config/retroarch32/config/Flycast32 Rumble Hack" \
       "/home/ark/.config/retroarch32/config/Flycast32 Modern" \
       "/home/ark/.config/retroarch32/config/remaps/Flycast32 Rumble Hack" \
       "/home/ark/.config/retroarch32/config/remaps/Flycast32 Modern"

# ES core lists: drop our two lines (the backup from the install is kept)
tmp=$(mktemp)
grep -v '<core>flycast32_rumble_hack</core>\|<core>flycast32_modern</core>' "$cfg" > "$tmp" || true
if ! cmp -s "$tmp" "$cfg"; then sudo cp "$tmp" "$cfg"; echo "es_systems.cfg: core lines removed"; fi
rm -f "$tmp"

# ES per-system core choices that named them (ES falls back to the system default)
if grep -q 'value="flycast32_rumble_hack"\|value="flycast32_modern"' "$ess" 2>/dev/null; then
    grep -n 'value="flycast32_rumble_hack"\|value="flycast32_modern"' "$ess"
    sed -i '/value="flycast32_rumble_hack"/d; /value="flycast32_modern"/d' "$ess"
    echo "es_settings.cfg: core choices reset"
fi

# options the modern core added (its own prefix); the legacy keys are not touched
if grep -q '^flycast_' "$opts" 2>/dev/null; then
    echo "retroarch-core-options.cfg: $(grep -c '^flycast_' "$opts") flycast_* lines removed"
    sed -i '/^flycast_/d' "$opts"
fi

sudo systemctl start emulationstation
echo "left in the core lists: $(grep -c '<core>flycast32_rumble</core>' "$cfg") flycast32_rumble entries, $(grep -c 'flycast32_rumble_hack\|flycast32_modern' "$cfg") of ours"
ls "$cores" | grep -i flycast
REMOTE
echo "removed from $HOST"
