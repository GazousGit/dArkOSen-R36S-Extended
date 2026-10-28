#!/bin/bash
# Put dArkOSen's own retrorun and retrorun32 back on a device (from the .darkosen copies
# that device-install.sh kept), drop the retrorun_hotkey_* lines from retrorun.cfg and the
# link on the default config path. Over SSH from WSL. Refuses to run while retrorun runs.
# Safe to run twice.
#
# usage: device-remove.sh [host]      (default 192.168.1.159, user ark / ark)

set -euo pipefail

HOST=${1:-192.168.1.159}
SSH=(sshpass -p ark ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ark@$HOST")

"${SSH[@]}" 'bash -s' <<'REMOTE'
set -euo pipefail
if pgrep -x retrorun >/dev/null || pgrep -x retrorun32 >/dev/null; then
    echo "retrorun is running, not touching anything:"; pgrep -a "retrorun"; exit 3
fi
for b in retrorun retrorun32; do
    cur=/usr/local/bin/$b
    if [ -f "$cur.darkosen" ]; then
        sudo mv -f "$cur.darkosen" "$cur"; sudo chmod 755 "$cur"; echo "$b: dArkOSen's build restored"
    elif grep -q retrorun_hotkey_menu "$cur" 2>/dev/null; then
        echo "$b: the hotkeys build is installed but no $cur.darkosen copy exists: reinstall dArkOSen's binary by hand (OTA update or image)" >&2
    else
        echo "$b: already dArkOSen's build"
    fi
done
cfg=/home/ark/.config/retrorun.cfg
if grep -q '^retrorun_hotkey_' "$cfg" 2>/dev/null; then
    sed -i '/^retrorun_hotkey_/d' "$cfg"; echo "retrorun.cfg: retrorun_hotkey_* lines removed"
fi
link=/storage/.config/distribution/configs/retrorun.cfg
if [ -L "$link" ]; then sudo rm -f "$link"; echo "default config path link removed"; fi
[ -x /opt/system/Shortcuts.sh ] && sudo /opt/system/Shortcuts.sh --layout-report | grep '^retrorun'
REMOTE
echo "removed from $HOST"
