#!/bin/bash

# =======================================================
# Dreamcast Tuning for retrorun / retrorun32  (dArkOSen Extended)
#
# retrorun reads the flycast core options straight from
# /home/ark/.config/retrorun.cfg. dArkOS ships it with most
# speed tweaks already on (threaded rendering, no RTT,
# per-strip alpha sorting, auto frame skip), but not the
# ones RetroArch32 uses on this hardware: internal
# resolution 320x240, synchronous rendering off, VGA cable.
#
# This tool edits ONLY the reicast_* lines of retrorun.cfg
# (a backup is kept as retrorun.cfg.pre-ext) and can put
# the dArkOS defaults back at any time. It also checks the
# known "no sound in 32-bit emulators" issue of the
# 09302026 image.
#
# Notes: the reicast_xtreme core ignores 320x240, fog and
# frame skipping (it only knows 640x480 and up).
# =======================================================
# MIT License - same terms as dArkOSen.

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

CFG="/home/ark/.config/retrorun.cfg"
BK="$CFG.pre-ext"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="Dreamcast Tuning (retrorun) - dArkOSen Extended"

Get() { grep -m1 "^$1 *= *" "$CFG" 2>/dev/null | sed 's/^[^=]*= *//; s/ *$//'; }
# Set a core option: replaces every existing line for the key with one line
# (dArkOS ships duplicates), or adds it after the "# ---- FLYCAST ----" header.
Set() {
    local k=$1 v=$2 tmp="$CFG.tmp"
    [ -f "$BK" ] || cp -p "$CFG" "$BK"
    if grep -q "^$k *=" "$CFG"; then
        awk -v k="$k" -v v="$v" '
            $0 ~ "^"k" *=" { if (!done) { print k " = " v; done=1 }; next }
            { print }' "$CFG" > "$tmp" && cat "$tmp" > "$CFG"
    elif grep -q '^# ---- FLYCAST ----' "$CFG"; then
        awk -v k="$k" -v v="$v" '{ print } /^# ---- FLYCAST ----/ { print k " = " v }' "$CFG" > "$tmp" && cat "$tmp" > "$CFG"
    else
        printf '%s = %s\n' "$k" "$v" >> "$CFG"
    fi
    rm -f "$tmp"
    chown ark:ark "$CFG" "$BK" 2>/dev/null || chown 1000:1000 "$CFG" "$BK" 2>/dev/null || :
}
Toggle() {   # key, value A, value B (A is the default when unset)
    if [ "$(Get "$1")" = "$2" ]; then Set "$1" "$3"; else Set "$1" "$2"; fi
}
Apply_Fast() {
    Set reicast_internal_resolution "320x240"
    Set reicast_synchronous_rendering "disabled"
    Set reicast_threaded_rendering "enabled"
    Set reicast_auto_skip_frame "enabled"
    Set reicast_frame_skipping "disabled"
    Set reicast_delay_frame_swapping "disabled"
    Set reicast_cable_type "VGA (RGB)"
    Set reicast_anisotropic_filtering "off"
    Set reicast_alpha_sorting "per-strip (fast, least accurate)"
    Set reicast_enable_rtt "disabled"
    Set reicast_enable_rttb "disabled"
    Set reicast_texupscale "off"
    Set reicast_fog "disabled"
    Set reicast_pvr2_filtering "disabled"
    Set reicast_enable_dsp "disabled"
}
Audio_Status() {
    local lib="/usr/lib/arm-linux-gnueabihf/libasound.so.2.0.0" msg
    if [ -f /home/ark/.config/.dArkOSen-update09302026b ]; then
        msg="OK: update 09302026b is installed (custom 32-bit ALSA library).\n"
    else
        msg="MISSING: update 09302026b is NOT installed.\n\nThe 09302026 image ships a 32-bit ALSA library that produces NO SOUND in 32-bit emulators (retrorun32, retroarch32) on this kernel. Dreamcast through retrorun32 is silent until you run:\n\n  Options > System > Update-dArkOSen\n\n(needs Wi-Fi; the offline package is on djparentx's dArkOSen-updates release 09302026b).\n"
    fi
    msg="$msg\nDiversion: $(dpkg-divert --list "$lib" 2>/dev/null | grep -q distrib && echo active || echo none)"
    dialog --clear --backtitle "$BACKTITLE" --title "32-bit audio check" --msgbox "$msg" 18 62 > "$CURR_TTY"
}

# Command line (no UI): --fast [CFG] applies the preset, --restore [CFG] puts the
# backup back, --show [CFG] prints the flycast/retrorun lines.
case "${1:-}" in
    --fast)    CFG="${2:-$CFG}"; BK="$CFG.pre-ext"; [ -f "$CFG" ] || { echo "$CFG not found" >&2; exit 1; }; Apply_Fast; exit 0 ;;
    --restore) CFG="${2:-$CFG}"; BK="$CFG.pre-ext"; [ -f "$BK" ] || { echo "no backup $BK" >&2; exit 1; }; cat "$BK" > "$CFG"; rm -f "$BK"; exit 0 ;;
    --show)    CFG="${2:-$CFG}"; grep -E '^(reicast_|retrorun_)' "$CFG"; exit 0 ;;
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
Msg() { dialog --clear --backtitle "$BACKTITLE" --msgbox "$1" "${2:-8}" "${3:-56}" > "$CURR_TTY"; }

ORIGINAL_FONT=$(setfont -v 2>&1 | grep -o '/.*\.psf.*')
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null
printf "\e[?25l\033[H\033[2J" > "$CURR_TTY"
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
chmod 666 /dev/uinput
cp /opt/inttools/keys.gptk "$TMP_KEYS"
if grep -q '^b = backspace' "$TMP_KEYS"; then
    sed -i 's/^b = .*/b = esc/; s/^a = .*/a = enter/' "$TMP_KEYS"
fi
Start_GPTKeyb
trap 'Exit_Menu' EXIT

[ -f "$CFG" ] || { Msg "$CFG not found."; Exit_Menu; }

while true; do
    res=$(Get reicast_internal_resolution);   res=${res:-640x480 (default)}
    syn=$(Get reicast_synchronous_rendering); syn=${syn:-default}
    fsk=$(Get reicast_frame_skipping);        fsk=${fsk:-disabled}
    ask=$(Get reicast_auto_skip_frame);       ask=${ask:-default}
    cab=$(Get reicast_cable_type);            cab=${cab:-default}
    fog=$(Get reicast_fog);                   fog=${fog:-default}
    dsp=$(Get reicast_enable_dsp);            dsp=${dsp:-default}
    fps=$(Get retrorun_fps_counter);          fps=${fps:-false}
    [ -f "$BK" ] && bk="yes" || bk="no"

    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "Dreamcast (retrorun / retrorun32)" \
        --menu "Resolution: $res | Sync render: $syn\nFrame skip: $fsk | Auto skip: $ask | Cable: $cab\nFog: $fog | DSP: $dsp | FPS counter: $fps | Backup: $bk" \
        21 66 10 \
        1 "Apply the fast preset (320x240, no sync, VGA...)" \
        2 "Internal resolution: 320x240 / 640x480" \
        3 "Synchronous rendering: on / off" \
        4 "Frame skipping: off / 1 / 2" \
        5 "Fog: on / off" \
        6 "DSP sound effects: on / off (off is faster)" \
        7 "FPS counter on screen: on / off" \
        8 "Restore dArkOS defaults from the backup" \
        9 "Check the 32-bit audio fix (no sound?)" \
        10 "Show the flycast lines of retrorun.cfg" \
        2>&1 > "$CURR_TTY") || Exit_Menu

    case "$CHOICE" in
        1) Apply_Fast; Msg "Fast preset applied.\n\nTakes effect at the next game launch.\nUse option 7 to go back to the dArkOS defaults." 10 56 ;;
        2) Toggle reicast_internal_resolution "320x240" "640x480" ;;
        3) Toggle reicast_synchronous_rendering "disabled" "enabled" ;;
        4) case "$(Get reicast_frame_skipping)" in
               1) Set reicast_frame_skipping "2" ;;
               2) Set reicast_frame_skipping "disabled" ;;
               *) Set reicast_frame_skipping "1" ;;
           esac ;;
        5) Toggle reicast_fog "disabled" "enabled" ;;
        6) Toggle reicast_enable_dsp "disabled" "enabled" ;;
        7) Toggle retrorun_fps_counter "true" "false" ;;
        8) if [ -f "$BK" ]; then cat "$BK" > "$CFG"; chown ark:ark "$CFG"; rm -f "$BK"; Msg "dArkOS defaults restored."
           else Msg "No backup yet: nothing was changed by this tool."; fi ;;
        9) Audio_Status ;;
        10) dialog --clear --backtitle "$BACKTITLE" --title "$CFG" --msgbox "$(grep -E '^(reicast_|retrorun_)' "$CFG")" 24 70 > "$CURR_TTY" ;;
    esac
done
