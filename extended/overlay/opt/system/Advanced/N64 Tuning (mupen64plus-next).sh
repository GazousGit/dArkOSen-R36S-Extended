#!/bin/bash

# =======================================================
# N64 Tuning for RetroArch  (dArkOSen Extended)
#
# The menu never changes which emulator a game uses: that
# stays the EmulationStation choice (the system default and
# the per-game emulator/core kept in gamelist.xml). It only
# edits RetroArch core options.
#
# The image build also runs "--es-default": it makes
# retroarch / mupen64plus_next the N64 default in
# EmulationStation, which is what the per-game list of
# R36S-Game-Compatibility-Lists assumes (a game without an
# emulator tag is one that runs best on that core). On a
# running device set it in ES instead (N64 > Advanced
# System Options).
#
# dArkOS ships RetroArch with NO options for the
# Mupen64Plus-Next core, so it runs at its defaults (640x480,
# single-threaded renderer). The preset writes the GLideN64
# settings recommended by the ArkOS wiki (Emulators and
# Ports > Nintendo 64) into
# /home/ark/.config/retroarch/retroarch-core-options.cfg:
#   320x240, threaded renderer, hybrid filter off, color
#   buffer to RDRAM off, overscan off; the rest as the core
#   ships it (framebuffer and LOD emulation ON, depth buffer
#   to RDRAM "Software", accurate texture coordinates).
# The older "mupen64plus" core reads the same option names
# for resolution, framebuffer emulation and buffer copies,
# so those settings apply to it as well.
#
# Only mupen64plus-* lines are touched. The lines that were
# there before the first change are kept in
# retroarch-core-options.cfg.mupen64plus.pre-ext, so the
# tool can restore them (dArkOS default = nothing). Run it
# while RetroArch is not running (it is not, from
# EmulationStation). The image build applies the preset, so
# built images already have it.
#
# Per-game fixes: when <config>/<core name>/<rom name>.opt
# exists, RetroArch uses it instead of the global options.
# The tool writes such files for the games in PER_GAME.
# =======================================================
# MIT License - same terms as dArkOSen.

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

RA_HOME="${N64_RA_HOME:-/home/ark/.config}"
CFG="$RA_HOME/retroarch/retroarch-core-options.cfg"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="N64 Tuning (RetroArch) - dArkOSen Extended"

# rom name (glob, without extension) | RetroArch build | core folder | key prefix | key=value ...
PER_GAME=(
    # 32-bit ParaLLEl: fixes most of the menu and lighting problems (R36S-Game-Compatibility-Lists issue 19)
    'Pokemon Stadium (*|retroarch32|ParaLLEl N64|parallel-n64-|gfxplugin=glide64 gfxplugin-accuracy=medium screensize=640x480'
)

Own() { chown ark:ark "$@" 2>/dev/null || chown 1000:1000 "$@" 2>/dev/null || :; }
Bk() { echo "$CFG.mupen64plus.pre-ext"; }
Get() { grep -m1 "^$1 *= *" "$CFG" 2>/dev/null | sed 's/^[^=]*= *//; s/^"//; s/"$//'; }
# Set key value: RetroArch format  key = "value"  (one line per key)
Set() {
    local k=$1 v=$2 tmp="$CFG.tmp"
    if [ ! -f "$(Bk)" ]; then grep '^mupen64plus-' "$CFG" > "$(Bk)" 2>/dev/null || :; fi
    if grep -q "^$k *=" "$CFG"; then
        awk -v k="$k" -v v="$v" '
            $0 ~ "^"k" *=" { if (!done) { print k " = \"" v "\""; done=1 }; next }
            { print }' "$CFG" > "$tmp" && cat "$tmp" > "$CFG"
        rm -f "$tmp"
    else
        printf '%s = "%s"\n' "$k" "$v" >> "$CFG"
    fi
    Own "$CFG" "$(Bk)"
}
# Toggle key A B DEFAULT: an unset key counts as the core default
Toggle() {
    local cur; cur=$(Get "$1"); cur=${cur:-$4}
    if [ "$cur" = "$2" ]; then Set "$1" "$3"; else Set "$1" "$2"; fi
}
Restore() {
    [ -f "$(Bk)" ] || return 1
    local tmp="$CFG.tmp"
    grep -v '^mupen64plus-' "$CFG" > "$tmp" || :
    cat "$(Bk)" >> "$tmp"
    cat "$tmp" > "$CFG"; rm -f "$tmp" "$(Bk)"
    Own "$CFG"
    return 0
}
# The GLideN64 page of the ArkOS wiki, option by option, in the order of the RetroArch menu
Apply_Preset() {
    Restore                                  # start again from the lines that were there before this tool
    Set mupen64plus-rdp-plugin "gliden64"
    Set mupen64plus-43screensize "320x240"
    Set mupen64plus-169screensize "640x360"
    Set mupen64plus-aspect "4:3"
    Set mupen64plus-EnableNativeResFactor "0"
    Set mupen64plus-ThreadedRenderer "True"
    Set mupen64plus-BilinearMode "standard"
    Set mupen64plus-HybridFilter "False"
    Set mupen64plus-DitheringPattern "False"
    Set mupen64plus-DitheringQuantization "False"
    Set mupen64plus-RDRAMImageDitheringMode "False"
    Set mupen64plus-MultiSampling "0"
    Set mupen64plus-FXAA "0"
    Set mupen64plus-EnableLODEmulation "True"
    Set mupen64plus-EnableFBEmulation "True"
    Set mupen64plus-EnableCopyAuxToRDRAM "False"
    Set mupen64plus-EnableCopyColorToRDRAM "Off"
    Set mupen64plus-EnableCopyDepthToRDRAM "Software"
    Set mupen64plus-BackgroundMode "OnePiece"
    Set mupen64plus-EnableHWLighting "False"
    Set mupen64plus-CorrectTexrectCoords "Off"
    Set mupen64plus-EnableInaccurateTextureCoordinates "False"
    Set mupen64plus-EnableTexCoordBounds "False"
    Set mupen64plus-EnableNativeResTexrects "Disabled"
    Set mupen64plus-EnableLegacyBlending "True"
    Set mupen64plus-EnableFragmentDepthWrite "False"
    Set mupen64plus-EnableTextureCache "True"
    Set mupen64plus-EnableOverscan "Disabled"
    Set mupen64plus-OverscanTop "0"
    Set mupen64plus-OverscanLeft "0"
    Set mupen64plus-OverscanRight "0"
    Set mupen64plus-OverscanBottom "0"
    Set mupen64plus-MaxHiResTxVramLimit "0"
    Set mupen64plus-MaxTxCacheSize "8000"
    Set mupen64plus-txFilterMode "None"
}
# Writes the per-game option files for the roms that are present; prints one path per file.
# Each file holds every option of the core: the current global lines with the listed values.
Apply_Per_Game() {
    local e pat ra core pre kv dir rom name out k key
    for e in "${PER_GAME[@]}"; do
        IFS='|' read -r pat ra core pre kv <<<"$e"
        for dir in ${N64_ROMS:-/roms/n64 /roms2/n64}; do
            for rom in "$dir"/*; do
                [ -f "$rom" ] || continue
                case "${rom##*.}" in z64|Z64|n64|N64|v64|V64|zip|ZIP|7z|7Z) ;; *) continue ;; esac
                name=$(basename "${rom%.*}")
                # shellcheck disable=SC2254
                case "$name" in $pat) ;; *) continue ;; esac
                out="$RA_HOME/$ra/config/$core/$name.opt"
                mkdir -p "$(dirname "$out")"
                grep "^$pre" "$RA_HOME/$ra/retroarch-core-options.cfg" > "$out.tmp" 2>/dev/null || :
                for k in $kv; do
                    key="$pre${k%%=*}"
                    grep -v "^$key *=" "$out.tmp" > "$out.tmp2" || :
                    printf '%s = "%s"\n' "$key" "${k#*=}" >> "$out.tmp2"
                    mv "$out.tmp2" "$out.tmp"
                done
                mv "$out.tmp" "$out"
                Own "$RA_HOME/$ra/config/$core" "$out"
                echo "$out"
            done
        done
    done
}

# N64 default emulator in es_settings.cfg (ES rewrites that file on exit: only while ES is stopped)
Set_ES_Default() {
    local f=$1 tmp="$1.tmp"
    grep -vE '<string name="n64\.(emulator|core)" ' "$f" > "$tmp" || :
    [ -z "$(tail -c1 "$tmp")" ] || echo >> "$tmp"
    if grep -q '</config>' "$tmp"; then
        sed -i 's|</config>|<string name="n64.core" value="mupen64plus_next" />\n<string name="n64.emulator" value="retroarch" />\n</config>|' "$tmp"
    else
        printf '%s\n' '<string name="n64.core" value="mupen64plus_next" />' '<string name="n64.emulator" value="retroarch" />' >> "$tmp"
    fi
    cat "$tmp" > "$f"; rm -f "$tmp"
    Own "$f"
}

# Command line (no UI): --wiki [CFG], --restore [CFG], --show [CFG], --per-game, --es-default [ES_SETTINGS]
case "${1:-}" in
    --es-default) ES="${2:-/home/ark/.emulationstation/es_settings.cfg}"
                [ -f "$ES" ] || { echo "$ES not found" >&2; exit 1; }; Set_ES_Default "$ES"; exit 0 ;;
    --wiki)     CFG="${2:-$CFG}"; [ -f "$CFG" ] || { echo "$CFG not found" >&2; exit 1; }; Apply_Preset; exit 0 ;;
    --restore)  CFG="${2:-$CFG}"; Restore || { echo "no backup $(Bk)" >&2; exit 1; }; exit 0 ;;
    --show)     CFG="${2:-$CFG}"; grep '^mupen64plus-' "$CFG"; exit 0 ;;
    --per-game) Apply_Per_Game; exit 0 ;;
esac

Start_GPTKeyb() {
    pkill -9 -f gptokeyb 2>/dev/null; sleep 0.1
    /opt/inttools/gptokeyb -1 "$0" -c "$TMP_KEYS" > /dev/null 2>&1 &
    GPTOKEYB_PID=$!
}
Stop_GPTKeyb() { [ -n "$GPTOKEYB_PID" ] && kill "$GPTOKEYB_PID" 2>/dev/null; GPTOKEYB_PID=""; }
Exit_Menu() {
    trap - EXIT
    printf "\033[H\033[2J\e[?25h" > "$CURR_TTY"
    Stop_GPTKeyb; rm -f "$TMP_KEYS"
    [ -n "$ORIGINAL_FONT" ] && setfont "$ORIGINAL_FONT"
    exit 0
}
Msg() { dialog --clear --backtitle "$BACKTITLE" --msgbox "$1" "${2:-8}" "${3:-58}" > "$CURR_TTY"; }

ORIGINAL_FONT=$(setfont -v 2>&1 | grep -o '/.*\.psf.*')
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null
printf "\e[?25l\033[H\033[2J" > "$CURR_TTY"
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
chmod 666 /dev/uinput
# Confirm/back follow EmulationStation (A confirms unless ES has InvertButtons=true)
cp /opt/inttools/keys.gptk "$TMP_KEYS"
if grep -q 'name="InvertButtons" value="true"' /home/ark/.emulationstation/es_settings.cfg 2>/dev/null; then
    sed -i 's/^a = .*/a = esc/; s/^b = .*/b = enter/' "$TMP_KEYS"
else
    sed -i 's/^a = .*/a = enter/; s/^b = .*/b = esc/' "$TMP_KEYS"
fi
Start_GPTKeyb
trap 'Exit_Menu' EXIT

[ -f "$CFG" ] || { Msg "$CFG not found."; Exit_Menu; }

while true; do
    res=$(Get mupen64plus-43screensize);        res=${res:-640x480 (default)}
    fbe=$(Get mupen64plus-EnableFBEmulation);   fbe=${fbe:-True (default)}
    thr=$(Get mupen64plus-ThreadedRenderer);    thr=${thr:-False (default)}
    dup=$(Get mupen64plus-FrameDuping);         dup=${dup:-False (default)}
    dep=$(Get mupen64plus-EnableN64DepthCompare); dep=${dep:-False (default)}
    lod=$(Get mupen64plus-EnableLODEmulation);  lod=${lod:-True (default)}
    rdp=$(Get mupen64plus-rdp-plugin);          rdp=${rdp:-gliden64 (default)}
    [ -f "$(Bk)" ] && bk="yes" || bk="no"

    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "N64 cores mupen64plus_next / mupen64plus" \
        --menu "Resolution: $res | FB emulation: $fbe\nThreaded: $thr | Frame duping: $dup | Depth compare: $dep\nLOD: $lod | RDP: $rdp | Backup: $bk" \
        21 68 10 \
        1 "Apply the ArkOS wiki preset (320x240, threaded)" \
        2 "Internal resolution: 320x240 / 640x480" \
        3 "FB emulation: on / off (off: faster, glitches)" \
        4 "Threaded renderer: on / off" \
        5 "Frame duping: off / on" \
        6 "N64 depth compare: off / on" \
        7 "LOD emulation: on / off" \
        8 "RDP plugin: gliden64 / angrylion (software, slow)" \
        9 "Per-game fixes (Pokemon Stadium on ParaLLEl 32)" \
        10 "Restore what was there before this tool" \
        11 "Show the mupen64plus lines" \
        2>&1 > "$CURR_TTY") || Exit_Menu

    case "$CHOICE" in
        1) Apply_Preset; Msg "ArkOS wiki preset applied.\n\nUsed by the retroarch cores mupen64plus_next and\nmupen64plus at the next game launch. The emulator\nchosen for each game is not changed.\nOption 10 puts the previous settings back." 12 58 ;;
        2) Toggle mupen64plus-43screensize "320x240" "640x480" "640x480" ;;
        3) Toggle mupen64plus-EnableFBEmulation "True" "False" "True" ;;
        4) Toggle mupen64plus-ThreadedRenderer "True" "False" "False" ;;
        5) Toggle mupen64plus-FrameDuping "False" "True" "False" ;;
        6) Toggle mupen64plus-EnableN64DepthCompare "False" "True" "False" ;;
        7) Toggle mupen64plus-EnableLODEmulation "True" "False" "True" ;;
        8) Toggle mupen64plus-rdp-plugin "gliden64" "angrylion" "gliden64" ;;
        9) pg=$(Apply_Per_Game)
           if [ -n "$pg" ]; then Msg "Per-game options written:\n\n$(sed 's|.*/config/||' <<<"$pg")\n\nDelete a file to go back to the global options." 14 58
           else Msg "No rom in /roms/n64 matches a known per-game fix." ; fi ;;
        10) if Restore; then Msg "Previous mupen64plus settings restored."; else Msg "No backup yet: nothing was changed by this tool."; fi ;;
        11) dialog --clear --backtitle "$BACKTITLE" --title "$CFG" --msgbox "$(grep '^mupen64plus-' "$CFG" || echo '(none: core defaults)')" 24 72 > "$CURR_TTY" ;;
    esac
done
