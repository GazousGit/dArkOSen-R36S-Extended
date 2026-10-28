#!/bin/bash
# =======================================================
# dArkOSen-R36S-Extended image build
#
# Takes an official dArkOSen release image, adds the boot
# video tool (+ self-repair service) and repacks it as a
# split .7z (parts < 2 GB, GitHub's release asset limit).
#
# The root filesystem (btrfs) gets our additions; on the BOOT
# partition only broken model selector entries are repaired
# (fix-boot.sh). The EASYROMS partition is left alone:
# dArkOSen's first boot re-creates
# it anyway, so shipped videos are stored on the root
# filesystem and copied to /roms/bootvideos at boot, and
# --roms files are appended to the /roms.tar that the first
# boot extracts into the new partition.
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
#   --roms DIR          files for the roms partition, laid out like
#                       /roms (local builds: extended/roms/README.md);
#                       the root partition is enlarged when they do
#                       not fit (grow-root.sh)
#   --level N           7z compression level 1-9 (default 5)
#   --split SIZE        7z volume size (default 1900m)
#   --name NAME         output base name
#                       (default dArkOSen-Extended_R36_<TAG>)
#   --retrorun-hotkeys DIR
#                       local builds: install the retrorun hotkeys build
#                       (DIR/retrorun, DIR/retrorun32 from
#                       components/retrorun_hotkeys/build.sh) over
#                       dArkOSen's binaries, which are kept as .darkosen
#   --keep-img          keep the modified .img
#   --no-pack           stop after modifying the image
# =======================================================
set -euo pipefail

REPO="djparentx/dArkOSen-R36S"
TAG=""; IMG=""; WORK="$PWD/work"; OUT=""; VIDEOS=""; ROMS=""; RRHK=""
LEVEL=5; SPLIT="1900m"; NAME=""; KEEP_IMG=0; NO_PACK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)     REPO=$2; shift 2 ;;
        --tag)      TAG=$2; shift 2 ;;
        --img)      IMG=$2; shift 2 ;;
        --workdir)  WORK=$2; shift 2 ;;
        --out)      OUT=$2; shift 2 ;;
        --videos)   VIDEOS=$2; shift 2 ;;
        --roms)     ROMS=$2; shift 2 ;;
        --retrorun-hotkeys) RRHK=$2; shift 2 ;;
        --level)    LEVEL=$2; shift 2 ;;
        --split)    SPLIT=$2; shift 2 ;;
        --name)     NAME=$2; shift 2 ;;
        --keep-img) KEEP_IMG=1; shift ;;
        --no-pack)  NO_PACK=1; shift ;;
        -h|--help)  sed -n '2,48p' "$0"; exit 0 ;;
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
[ -n "$RRHK" ] && RRHK="$(cd "$RRHK" && pwd)"
[ -n "$ROMS" ] && ROMS="$(cd "$ROMS" && pwd)"

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
    IMG=$(find "$WORK/img" -maxdepth 3 -type f -iname '*.img' -printf '%s %p\n' | sort -nr | sed -n '1p' | cut -d' ' -f2-)
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

ROOTP=""; ROOTTYPE=""; BOOTP=""
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
    if [ -z "$BOOTP" ] && [ "$t" = vfat ] && mount -o ro "$p" "$WORK/probe" 2>/dev/null; then
        [ -f "$WORK/probe/boot.ini" ] && [ -d "$WORK/probe/dtb" ] && BOOTP=$p
        umount "$WORK/probe"
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

# btrfs: write with the compression dArkOSen's own fstab uses (compress=zlib:1), forced so that
# appended data (roms.tar) is compressed as well; its kernel reads zlib extents
if [ "$ROOTTYPE" = btrfs ]; then mount -o compress-force=zlib:1 "$ROOTP" "$MNT"; else mount "$ROOTP" "$MNT"; fi
ROOT_FREE=$(df --output=avail -k "$MNT" | tail -1 | tr -d ' ')
log "root filesystem mounted, $(human $((ROOT_FREE * 1024))) free"

# --roms files that would not fit: make the root partition bigger first, by their raw size plus
# the reserve inject.sh keeps (compression only adds margin). dArkOSen's first boot grows it to
# about 11 GB anyway (expandtoexfat.sh); see grow-root.sh. Release builds have no --roms files.
GROWN=0
if [ -n "$ROMS" ] && [ "$ROOTTYPE" = btrfs ]; then
    mapfile -d '' rf < <(cd "$ROMS" && find . -mindepth 2 -type f ! -name .gitignore -print0)
    if [ ${#rf[@]} -gt 0 ]; then
        WANT=$(( $(cd "$ROMS" && printf '%s\0' "${rf[@]}" | du -ck --apparent-size --files0-from=- | tail -1 | cut -f1) + 32768 + 16384 ))
        if [ "$ROOT_FREE" -lt "$WANT" ]; then
            GROWN=$(( (WANT - ROOT_FREE + 65535) / 65536 * 64 ))           # MiB, in steps of 64
            log "--roms files need up to $((WANT / 1024)) MiB with the reserve, $((ROOT_FREE / 1024)) MiB free: root partition +$GROWN MiB"
            RNUM=${ROOTP##*p}; BNUM=${BOOTP##*p}
            umount "$MNT"; losetup -d "$LOOP"; LOOP=""
            bash "$HERE/grow-root.sh" "$IMG" "$RNUM" "$GROWN"
            LOOP=$(losetup --find --show --partscan "$IMG")
            udevadm settle 2>/dev/null || sleep 2
            ROOTP="${LOOP}p$RNUM"; [ -n "$BOOTP" ] && BOOTP="${LOOP}p$BNUM"
            mount -o compress-force=zlib:1 "$ROOTP" "$MNT"
            btrfs filesystem resize max "$MNT" > /dev/null
            ROOT_FREE=$(df --output=avail -k "$MNT" | tail -1 | tr -d ' ')
            log "root filesystem grown, $(human $((ROOT_FREE * 1024))) free; image $(human "$(stat -c %s "$IMG")")"
        fi
    fi
fi
[ "$ROOT_FREE" -gt 8192 ] || die "root filesystem has less than 8 MB free"

bash "$INJECT" "$MNT" "$VIDEOS" "$TAG" "$ROMS" "$RRHK"
STAMP=$(cat "$MNT/etc/dArkOSen-Extended.release")
ROMSFILES=$(sed -n 's/^DARKOSEN_EXTENDED_ROMS_FILES=//p' <<<"$STAMP")
SHIPPED=0
if [ -d "$MNT/usr/share/dArkOSen-Extended/bootvideos" ]; then
    SHIPPED=$(find "$MNT/usr/share/dArkOSen-Extended/bootvideos" -maxdepth 1 -type f | wc -l)
fi

sync
log "root filesystem after the changes: $(human $(( $(df --output=avail -k "$MNT" | tail -1 | tr -d ' ') * 1024 ))) free"
umount "$MNT"

FSCK_AFTER=$(fscheck "$ROOTP" "$ROOTTYPE" "$WORK/fsck-after.log")
log "filesystem check (after): exit $FSCK_AFTER ($(tail -1 "$WORK/fsck-after.log" | cut -c1-80))"
if [ "$FSCK_BEFORE" -eq 0 ] && [ "$FSCK_AFTER" -ne 0 ]; then
    cat "$WORK/fsck-after.log"
    die "root filesystem check failed after modification"
fi
# BOOT partition: model selector entries whose boot.ini names a device tree that is not there
BOOTFIXED=0
if [ -n "$BOOTP" ]; then
    mount "$BOOTP" "$WORK/probe"
    bash "$HERE/fix-boot.sh" "$WORK/probe" | tee "$WORK/fix-boot.log"
    BOOTFIXED=$(sed -n 's/^fix-boot: \([0-9]*\) entr.* fixed$/\1/p' "$WORK/fix-boot.log")
    sync; umount "$WORK/probe"
    if command -v fsck.vfat >/dev/null; then
        fsck.vfat -n "$BOOTP" > "$WORK/fsck-boot.log" 2>&1 || die "BOOT partition check failed after the repair: $(tail -3 "$WORK/fsck-boot.log" | tr '\n' ' ')"
        log "BOOT partition check: clean"
    fi
else
    log "no BOOT partition with a model selector found; nothing to repair there"
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
    echo "- **Boot Video Manager** in *Options > System*: on/off, random or fixed video, which videos play (all, none, search, playlists), sound, volume, max length, converter, preview, repair, uninstall."
    echo "- **Boot video at startup** (random, skip with A/B/X/Y/Start, volume keys keep working), enabled by default; nothing plays until there are videos in \`/roms/bootvideos\`."
    echo "- **\"Boot Videos\" system in EmulationStation** with thumbnails and video previews; press A on a video to preview it or to enable/disable it."
    echo "- **Self-repair service** (\`bootvideo-repair.service\`) that re-attaches the boot video if an OTA update replaces \`emulationstation.sh\` or \`es_systems.cfg\`."
    if [ "${SHIPPED:-0}" -gt 0 ]; then
        echo "- $SHIPPED boot video(s) shipped with the image; they are copied into \`/roms/bootvideos\` on the first regular boot."
    fi
    if [ "${BOOTFIXED:-0}" -gt 0 ]; then
        echo "- **Model selector repaired**: $BOOTFIXED entries (\`R36S-V12 2023-08-18 Panel 4\` among them) had a \`boot.ini\` that loads a device tree missing from their folder, so the kernel started without the board's device tree: picture and sound, but no controls. They now load the device tree of their own folder."
    fi
    if [ "${ROMSFILES:-0}" -gt 0 ]; then
        echo "- $ROMSFILES personal file(s) for the roms partition, extracted into \`/roms\` by the first boot. **This image is a private build: do not publish or share it.**"
    fi
    echo "- **Extra tools** in *Options > Advanced*: \"Swap A-B in EmulationStation only\" (flip A/B in ES without touching the emulators), \"Dreamcast Tuning (retrorun)\" (320x240 internal resolution and the other speed options RetroArch32 uses, with backup/restore and an FPS counter), \"N64 Tuning (mupen64plus-next)\" (the wiki settings, toggles, per-game option files) and \"PPSSPP Sync standalone and 2021\" (share per-game settings between the two PPSSPP builds)."
    echo "- **Shortcuts** in *Options*: pages with the key combinations of the system, of EmulationStation and of the emulators (quit, menu, save states), and a **reminder before each game** (10 s, or A to go on) with the page of the emulator about to start, button names in the colours of the R36S. On/off and duration in the tool; the texts can be replaced by your own files in \`/roms/shortcuts\`."
    echo "- **Universal hotkey layout** in RetroArch (every core, 64 and 32-bit), DuckStation, PPSSPP 1.20, the standalone N64 emulator, Flycast standalone and DraStic: **FN = menu, SELECT + START = quit, SELECT + R1 / L1 = save / load state, SELECT + R2 / L2 = next / previous slot, SELECT + L3 = fast-forward**, plus SELECT + LEFT rewind, B reset, A screenshot, Y pause where the emulator has them (Flycast and DraStic take single buttons only: FN opens their menu, states inside). Holding SELECT no longer opens the RetroArch menu, and SELECT + UP no longer freezes the game (dArkOSen binds it to frame advance). The Wi-Fi / Bluetooth toggles of the hotkey daemon (SELECT + L1 / R1) are off while a game runs. Yabasanshiro keeps its own keys; retrorun (keys compiled in) follows once the opt-in retrorun hotkeys build of components/retrorun_hotkeys/ is installed over SSH (not part of the image). *Options > Shortcuts > Hotkey layout* puts dArkOSen's own values back."
    echo "- **N64 settings of the ArkOS wiki pre-applied** for the RetroArch cores \`mupen64plus_next\` and \`mupen64plus\`: 320x240, threaded renderer, hybrid filter, color buffer copy and overscan off, framebuffer and LOD emulation left on (dArkOS ships the cores at their defaults). **The N64 default emulator in EmulationStation is \`retroarch\` / \`mupen64plus_next\`** instead of dArkOSen's \`retroarch32\` / \`parallel_n64\`, as the per-game list of [R36S-Game-Compatibility-Lists](https://github.com/GazousGit/R36S-Game-Compatibility-Lists) assumes; per-game choices in \`gamelist.xml\` are untouched, and N64 > Advanced System Options in ES changes it back."
    echo
    echo "> **After flashing, run *Options > System > Update-dArkOSen* once.** The official 09302026 image needs djparentx's 09302026b update, otherwise 32-bit emulators (retrorun32, retroarch32: Dreamcast, Naomi and others) have no sound. This repack does not include OTA updates."
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
