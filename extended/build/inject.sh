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

ROOT="${1:?usage: inject.sh ROOT [VIDEOS_DIR] [TAG] [ROMS_DIR] [RETRORUN_HOTKEYS_DIR]}"
VIDEOS="${2:-}"
TAG="${3:-dev}"
ROMSDIR="${4:-}"
RRDIR="${5:-}"
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
# retrorun hotkeys build (local builds only: the binaries are not in the repository, see
# components/retrorun_hotkeys/). dArkOSen's binaries stay next to them as .darkosen, as
# device-install.sh does; the default config path retrorun uses without -c (Saturn's launcher)
# is linked to dArkOSen's retrorun.cfg. The layout step below then fills in the retrorun lines.
NRR=0
if [ -n "$RRDIR" ]; then
    for b in retrorun retrorun32; do
        [ -f "$RRDIR/$b" ] || { echo "inject: $RRDIR/$b not found" >&2; exit 1; }
        grep -q retrorun_hotkey_menu "$RRDIR/$b" || { echo "inject: $RRDIR/$b is not the retrorun hotkeys build" >&2; exit 1; }
        cur="$ROOT/usr/local/bin/$b"
        [ -f "$cur" ] || { echo "inject: $cur not found in the image" >&2; exit 1; }
        grep -q retrorun_hotkey_menu "$cur" || cp -p "$cur" "$cur.darkosen"
        cp -f "$RRDIR/$b" "$cur"; chmod 755 "$cur"; chown --reference="$cur.darkosen" "$cur"
        NRR=$((NRR + 1))
    done
    mkdir -p "$ROOT/storage/.config/distribution/configs"
    ln -sfn /home/ark/.config/retrorun.cfg "$ROOT/storage/.config/distribution/configs/retrorun.cfg"
    echo "inject: retrorun hotkeys build -> $NRR binaries in /usr/local/bin (dArkOSen's kept as .darkosen)"
fi
# Universal hotkey layout (RetroArch 64/32 and the standalone N64 emulator get DuckStation's
# SELECT + ... combinations; Options > Shortcuts switches back to dArkOSen's values)
SCTOOL="$OVERLAY/opt/system/Shortcuts.sh"
if [ -f "$SCTOOL" ]; then
    SHORTCUTS_ROOT="$ROOT" bash "$SCTOOL" --layout universal
    echo "inject: hotkey layout -> $(SHORTCUTS_ROOT="$ROOT" bash "$SCTOOL" --layout-status)"
fi

# EmulationStation settings for local builds (optional): ROMS_DIR/es_settings.cfg holds
# lines in ES's own format, e.g. <string name="GamelistViewStyle" value="video" />.
# Each one replaces the image's line of the same name or is added; anything else is ignored.
# Two names do what ES's own menu does instead of going into the file: system.timezone links
# /etc/localtime and is kept in ~/.emulationstation.conf (where ES reads it), and InvertButtons
# true / false runs dArkOSen's global A/B swap (b_swap.sh: US / JP) if the image is the other way.
NES=0; TZ_WANT=""; AB_WANT=""
if [ -n "$ROMSDIR" ] && [ -f "$ROMSDIR/es_settings.cfg" ]; then
    [ -f "$ESSET" ] || { echo "inject: ${ESSET#"$ROOT"} not found, cannot apply es_settings.cfg" >&2; exit 1; }
    tmp="$ESSET.tmp"; cp "$ESSET" "$tmp"
    re='^[[:space:]]*(<(bool|int|float|string)[[:space:]]+name="([^"]+)"[[:space:]]+value="([^"]*)"[[:space:]]*/>)[[:space:]]*$'
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}; line=${line#$'\xef\xbb\xbf'}         # files saved by Windows editors
        [[ "$line" =~ $re ]] || continue
        entry=${BASH_REMATCH[1]}; name=${BASH_REMATCH[3]}; value=${BASH_REMATCH[4]}
        case "$name" in
            system.timezone) TZ_WANT=$value; NES=$((NES + 1)); continue ;;
            InvertButtons)   AB_WANT=$value; NES=$((NES + 1)); continue ;;
        esac
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
if [ -n "$TZ_WANT" ]; then
    [[ "$TZ_WANT" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] && [ -f "$ROOT/usr/share/zoneinfo/$TZ_WANT" ] \
        || { echo "inject: time zone '$TZ_WANT' not found in the image's /usr/share/zoneinfo" >&2; exit 1; }
    ln -sfn "/usr/share/zoneinfo/$TZ_WANT" "$ROOT/etc/localtime"
    ESCONF="$ROOT/home/ark/.emulationstation.conf"
    [ -f "$ESCONF" ] || { : > "$ESCONF"; chown --reference="$ROOT/home/ark" "$ESCONF"; }
    grep -v '^system\.timezone=' "$ESCONF" > "$ESCONF.tmp" || :
    echo "system.timezone=$TZ_WANT" >> "$ESCONF.tmp"
    cat "$ESCONF.tmp" > "$ESCONF"; rm -f "$ESCONF.tmp"
    echo "inject: time zone -> $TZ_WANT (/etc/localtime, ${ESCONF#"$ROOT"})"
fi
if [ -n "$AB_WANT" ]; then
    case "$AB_WANT" in
        true)  want=US ;;
        false) want=JP ;;
        *)     echo "inject: InvertButtons must be true (US) or false (JP), not '$AB_WANT'" >&2; exit 1 ;;
    esac
    have=JP; [ -f "$ROOT/var/cache/Switch_AB" ] && have=US          # b_swap.sh's own flag
    if [ "$have" = "$want" ]; then
        echo "inject: A/B buttons -> already $want"
    else
        SWAP="$ROOT/usr/local/bin/b_swap.sh"
        [ -f "$SWAP" ] || { echo "inject: ${SWAP#"$ROOT"} not found, cannot switch the A/B buttons" >&2; exit 1; }
        # dArkOSen's own script, its file paths (all set at its top) moved under ROOT. A path through
        # a symbolic link could lead out of the image, so none may cross one.
        mapfile -t swpaths < <(sed -nE 's#^[A-Z0-9_]+="(/[^"]*)".*#\1#p' "$SWAP")
        for p in "${swpaths[@]}"; do
            cur=""; IFS=/ read -ra segs <<<"${p#/}"
            for s in "${segs[@]}"; do
                cur="$cur/$s"
                [ -L "$ROOT$cur" ] && { echo "inject: $cur in the image is a symbolic link, A/B buttons not switched" >&2; exit 1; }
            done
        done
        # /opt/system/Tools is /roms/tools bind-mounted on the device: PortMaster's and ThemeMaster's
        # files come from roms.tar at the first boot, so the script edits copies taken out of it
        stage=$(mktemp -d); staged=()
        for p in "${swpaths[@]}"; do
            m="roms/tools/${p#/opt/system/Tools/}"
            [[ "$p" == /opt/system/Tools/* ]] && [ -f "$ROMSTAR" ] && tar -xf "$ROMSTAR" -C "$stage" "$m" 2>/dev/null || continue
            cp -p "$stage/$m" "$stage/$m.orig"; staged+=("$m")
        done
        sw=$(mktemp)
        sed -E -e "s#^([A-Z0-9_]+)=\"/opt/system/Tools/#\\1=\"$stage/roms/tools/#" -e t \
               -e "s#^([A-Z0-9_]+)=\"/#\\1=\"$ROOT/#" "$SWAP" > "$sw"
        if [ ${#swpaths[@]} -eq 0 ] || [ "$(grep -cE "^[A-Z0-9_]+=\"($ROOT|$stage)/" "$sw")" -ne ${#swpaths[@]} ]; then
            rm -rf "$sw" "$stage"; echo "inject: ${SWAP#"$ROOT"} does not set its paths the expected way, A/B buttons not switched" >&2; exit 1
        fi
        bash "$sw" || :                                            # a file the image lacks only gets sed's message
        rm -f "$sw"
        have=JP; [ -f "$ROOT/var/cache/Switch_AB" ] && have=US
        [ "$have" = "$want" ] || { rm -rf "$stage"; echo "inject: A/B buttons still $have after b_swap.sh" >&2; exit 1; }
        ntools=0
        for m in "${staged[@]}"; do                                 # changed copies replace their roms.tar entry
            cmp -s "$stage/$m" "$stage/$m.orig" && continue
            nbefore=$(tar -tf "$ROMSTAR" | wc -l)
            tar --delete -f "$ROMSTAR" "$m"
            tar -rf "$ROMSTAR" -C "$stage" --owner=0 --group=0 --mode='u=rwX,go=rX' "$m"
            [ "$(tar -tf "$ROMSTAR" | wc -l)" -eq "$nbefore" ] || { echo "inject: roms.tar entry count changed while replacing $m" >&2; exit 1; }
            ntools=$((ntools + 1))
        done
        rm -rf "$stage"
        echo "inject: A/B buttons -> $want (dArkOSen's b_swap.sh; $ntools file(s) of /roms/tools switched in roms.tar)"
    fi
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
DARKOSEN_EXTENDED_RETRORUN_HOTKEYS=$NRR
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
echo "inject: retrorun  -> $NRR hotkeys build binaries"
