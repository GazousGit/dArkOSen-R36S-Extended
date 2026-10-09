#!/bin/bash
# =======================================================
# dArkOSen-R36S-Extended image build
#
# Takes an official dArkOSen release image, adds the boot
# video tool (+ self-repair service) and repacks it as a
# split .7z (parts < 2 GB, GitHub's release asset limit).
#
# Only the root filesystem (btrfs) is modified. The EASYROMS
# partition is left alone: dArkOSen's first boot re-creates
# it anyway, so shipped videos are stored on the root
# filesystem and copied to /roms/bootvideos at boot.
#
# Runs as root on Linux: the GitHub Actions ubuntu runner,
# or WSL/Ubuntu for a local build.
# Needs: curl jq 7z losetup blkid blockdev
# Optional: btrfs-progs (filesystem check), e2fsprogs
#
# Usage:
#   build-image.sh --tag 09302026 [options]
#   build-image.sh --img path/to/dArkOSen.img [options]
# Options:
#   --repo OWNER/REPO   upstream (default djparentx/dArkOSen-R36S)
#   --tag TAG           upstream release tag (default: latest)
#   --img FILE          use this image instead of downloading
#   --workdir DIR       scratch dir (default ./work)
#   --out DIR           output dir (default WORKDIR/out)
#   --videos DIR        videos to ship (seeded into /roms/bootvideos)
#   --level N           7z compression level 1-9 (default 5)
#   --split SIZE        7z volume size (default 1900m)
#   --name NAME         output base name
#                       (default dArkOSen-Extended_R36_<TAG>)
#   --keep-img          keep the modified .img
#   --no-pack           stop after modifying the image
# =======================================================
set -euo pipefail

REPO="djparentx/dArkOSen-R36S"
TAG=""; IMG=""; WORK="$PWD/work"; OUT=""; VIDEOS=""
LEVEL=5; SPLIT="1900m"; NAME=""; KEEP_IMG=0; NO_PACK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)     REPO=$2; shift 2 ;;
        --tag)      TAG=$2; shift 2 ;;
        --img)      IMG=$2; shift 2 ;;
        --workdir)  WORK=$2; shift 2 ;;
        --out)      OUT=$2; shift 2 ;;
        --videos)   VIDEOS=$2; shift 2 ;;
        --level)    LEVEL=$2; shift 2 ;;
        --split)    SPLIT=$2; shift 2 ;;
        --name)     NAME=$2; shift 2 ;;
        --keep-img) KEEP_IMG=1; shift ;;
        --no-pack)  NO_PACK=1; shift ;;
        -h|--help)  sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
INJECT="$HERE/inject.sh"
[ "$(id -u)" -eq 0 ] || { echo "build-image: run as root (sudo)" >&2; exit 1; }
for t in curl jq losetup blkid blockdev; do
    command -v "$t" >/dev/null || { echo "build-image: missing tool: $t" >&2; exit 1; }
done
SEVENZ=$(command -v 7z || command -v 7zz || true)
[ -n "$SEVENZ" ] || { echo "build-image: missing 7z (apt install p7zip-full)" >&2; exit 1; }
[ -n "$VIDEOS" ] && VIDEOS="$(cd "$VIDEOS" && pwd)"

mkdir -p "$WORK"; WORK="$(cd "$WORK" && pwd)"
OUT="${OUT:-$WORK/out}"; mkdir -p "$OUT" "$WORK/dl" "$WORK/img" "$WORK/mnt" "$WORK/probe"
LOG="$OUT/build.log"; : > "$LOG"
exec > >(tee -a "$LOG") 2>&1

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }
human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 B"; }

LOOP=""; MNT="$WORK/mnt"
cleanup() {
    set +e
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT"
    mountpoint -q "$WORK/probe" 2>/dev/null && umount "$WORK/probe"
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
    return 0
}
trap cleanup EXIT

log "dArkOSen-R36S-Extended image build"
log "work dir: $WORK ($(df -h --output=avail "$WORK" | tail -1 | tr -d ' ') free)"

# -------------------------------------------------------
# 1. Release metadata + download + extract
# -------------------------------------------------------
api() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -sSL --retry 5 -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
    else
        curl -sSL --retry 5 -H "Accept: application/vnd.github+json" "$@"
    fi
}

UPSTREAM_URL="https://github.com/$REPO/releases"
if [ -z "$IMG" ]; then
    if [ -z "$TAG" ]; then
        REL=$(api "https://api.github.com/repos/$REPO/releases/latest")
        TAG=$(jq -r '.tag_name // empty' <<<"$REL")
        [ -n "$TAG" ] || die "could not resolve the latest release of $REPO"
    else
        REL=$(api "https://api.github.com/repos/$REPO/releases/tags/$TAG")
        [ "$(jq -r '.tag_name // empty' <<<"$REL")" = "$TAG" ] || die "release $TAG not found in $REPO"
    fi
    UPSTREAM_URL=$(jq -r .html_url <<<"$REL")
    log "upstream release: $TAG ($UPSTREAM_URL)"

    mapfile -t ASSETS < <(jq -r '.assets[]
        | select(.name | test("\\.(7z(\\.[0-9]+)?|zip|img\\.xz|img\\.gz|img)$"))
        | "\(.name)\t\(.browser_download_url)\t\(.size)"' <<<"$REL" | sort)
    [ ${#ASSETS[@]} -gt 0 ] || die "release $TAG has no image assets"

    # Rough space check: archive parts + extracted image (~3x) + repacked archive
    TOTAL=0
    for a in "${ASSETS[@]}"; do IFS=$'\t' read -r _ _ asize <<<"$a"; TOTAL=$((TOTAL + asize)); done
    NEED=$((TOTAL * 5))
    FREE=$(( $(df --output=avail -k "$WORK" | tail -1 | tr -d ' ') * 1024 ))
    log "assets: $(human "$TOTAL"); need about $(human "$NEED"), have $(human "$FREE") in $WORK"
    [ "$FREE" -gt "$NEED" ] || die "not enough free space in $WORK (need about $(human "$NEED"))"
    log "7z: $("$SEVENZ" 2>/dev/null | sed -n '2p' | cut -c1-60)"

    for a in "${ASSETS[@]}"; do
        IFS=$'\t' read -r aname aurl asize <<<"$a"
        log "download $aname ($(human "$asize"))"
        curl -L --retry 10 --retry-all-errors --retry-delay 5 -C - -sS -o "$WORK/dl/$aname" "$aurl"
        got=$(stat -c %s "$WORK/dl/$aname")
        [ "$got" = "$asize" ] || die "$aname: downloaded $got bytes, expected $asize"
    done

    IFS=$'\t' read -r FIRST _ _ <<<"${ASSETS[0]}"
    log "extract $FIRST ($(df -h --output=avail "$WORK" | tail -1 | tr -d ' ') free)"
    case "$FIRST" in
        *.7z|*.7z.001) "$SEVENZ" x -y -bd -bb0 -o"$WORK/img" "$WORK/dl/$FIRST" > "$WORK/7z-extract.log" 2>&1 \
                           || { rc=$?; tail -n 15 "$WORK/7z-extract.log"; df -h "$WORK"; die "7z extraction failed (exit $rc)"; } ;;
        *.zip)         unzip -o -q "$WORK/dl/$FIRST" -d "$WORK/img" ;;
        *.img.xz)      xz -dc "$WORK/dl/$FIRST" > "$WORK/img/${FIRST%.xz}" ;;
        *.img.gz)      gzip -dc "$WORK/dl/$FIRST" > "$WORK/img/${FIRST%.gz}" ;;
        *.img)         mv "$WORK/dl/$FIRST" "$WORK/img/" ;;
        *)             die "do not know how to unpack $FIRST" ;;
    esac
    IMG=$(find "$WORK/img" -maxdepth 3 -type f -iname '*.img' -printf '%s %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
    [ -n "$IMG" ] || die "no .img file inside $FIRST"
    rm -rf "$WORK/dl"
else
    [ -f "$IMG" ] || die "image not found: $IMG"
    TAG="${TAG:-local}"
fi
IMG="$(readlink -f "$IMG")"
log "image: $IMG ($(human "$(stat -c %s "$IMG")"))"
log "free space now: $(df -h --output=avail "$WORK" | tail -1 | tr -d ' ')"

# -------------------------------------------------------
# 2. Find the root filesystem
# -------------------------------------------------------
grep -qw btrfs /proc/filesystems || modprobe btrfs 2>/dev/null || true

LOOP=$(losetup --find --show --partscan "$IMG")
udevadm settle 2>/dev/null || sleep 2
PARTS=("$LOOP"p*)
if [ ! -e "${PARTS[0]}" ]; then partprobe "$LOOP" 2>/dev/null || true; sleep 2; PARTS=("$LOOP"p*); fi
[ -e "${PARTS[0]}" ] || die "no partitions found on $IMG"

ROOTP=""; ROOTTYPE=""
for p in "${PARTS[@]}"; do
    t=$(blkid -o value -s TYPE "$p" 2>/dev/null || true)
    l=$(blkid -o value -s LABEL "$p" 2>/dev/null || true)
    sz=$(blockdev --getsize64 "$p")
    log "  $p  type=${t:-?}  label=${l:-}  size=$(human "$sz")"
    if [ -z "$ROOTP" ] && [[ "$t" =~ ^(ext2|ext3|ext4|btrfs|f2fs|xfs)$ ]]; then
        if mount -o ro "$p" "$WORK/probe" 2>/dev/null; then
            [ -f "$WORK/probe/usr/bin/emulationstation/emulationstation.sh" ] && { ROOTP=$p; ROOTTYPE=$t; }
            umount "$WORK/probe"
        else
            log "  (could not mount $p read-only to probe it)"
        fi
    fi
done
[ -n "$ROOTP" ] || die "could not find the dArkOSen root filesystem in the image"
log "root partition: $ROOTP ($ROOTTYPE)"

# -------------------------------------------------------
# 3. Check, mount, inject, unmount, check again
# -------------------------------------------------------
fscheck() {   # $1 device, $2 fs type, $3 log file -> prints the checker's exit code
    local rc=0
    case "$2" in
        ext2|ext3|ext4)
            if command -v e2fsck >/dev/null; then e2fsck -fn "$1" > "$3" 2>&1 || rc=$?
            else echo "skipped: e2fsprogs not installed" > "$3"; fi ;;
        btrfs)
            if command -v btrfs >/dev/null; then btrfs check --readonly "$1" > "$3" 2>&1 || rc=$?
            else echo "skipped: btrfs-progs not installed" > "$3"; fi ;;
        *)  echo "skipped: no checker for $2" > "$3" ;;
    esac
    echo "$rc"
}

FSCK_BEFORE=$(fscheck "$ROOTP" "$ROOTTYPE" "$WORK/fsck-before.log")
log "filesystem check (before): exit $FSCK_BEFORE ($(tail -1 "$WORK/fsck-before.log" | cut -c1-80))"

mount "$ROOTP" "$MNT"
ROOT_FREE=$(df --output=avail -k "$MNT" | tail -1 | tr -d ' ')
log "root filesystem mounted, $(human $((ROOT_FREE * 1024))) free"
[ "$ROOT_FREE" -gt 8192 ] || die "root filesystem has less than 8 MB free"

bash "$INJECT" "$MNT" "$VIDEOS" "$TAG"
STAMP=$(cat "$MNT/etc/dArkOSen-Extended.release")
SHIPPED=$(ls "$MNT/usr/share/dArkOSen-Extended/bootvideos" 2>/dev/null | wc -l)

sync
umount "$MNT"

FSCK_AFTER=$(fscheck "$ROOTP" "$ROOTTYPE" "$WORK/fsck-after.log")
log "filesystem check (after): exit $FSCK_AFTER ($(tail -1 "$WORK/fsck-after.log" | cut -c1-80))"
if [ "$FSCK_BEFORE" -eq 0 ] && [ "$FSCK_AFTER" -ne 0 ]; then
    cat "$WORK/fsck-after.log"
    die "root filesystem check failed after modification"
fi
losetup -d "$LOOP"; LOOP=""

# -------------------------------------------------------
# 4. Pack
# -------------------------------------------------------
NAME="${NAME:-dArkOSen-Extended_R36_$TAG}"
FINAL="$WORK/img/$NAME.img"
[ "$IMG" = "$FINAL" ] || mv "$IMG" "$FINAL"
if [ "$NO_PACK" = 1 ]; then
    log "image ready (not packed): $FINAL"
    exit 0
fi

rm -f "$OUT/$NAME".7z*
log "packing with 7z level $LEVEL, volumes of $SPLIT (this takes a while)"
"$SEVENZ" a -t7z -mx="$LEVEL" -mmt=on -v"$SPLIT" -bd -bb0 "$OUT/$NAME.7z" "$FINAL" >/dev/null
[ "$KEEP_IMG" = 1 ] || rm -f "$FINAL"
(cd "$OUT" && sha256sum "$NAME".7z.* > SHA256SUMS.txt)
log "packed:"
ls -l "$OUT"/"$NAME".7z.* | awk '{print "  " $5 "  " $9}'

# -------------------------------------------------------
# 5. Release notes
# -------------------------------------------------------
OURREPO="${GITHUB_REPOSITORY:-GazousGit/dArkOSen-R36S-Extended}"
{
    echo "# dArkOSen-Extended R36 - $TAG"
    echo
    echo "The official dArkOSen release [$TAG]($UPSTREAM_URL) by [djparentx](https://github.com/djparentx), with the **Boot Video Manager** pre-installed. Nothing else is changed; the device keeps receiving djparentx's OTA updates."
    echo
    echo "## Install"
    echo
    echo "1. Download **all** \`.7z.*\` parts into the same folder."
    echo "2. Extract the \`.001\` part with 7-Zip (the other parts are picked up automatically) to get the \`.img\`."
    echo "3. Flash the \`.img\` to your SD card exactly like the official image (Rufus, balenaEtcher, Win32DiskImager or \`dd\`), then run the model selector from the boot partition as described in the [dArkOSen README](https://github.com/$REPO#readme)."
    echo "4. Boot. The first boot sets up the EASYROMS partition and reboots, as with the official image."
    echo "5. Copy your videos (mp4, mkv, webm or gif) into the \`bootvideos\` folder on the EASYROMS partition (\`/roms/bootvideos\`, created at boot). From the next boot on, one of them plays at random before EmulationStation."
    echo
    echo "## What is added"
    echo
    echo "- **Boot Video Manager** in *Options > System*: on/off, random or fixed video, sound, max length, converter, preview, repair, uninstall."
    echo "- **Boot video at startup** (random, skip with A/B/X/Y/Start, volume keys keep working), enabled by default; nothing plays until there are videos in \`/roms/bootvideos\`."
    echo "- **\"Boot Videos\" system in EmulationStation** with thumbnails and video previews; press A on a video to preview it or to enable/disable it."
    echo "- **Self-repair service** (\`bootvideo-repair.service\`) that re-attaches the boot video if an OTA update replaces \`emulationstation.sh\` or \`es_systems.cfg\`."
    if [ "${SHIPPED:-0}" -gt 0 ]; then
        echo "- $SHIPPED boot video(s) shipped with the image; they are copied into \`/roms/bootvideos\` on the first regular boot."
    fi
    echo
    echo "Everything lives in [extended/](https://github.com/$OURREPO/tree/main/extended). Device-side files: \`/opt/system/System/Boot Video Manager.sh\`, \`/usr/local/bin/bootvideo.sh\`, \`/usr/local/bin/bootvideo-repair\`, \`/etc/systemd/system/bootvideo-repair.service\`, \`/home/ark/.config/bootvideo.conf\`, plus one tagged line in \`emulationstation.sh\` and one system in \`es_systems.cfg\`."
    echo
    echo "## Files"
    echo
    echo '| File | Size | SHA-256 |'
    echo '| --- | --- | --- |'
    while read -r sum f; do
        echo "| \`$f\` | $(human "$(stat -c %s "$OUT/$f")") | \`$sum\` |"
    done < "$OUT/SHA256SUMS.txt"
    echo
    echo "## Build"
    echo
    echo '```'
    echo "$STAMP"
    echo '```'
    echo
    echo "## Credits and license"
    echo
    echo "dArkOSen is made by [djparentx](https://github.com/$REPO) (MIT License), based on dArkOS and ArkOS. This repack only adds the boot video tool and is published under the same MIT terms. Please report emulator or system issues to the respective upstream projects, and boot video issues [here](https://github.com/$OURREPO/issues)."
} > "$OUT/RELEASE_NOTES.md"

log "done: $OUT"
