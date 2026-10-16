#!/bin/bash
# =======================================================
# dArkOSen-R36S-Extended: make room on the root partition
# of an image (local builds whose personal files do not fit).
#
#   grow-root.sh IMG PARTNUM MIB
#
# The image file grows by MIB MiB, partition PARTNUM grows by
# the same amount and every partition after it moves along,
# data included. In dArkOSen that is only EASYROMS, which the
# first boot (/boot/expandtoexfat.sh) stretches to the end of
# the card, then re-creates right after the end of partition 2
# once that one is grown to about 11 GB: nothing there depends
# on where the partitions start.
# The filesystem inside PARTNUM is not touched; build-image.sh
# resizes it once mounted. MBR (dos) partition tables only.
# =======================================================
set -euo pipefail

usage="usage: grow-root.sh IMG PARTNUM MIB"
IMG=${1:?$usage}; N=${2:?$usage}; MIB=${3:?$usage}
[[ "$N" =~ ^[1-4]$ && "$MIB" =~ ^[1-9][0-9]*$ ]] || { echo "grow-root: $usage" >&2; exit 2; }
[ -f "$IMG" ] || { echo "grow-root: $IMG not found" >&2; exit 1; }
for t in sfdisk jq dd truncate; do
    command -v "$t" >/dev/null || { echo "grow-root: missing tool: $t" >&2; exit 1; }
done

table() { sfdisk -J "$IMG"; }
parts() {   # "number start size type" per partition, in disk order
    table | jq -r --arg img "$IMG" '.partitiontable.partitions[]
        | "\(.node | ltrimstr($img)) \(.start) \(.size) \(.type)"' | sort -k2,2n
}
T=$(table)
[ "$(jq -r .partitiontable.label <<<"$T")" = dos ] || { echo "grow-root: only MBR (dos) partition tables" >&2; exit 1; }
ID=$(jq -r .partitiontable.id <<<"$T")
SS=$(jq -r '.partitiontable.sectorsize // 512' <<<"$T")
GROW=$((MIB * 1048576 / SS))

start=""; size=""; later=()
while read -r num pstart psize ptype; do
    case "$ptype" in 5|f|85) echo "grow-root: extended partitions are not supported" >&2; exit 1 ;; esac
    if [ "$num" = "$N" ]; then start=$pstart; size=$psize
    elif [ -n "$start" ]; then
        [ "$pstart" -ge $((start + size)) ] || { echo "grow-root: partition $num overlaps partition $N" >&2; exit 1; }
        later+=("$num $pstart $psize")
    fi
done < <(parts)
[ -n "$start" ] || { echo "grow-root: no partition $N in $IMG" >&2; exit 1; }

truncate -s $(( $(stat -c %s "$IMG") + GROW * SS )) "$IMG"
# Last partition first; each goes through a temporary file because old and new places may overlap
sf=(sfdisk --no-reread --no-tell-kernel --wipe never --wipe-partitions never -q)
for ((i = ${#later[@]} - 1; i >= 0; i--)); do
    read -r num pstart psize <<<"${later[$i]}"
    tmp=$(mktemp "$IMG.part$num.XXXXXX")
    dd if="$IMG" of="$tmp" bs=1M iflag=skip_bytes,count_bytes skip=$((pstart * SS)) count=$((psize * SS)) status=none
    dd if="$tmp" of="$IMG" bs=1M oflag=seek_bytes seek=$(((pstart + GROW) * SS)) conv=notrunc status=none
    rm -f "$tmp"
    echo "start=$((pstart + GROW)), size=$psize" | "${sf[@]}" -N "$num" "$IMG" >/dev/null
done
echo "start=$start, size=$((size + GROW))" | "${sf[@]}" -N "$N" "$IMG" >/dev/null

# Check the result: same disk id, partition N bigger, the others moved, nothing else changed
[ "$(table | jq -r .partitiontable.id)" = "$ID" ] || { echo "grow-root: disk identifier changed" >&2; exit 1; }
want=$(for p in "${later[@]}"; do read -r num pstart psize <<<"$p"; echo "$num $((pstart + GROW)) $psize"; done)
got=$(parts | awk -v n="$N" '$1 == n { found = 1; next } found { print $1, $2, $3 }')
[ "$got" = "$want" ] || { echo "grow-root: unexpected partition table after the move" >&2; table >&2; exit 1; }
[ "$(parts | awk -v n="$N" '$1 == n { print $2, $3 }')" = "$start $((size + GROW))" ] || { echo "grow-root: partition $N was not grown" >&2; exit 1; }
echo "grow-root: partition $N +$MIB MiB ($size -> $((size + GROW)) sectors), ${#later[@]} partition(s) after it moved"
