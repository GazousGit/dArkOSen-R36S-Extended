#!/bin/bash
# =======================================================
# dArkOSen-R36S-Extended: repair the model selector entries
# of a mounted BOOT partition.
#
#   fix-boot.sh BOOT_MOUNT
#
# The model selector copies one folder of BOOT/dtb/
# (boot.ini + device trees) to the root of the partition.
# Some folders name a kernel device tree they do not
# contain; in the 09302026 image:
#   r36s/R36S-V12 2023-08-18 Panel 4  loads rk3326-r36h-linux.dtb
#   r36s/HL-R46H-V22 2026-03-12       loads rk3326-r45h-linux.dtb
# The bootloader then starts the kernel without the board's
# device tree: picture and sound work, the controls do not
# (EmulationStation only sees the power button).
#
# When such a folder holds exactly one *-linux.dtb, its
# boot.ini is pointed at that file; line endings and the
# rest of the file are kept. Anything else is reported and
# left alone.
# =======================================================
set -euo pipefail

B="${1:?usage: fix-boot.sh BOOT_MOUNT}"
B="${B%/}"
[ -f "$B/boot.ini" ] || { echo "fix-boot: $B/boot.ini not found, not a BOOT partition" >&2; exit 1; }

FIXED=0
while IFS= read -r -d '' ini; do
    d=$(dirname "$ini"); rel=${d#"$B"}; rel=${rel#/}; rel=${rel:-.}
    want=$(sed -n 's/^.*load mmc [0-9:]* \${dtb_loadaddr} \([^[:space:]]*\.dtb\).*$/\1/p' "$ini" | tr -d '\r' | head -1)
    [ -n "$want" ] || continue
    [ -e "$d/$want" ] && continue
    mapfile -t have < <(find "$d" -maxdepth 1 -type f -iname '*-linux.dtb' -printf '%f\n')
    if [ ${#have[@]} -ne 1 ]; then
        echo "fix-boot: $rel: boot.ini loads $want, which is missing; ${#have[@]} candidate(s) there, left alone"
        continue
    fi
    sed -i "s|\(load mmc [0-9:]* \${dtb_loadaddr} \)${want//./\\.}|\1${have[0]}|" "$ini"
    echo "fix-boot: $rel: boot.ini loaded $want (not in the folder), now ${have[0]}"
    FIXED=$((FIXED + 1))
done < <(find "$B" -name boot.ini -type f -print0)
echo "fix-boot: $FIXED entr$([ "$FIXED" = 1 ] && echo y || echo ies) fixed"
