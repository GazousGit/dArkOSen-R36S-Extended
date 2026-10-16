#!/bin/bash
# =======================================================
# dArkOSen-R36S-Extended: apply our additions to a mounted
# dArkOSen root filesystem.
#
#   inject.sh ROOT [VIDEOS_DIR] [UPSTREAM_TAG] [ROMS_DIR]
#
# ROOT        mount point of the image's root filesystem
# VIDEOS_DIR  optional folder whose videos (mp4 mkv webm gif)
#             are shipped in the image. They are stored on the
#             root filesystem and copied into /roms/bootvideos
#             by the self-repair service at boot, because the
#             EASYROMS partition is re-created on first boot.
# ROMS_DIR    optional folder laid out like /roms (bios/...,
#             psp/...). Its files are appended to the image's
#             /roms.tar, which dArkOSen's first boot extracts
#             into the new EASYROMS partition; themes/<name>/
#             goes to /tempthemes, which the first boot copies
#             to /roms/themes. ROMS_DIR/es_settings.cfg lines
#             go into EmulationStation's settings. Local builds
#             only: see extended/roms/README.md.
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

ROOT="${1:?usage: inject.sh ROOT [VIDEOS_DIR] [TAG] [ROMS_DIR]}"
VIDEOS="${2:-}"
TAG="${3:-dev}"
ROMSDIR="${4:-}"
ROOT="${ROOT%/}"
SEED="$ROOT/usr/share/dArkOSen-Extended/bootvideos"
OVERLAY_SEED="$ROOT/usr/share/dArkOSen-Extended/overlay"
ROMSTAR="$ROOT/roms.tar"
ROMS_RESERVE_KB=32768      # free space that must remain on the root filesystem

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

# Files for the roms partition (optional): appended to /roms.tar, so dArkOSen's own
# first boot puts them in place. Only files inside a top folder are taken (a README
# next to the folders is not), and a file dArkOSen already ships is never replaced.
# themes/<name>/ goes to /tempthemes instead when the image has one: its first boot
# copies that folder into /roms/themes and deletes it, while roms.tar stays on the
# root filesystem since 10152026. A theme dArkOSen ships is not replaced either.
NROMS=0; NTHEMES=0
if [ -n "$ROMSDIR" ] && [ -d "$ROMSDIR" ]; then
    mapfile -t rfiles < <(cd "$ROMSDIR" && find . -mindepth 2 -type f ! -name .gitignore | sed 's|^\./||' | LC_ALL=C sort)
    TT="$ROOT/tempthemes"
    declare -A tshipped=() tseen=()
    if [ -d "$TT" ]; then
        while IFS= read -r -d '' e; do tshipped["$(basename "${e,,}")"]=1; done < <(find "$TT" -mindepth 1 -maxdepth 1 -print0)
    fi
    tarfiles=(); tfiles=(); themes=()
    for f in "${rfiles[@]}"; do
        if [ -d "$TT" ] && [[ "$f" == themes/*/* ]]; then
            t=${f#themes/}; t=${t%%/*}
            if [ -n "${tshipped[${t,,}]:-}" ]; then
                [ -n "${tseen[$t]:-}" ] || echo "inject: theme $t is already in /tempthemes, not replaced"
            else
                tfiles+=("$f"); [ -n "${tseen[$t]:-}" ] || themes+=("$t")
            fi
            tseen[$t]=1
        else
            tarfiles+=("$f")
        fi
    done
    add=(); nbefore=0
    if [ ${#tarfiles[@]} -gt 0 ]; then
        [ -f "$ROMSTAR" ] || { echo "inject: /roms.tar not found in the image, cannot ship files for the roms partition" >&2; exit 1; }
        declare -A shipped=()
        while IFS= read -r m; do
            [ -n "$m" ] || continue
            shipped["${m,,}"]=1; nbefore=$((nbefore + 1))     # EASYROMS is exFAT: names are case-insensitive
        done < <(tar -tf "$ROMSTAR")
        for f in "${tarfiles[@]}"; do
            k="roms/${f,,}"
            if [ -n "${shipped[$k]:-}" ]; then
                echo "inject: roms/$f is already in roms.tar, not replaced"
            else
                add+=("$f")
            fi
        done
    fi
    est=("${add[@]}" "${tfiles[@]}")
    if [ ${#rfiles[@]} -eq 0 ]; then
        echo "inject: no files in $ROMSDIR (nothing added to roms.tar)"
    elif [ ${#est[@]} -gt 0 ]; then
        rawkb() { [ $# -eq 0 ] && { echo 0; return; }; (cd "$ROMSDIR" && printf '%s\0' "$@" | du -ck --apparent-size --files0-from=- | tail -1 | cut -f1); }
        need=$(( $(rawkb "${est[@]}") + ${#est[@]} ))      # plus the tar header and padding of each file
        # A root mounted with compression (build-image.sh uses dArkOSen's own zlib) stores the
        # files compressed: estimate with gzip -1, plus 10 % for btrfs' per-extent compression
        case ",$(findmnt -no OPTIONS --target "$ROOT" 2>/dev/null)," in
            *,compress*) need=$(( $(cd "$ROMSDIR" && printf '%s\0' "${est[@]}" | tar -cf - --null -T - | gzip -1 | wc -c) / 1024 * 11 / 10 )) ;;
        esac
        free=$(df --output=avail -k "$ROOT" | tail -1 | tr -d ' ')
        if [ $((free - need)) -lt "$ROMS_RESERVE_KB" ]; then
            echo "inject: the files for the roms partition need $((need / 1024)) MB, the root filesystem has $((free / 1024)) MB free and $((ROMS_RESERVE_KB / 1024)) MB must remain" >&2
            exit 1
        fi
        if [ ${#add[@]} -gt 0 ]; then
            (cd "$ROMSDIR" && printf '%s\0' "${add[@]}" \
                | tar -rf "$ROMSTAR" --null -T - --transform 's|^|roms/|' --owner=0 --group=0 --mode='u=rwX,go=rX')
            sync -f "$ROMSTAR"
            nafter=$(tar -tf "$ROMSTAR" | wc -l)
            if [ "$nafter" -ne $((nbefore + ${#add[@]})) ]; then
                echo "inject: roms.tar lists $nafter entries after the append, expected $((nbefore + ${#add[@]}))" >&2
                exit 1
            fi
        fi
        mid=$(df --output=avail -k "$ROOT" | tail -1 | tr -d ' ')
        for t in "${themes[@]}"; do
            cp -r "$ROMSDIR/themes/$t" "$TT/"
            chown -R --reference="$TT" "$TT/$t"; chmod -R u=rwX,go=rX "$TT/$t"
        done
        sync -f "$ROOT"
        left=$(df --output=avail -k "$ROOT" | tail -1 | tr -d ' ')
        if [ "$left" -lt "$ROMS_RESERVE_KB" ]; then                 # the estimate was too optimistic
            echo "inject: only $((left / 1024)) MB left on the root filesystem after adding the files ($((ROMS_RESERVE_KB / 1024)) MB must remain)" >&2
            exit 1
        fi
        NROMS=${#add[@]}; NTHEMES=${#themes[@]}
        [ "$NROMS" -eq 0 ] || echo "inject: roms.tar +$NROMS file(s), $(( ($(rawkb "${add[@]}") + NROMS) / 1024 )) MB, $(((free - mid) / 1024)) MB used on the root filesystem:$(printf '%s\n' "${add[@]}" | cut -d/ -f1 | sort | uniq -c | awk '{printf " %s (%s)", $2, $1}')"
        [ "$NTHEMES" -eq 0 ] || echo "inject: /tempthemes +$NTHEMES theme(s), $(( $(rawkb "${tfiles[@]}") / 1024 )) MB, $(((mid - left) / 1024)) MB used on the root filesystem: ${themes[*]}"
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
    bash "$N64TOOL" --wiki "$RACO"
    echo "inject: N64 preset -> $(grep -c '^mupen64plus-' "$RACO") mupen64plus lines in ${RACO#"$ROOT"}"
fi
ESSET="$ROOT/home/ark/.emulationstation/es_settings.cfg"
if [ -f "$N64TOOL" ] && [ -f "$ESSET" ]; then
    bash "$N64TOOL" --es-default "$ESSET"
    echo "inject: N64 default emulator -> $(grep -c '<string name="n64\.' "$ESSET") line(s) in ${ESSET#"$ROOT"} (retroarch / mupen64plus_next)"
fi

# EmulationStation settings for local builds (optional): ROMS_DIR/es_settings.cfg holds
# lines in ES's own format, e.g. <string name="GamelistViewStyle" value="video" />.
# Each one replaces the image's line of the same name or is added; anything else is ignored.
NES=0
if [ -n "$ROMSDIR" ] && [ -f "$ROMSDIR/es_settings.cfg" ]; then
    [ -f "$ESSET" ] || { echo "inject: ${ESSET#"$ROOT"} not found, cannot apply es_settings.cfg" >&2; exit 1; }
    tmp="$ESSET.tmp"; cp "$ESSET" "$tmp"
    re='^[[:space:]]*(<(bool|int|float|string)[[:space:]]+name="([^"]+)"[[:space:]]+value="[^"]*"[[:space:]]*/>)[[:space:]]*$'
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}; line=${line#$'\xef\xbb\xbf'}         # files saved by Windows editors
        [[ "$line" =~ $re ]] || continue
        entry=${BASH_REMATCH[1]}; name=${BASH_REMATCH[3]}
        grep -vF "name=\"$name\" " "$tmp" > "$tmp.2" || :
        mv "$tmp.2" "$tmp"
        [ -z "$(tail -c1 "$tmp")" ] || echo >> "$tmp"
        if grep -q '</config>' "$tmp"; then
            awk -v e="$entry" '/<\/config>/ && !done { print e; done = 1 } { print }' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
        else
            printf '%s\n' "$entry" >> "$tmp"
        fi
        NES=$((NES + 1))
    done < "$ROMSDIR/es_settings.cfg"
    cat "$tmp" > "$ESSET"; rm -f "$tmp"                          # keeps the file's owner (ark)
    echo "inject: es_settings.cfg -> $NES setting(s) in ${ESSET#"$ROOT"}"
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
DARKOSEN_EXTENDED_ROMS_FILES=$NROMS
DARKOSEN_EXTENDED_THEMES=$NTHEMES
DARKOSEN_EXTENDED_ES_SETTINGS=$NES
EOF

echo "inject: done"
echo "inject: hook      -> $(grep -c '# bootvideo-hook' "$ROOT/usr/bin/emulationstation/emulationstation.sh") line(s) in emulationstation.sh"
echo "inject: ES entry  -> $(grep -c '<name>bootvideos</name>' "$ROOT/etc/emulationstation/es_systems.cfg" 2>/dev/null || echo 0) system(s) in es_systems.cfg"
echo "inject: service   -> $(readlink "$ROOT/etc/systemd/system/multi-user.target.wants/bootvideo-repair.service" 2>/dev/null || echo MISSING)"
echo "inject: config    -> $(tr '\n' ' ' < "$ROOT/home/ark/.config/bootvideo.conf")"
echo "inject: shipped   -> $(ls "$SEED" 2>/dev/null | wc -l) video(s) in ${SEED#"$ROOT"}"
echo "inject: overlay   -> $NOVERLAY file(s)"
echo "inject: roms      -> $NROMS file(s) appended to /roms.tar"
echo "inject: themes    -> $NTHEMES theme(s) added to /tempthemes"
echo "inject: settings  -> $NES line(s) from es_settings.cfg"
