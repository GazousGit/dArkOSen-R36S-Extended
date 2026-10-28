#!/bin/bash
# Install the retrorun hotkeys build (out/retrorun, out/retrorun32 from build.sh) on a
# dArkOSen device over SSH, from WSL. dArkOSen's own binaries are kept next to them as
# retrorun.darkosen / retrorun32.darkosen (only the first time: a binary that already carries
# the hotkeys string is not backed up). Then /opt/system/Shortcuts.sh --repair writes the
# retrorun_hotkey_* lines into retrorun.cfg if the universal hotkey layout is on (otherwise
# nothing changes until it is chosen). Saturn's launcher runs retrorun without -c: the default
# config path (/storage/.config/distribution/configs/retrorun.cfg, absent on dArkOSen) is
# made a link to /home/ark/.config/retrorun.cfg so that it reads the same settings.
# Refuses to run while retrorun runs. Safe to run twice.
#
# usage: device-install.sh [host]      (default 192.168.1.159, user ark / ark)

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOST=${1:-192.168.1.159}
SSH=(sshpass -p ark ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ark@$HOST")
SCP=(sshpass -p ark scp -o StrictHostKeyChecking=no -o ConnectTimeout=5)

for b in retrorun retrorun32; do
    [ -f "$HERE/out/$b" ] || { echo "missing $HERE/out/$b, run build.sh first" >&2; exit 1; }
    grep -q retrorun_hotkey_menu "$HERE/out/$b" || { echo "$HERE/out/$b is not the hotkeys build" >&2; exit 1; }
done

"${SCP[@]}" "$HERE/out/retrorun" "$HERE/out/retrorun32" "ark@$HOST:/tmp/"

"${SSH[@]}" 'bash -s' <<'REMOTE'
set -euo pipefail
if pgrep -x retrorun >/dev/null || pgrep -x retrorun32 >/dev/null; then
    echo "retrorun is running, not touching anything:"; pgrep -a "retrorun"; exit 3
fi
for b in retrorun retrorun32; do
    cur=/usr/local/bin/$b
    if [ -f "$cur" ] && ! grep -q retrorun_hotkey_menu "$cur"; then
        sudo cp -p "$cur" "$cur.darkosen"; echo "$b: dArkOSen's build kept as $cur.darkosen"
    fi
    sudo install -o root -g root -m 755 "/tmp/$b" "$cur"; rm -f "/tmp/$b"
    echo "$b: installed ($(md5sum "$cur" | cut -c1-8))"
done
cfgdir=/storage/.config/distribution/configs
if [ ! -e "$cfgdir/retrorun.cfg" ]; then
    sudo mkdir -p "$cfgdir" && sudo ln -s /home/ark/.config/retrorun.cfg "$cfgdir/retrorun.cfg"
    echo "default config path linked to /home/ark/.config/retrorun.cfg (Saturn through retrorun)"
fi
if [ -x /opt/system/Shortcuts.sh ]; then
    sudo /opt/system/Shortcuts.sh --repair
    sudo /opt/system/Shortcuts.sh --layout-report | grep '^retrorun'
    grep '^retrorun_hotkey' /home/ark/.config/retrorun.cfg || echo "(no retrorun_hotkey_* line: the universal layout is not on; Options > Shortcuts > Hotkey layout)"
else
    echo "Shortcuts.sh not installed: add the retrorun_hotkey_* lines to /home/ark/.config/retrorun.cfg by hand"
fi
REMOTE
echo "installed on $HOST"
