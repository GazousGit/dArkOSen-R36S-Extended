#!/bin/bash

# =======================================================
# N64 Tuning for the Mupen64Plus-Next core  (dArkOSen Extended)
#
# dArkOS ships RetroArch with NO mupen64plus-next core
# options set, so the core runs with its own defaults:
# 640x480 internal resolution, framebuffer emulation on,
# depth compare on, single-threaded renderer. Those are the
# expensive ones on an RK3326. The fast preset writes the
# settings commonly used on RG351/R36S devices into
# /home/ark/.config/retroarch/retroarch-core-options.cfg:
#   320x240, framebuffer emulation off, color/depth copies
#   off, N64 depth compare off, threaded renderer, frame
#   duping, GLideN64 + HLE RSP + dynarec, no filtering.
#
# Only mupen64plus-* lines are touched. The previous
# mupen64plus-* lines are kept in
# retroarch-core-options.cfg.mupen64plus.pre-ext so the
# tool can restore exactly what was there before (dArkOS
# default = nothing). Run it while RetroArch is not running
# (it is, from EmulationStation). The image build applies
# the fast preset, so built images already have it.
#
# In EmulationStation pick N64 > Advanced System Options >
# Emulator "retroarch", Core "mupen64plus_next" to use it.
# =======================================================
# MIT License - same terms as dArkOSen.

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

CFG="/home/ark/.config/retroarch/retroarch-core-options.cfg"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="N64 Tuning (mupen64plus-next) - dArkOSen Extended"

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
Toggle() { if [ "$(Get "$1")" = "$2" ]; then Set "$1" "$3"; else Set "$1" "$2"; fi; }
Apply_Fast() {
    Set mupen64plus-cpucore "dynamic_recompiler"
    Set mupen64plus-rdp-plugin "gliden64"
    Set mupen64plus-rsp-plugin "hle"
    Set mupen64plus-43screensize "320x240"
    Set mupen64plus-aspect "4:3"
    Set mupen64plus-EnableFBEmulation "False"
    Set mupen64plus-EnableCopyColorToRDRAM "Off"
    Set mupen64plus-EnableCopyDepthToRDRAM "Off"
    Set mupen64plus-EnableCopyAuxToRDRAM "False"
    Set mupen64plus-EnableCopyColorFromRDRAM "False"
    Set mupen64plus-EnableHWLighting "False"
    Set mupen64plus-EnableLODEmulation "False"
    Set mupen64plus-EnableNativeResTexrects "Disabled"
    Set mupen64plus-EnableLegacyBlending "True"
    Set mupen64plus-EnableFragmentDepthWrite "False"
    Set mupen64plus-EnableN64DepthCompare "False"
    Set mupen64plus-EnableTextureCache "True"
    Set mupen64plus-BilinearMode "standard"
    Set mupen64plus-MultiSampling "0"
    Set mupen64plus-FXAA "0"
    Set mupen64plus-HybridFilter "False"
    Set mupen64plus-txFilterMode "None"
    Set mupen64plus-txEnhancementMode "None"
    Set mupen64plus-txHiresEnable "False"
    Set mupen64plus-ThreadedRenderer "True"
    Set mupen64plus-FrameDuping "True"
    Set mupen64plus-Framerate "Original"
    Set mupen64plus-BackgroundMode "OnePiece"
    Set mupen64plus-EnableOverscan "Disabled"
    Set mupen64plus-CountPerOp "0"
    Set mupen64plus-EnableInaccurateTextureCoordinates "True"
    Set mupen64plus-EnableTexCoordBounds "False"
    Set mupen64plus-GLideN64IniBehaviour "late"
    Set mupen64plus-virefresh "Auto"
    Set mupen64plus-DitheringPattern "False"
    Set mupen64plus-DitheringQuantization "False"
    Set mupen64plus-RDRAMImageDitheringMode "False"
    Set mupen64plus-pak1 "memory"
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

# Command line (no UI): --fast [CFG], --restore [CFG], --show [CFG]
case "${1:-}" in
    --fast)    CFG="${2:-$CFG}"; [ -f "$CFG" ] || { echo "$CFG not found" >&2; exit 1; }; Apply_Fast; exit 0 ;;
    --restore) CFG="${2:-$CFG}"; Restore || { echo "no backup $(Bk)" >&2; exit 1; }; exit 0 ;;
    --show)    CFG="${2:-$CFG}"; grep '^mupen64plus-' "$CFG"; exit 0 ;;
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
    dup=$(Get mupen64plus-FrameDuping);         dup=${dup:-True (default)}
    dep=$(Get mupen64plus-EnableN64DepthCompare); dep=${dep:-True (default)}
    lod=$(Get mupen64plus-EnableLODEmulation);  lod=${lod:-True (default)}
    rdp=$(Get mupen64plus-rdp-plugin);          rdp=${rdp:-gliden64 (default)}
    [ -f "$(Bk)" ] && bk="yes" || bk="no"

    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "N64 (RetroArch core mupen64plus_next)" \
        --menu "Resolution: $res | FB emulation: $fbe\nThreaded: $thr | Frame duping: $dup | Depth compare: $dep\nLOD: $lod | RDP: $rdp | Backup: $bk" \
        21 68 10 \
        1 "Apply the fast preset (320x240, FB emulation off...)" \
        2 "Internal resolution: 320x240 / 640x480" \
        3 "Framebuffer emulation: off / on (some games need it)" \
        4 "Threaded renderer: on / off" \
        5 "Frame duping: on / off" \
        6 "N64 depth compare: off / on" \
        7 "LOD emulation: off / on" \
        8 "RDP plugin: gliden64 / angrylion (software, slow)" \
        9 "Restore what was there before (dArkOS default)" \
        10 "Show the mupen64plus lines" \
        2>&1 > "$CURR_TTY") || Exit_Menu

    case "$CHOICE" in
        1) Apply_Fast; Msg "Fast preset applied.\n\nTakes effect at the next game launch with the\nretroarch / mupen64plus_next emulator choice.\nOption 9 puts the previous settings back." 11 58 ;;
        2) Toggle mupen64plus-43screensize "320x240" "640x480" ;;
        3) Toggle mupen64plus-EnableFBEmulation "False" "True" ;;
        4) Toggle mupen64plus-ThreadedRenderer "True" "False" ;;
        5) Toggle mupen64plus-FrameDuping "True" "False" ;;
        6) Toggle mupen64plus-EnableN64DepthCompare "False" "True" ;;
        7) Toggle mupen64plus-EnableLODEmulation "False" "True" ;;
        8) Toggle mupen64plus-rdp-plugin "gliden64" "angrylion" ;;
        9) if Restore; then Msg "Previous mupen64plus settings restored."; else Msg "No backup yet: nothing was changed by this tool."; fi ;;
        10) dialog --clear --backtitle "$BACKTITLE" --title "$CFG" --msgbox "$(grep '^mupen64plus-' "$CFG" || echo '(none: core defaults)')" 24 72 > "$CURR_TTY" ;;
    esac
done
