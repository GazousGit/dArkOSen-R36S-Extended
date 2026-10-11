#!/bin/bash
# =======================================================
# dArkOSen-R36S-Extended: apply our additions to a mounted
# dArkOSen root filesystem.
#
#   inject.sh ROOT [VIDEOS_DIR] [UPSTREAM_TAG]
#
# ROOT        mount point of the image's root filesystem
# VIDEOS_DIR  optional folder whose videos (mp4 mkv webm gif)
#             are shipped in the image. They are stored on the
#             root filesystem and copied into /roms/bootvideos
#             by the self-repair service at boot, because the
#             EASYROMS partition is re-created on first boot.
#
# Also copies extended/overlay/ (extra tools, laid out like
# the device tree) into the root filesystem, plus a copy in
# /usr/share/dArkOSen-Extended/overlay so the self-repair
# service can restore files an OTA update removed.
#
# Everything that touches system files is done by
# "Boot Video Manager.sh --install-root", the same code
# that repairs the device after an OTA update.
# =======================================================
set -euo pipefail

ROOT="${1:?usage: inject.sh ROOT [VIDEOS_DIR] [TAG]}"
VIDEOS="${2:-}"
TAG="${3:-dev}"
ROOT="${ROOT%/}"
SEED="$ROOT/usr/share/dArkOSen-Extended/bootvideos"
OVERLAY_SEED="$ROOT/usr/share/dArkOSen-Extended/overlay"

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TOOL="$HERE/../bootvideo/Boot Video Manager.sh"
OVERLAY="$HERE/../overlay"
[ -f "$TOOL" ] || { echo "inject: $TOOL not found" >&2; exit 1; }
[ -f "$ROOT/usr/bin/emulationstation/emulationstation.sh" ] || { echo "inject: $ROOT is not a dArkOSen root" >&2; exit 1; }

# Videos shipped with the image (optional)
rm -rf "$SEED"
if [ -n "$VIDEOS" ] && [ -d "$VIDEOS" ]; then
    shopt -s nullglob nocaseglob
    vids=("$VIDEOS"/*.mp4 "$VIDEOS"/*.mkv "$VIDEOS"/*.webm "$VIDEOS"/*.gif)
    shopt -u nullglob nocaseglob
    if [ ${#vids[@]} -eq 0 ]; then
        echo "inject: no videos in $VIDEOS (nothing shipped)"
    else
        mkdir -p "$SEED"
        for v in "${vids[@]}"; do
            echo "inject: shipping video $(basename "$v") ($(du -h "$v" | cut -f1))"
            cp -f "$v" "$SEED/"
        done
        chmod 755 "$SEED"; chmod 644 "$SEED"/*
    fi
fi

# Extra tools (overlay): copied to their device paths and kept as a seed copy
rm -rf "$OVERLAY_SEED"
NOVERLAY=0
if [ -d "$OVERLAY" ]; then
    while IFS= read -r f; do
        f=${f#./}
        case "$f" in README.md|*/README.md) continue ;; esac
        mkdir -p "$ROOT/$(dirname "$f")" "$OVERLAY_SEED/$(dirname "$f")"
        cp -f "$OVERLAY/$f" "$ROOT/$f"
        cp -f "$OVERLAY/$f" "$OVERLAY_SEED/$f"
        case "$f" in
            *.sh|usr/local/bin/*) chmod 755 "$ROOT/$f" "$OVERLAY_SEED/$f" ;;
            *)                    chmod 644 "$ROOT/$f" "$OVERLAY_SEED/$f" ;;
        esac
        echo "inject: overlay /$f"
        NOVERLAY=$((NOVERLAY + 1))
    done < <(cd "$OVERLAY" && find . -type f | sort)
fi

# Presets applied to the image itself (each tool can undo them on the device)
N64TOOL="$OVERLAY/opt/system/Advanced/N64 Tuning (mupen64plus-next).sh"
RACO="$ROOT/home/ark/.config/retroarch/retroarch-core-options.cfg"
if [ -f "$N64TOOL" ] && [ -f "$RACO" ]; then
    bash "$N64TOOL" --fast "$RACO"
    echo "inject: N64 preset -> $(grep -c '^mupen64plus-' "$RACO") mupen64plus lines in ${RACO#"$ROOT"}"
fi

echo "inject: installing Boot Video Manager into $ROOT"
bash "$TOOL" --install-root "$ROOT"

# Build stamp (for support and to show where the image came from)
cat > "$ROOT/etc/dArkOSen-Extended.release" <<EOF
DARKOSEN_EXTENDED_UPSTREAM_TAG=$TAG
DARKOSEN_EXTENDED_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DARKOSEN_EXTENDED_COMMIT=${GITHUB_SHA:-local}
DARKOSEN_EXTENDED_TREE=${EXTENDED_TREE:-unknown}
DARKOSEN_EXTENDED_REPO=${GITHUB_REPOSITORY:-GazousGit/dArkOSen-R36S-Extended}
EOF

echo "inject: done"
echo "inject: hook      -> $(grep -c '# bootvideo-hook' "$ROOT/usr/bin/emulationstation/emulationstation.sh") line(s) in emulationstation.sh"
echo "inject: ES entry  -> $(grep -c '<name>bootvideos</name>' "$ROOT/etc/emulationstation/es_systems.cfg" 2>/dev/null || echo 0) system(s) in es_systems.cfg"
echo "inject: service   -> $(readlink "$ROOT/etc/systemd/system/multi-user.target.wants/bootvideo-repair.service" 2>/dev/null || echo MISSING)"
echo "inject: config    -> $(tr '\n' ' ' < "$ROOT/home/ark/.config/bootvideo.conf")"
echo "inject: shipped   -> $(ls "$SEED" 2>/dev/null | wc -l) video(s) in ${SEED#"$ROOT"}"
echo "inject: overlay   -> $NOVERLAY file(s)"
