#!/bin/bash

# =======================================================
# Swap A/B in EmulationStation only  (dArkOSen Extended)
#
# dArkOSen's "Switch A/B Globally" flips the buttons in
# EmulationStation, RetroArch, PortMaster, Kodi, 351Files...
# all at once. This tool flips EmulationStation ALONE, by
# toggling its "InvertButtons" setting, and leaves every
# emulator exactly as it is.
#
# EmulationStation is restarted so the change takes effect.
# =======================================================
# MIT License - same terms as dArkOSen.

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

ES_CFG="/home/ark/.emulationstation/es_settings.cfg"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="Swap A/B in EmulationStation only - dArkOSen Extended"

Inverted() { grep -q 'name="InvertButtons" value="true"' "$ES_CFG" 2>/dev/null; }
# Flip the setting in the file (run while ES is stopped: ES writes its settings on exit)
Toggle_File() {
    local f=$1
    if grep -q 'name="InvertButtons" value="true"' "$f"; then
        sed -i '/bool name="InvertButtons"/d' "$f"
    else
        sed -i '/bool name="InvertButtons"/d' "$f"
        sed -i '/<config>/a <bool name="InvertButtons" value="true" \/>' "$f"
    fi
    chown ark:ark "$f" 2>/dev/null
}
case "${1:-}" in
    --toggle) Toggle_File "${2:-$ES_CFG}"; exit 0 ;;
    --status) Inverted && echo "swapped" || echo "normal"; exit 0 ;;
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

if [ ! -f "$ES_CFG" ]; then
    dialog --clear --backtitle "$BACKTITLE" --msgbox "$ES_CFG not found." 7 50 > "$CURR_TTY"
    Exit_Menu
fi

if Inverted; then
    STATE="SWAPPED (InvertButtons = true)"
    ACTION="switch EmulationStation back to its normal A/B layout"
else
    STATE="NORMAL (InvertButtons not set)"
    ACTION="swap A and B in EmulationStation"
fi

if dialog --clear --backtitle "$BACKTITLE" --title "EmulationStation A/B buttons" \
     --yesno "EmulationStation is currently: $STATE\n\nThis will $ACTION.\nEmulators, RetroArch, PortMaster and Kodi are NOT changed.\n\nEmulationStation restarts right away. Continue?" 13 60 > "$CURR_TTY"; then
    Stop_GPTKeyb
    printf "\033[H\033[2J" > "$CURR_TTY"
    # Edit the file only after ES has stopped: ES writes its settings on exit
    # and would otherwise overwrite the change.
    SELF=$(readlink -f "$0")
    systemd-run --no-block --quiet bash -c \
        "systemctl stop emulationstation; bash '$SELF' --toggle '$ES_CFG'; systemctl start emulationstation"
    trap - EXIT
    rm -f "$TMP_KEYS"
    exit 0
fi
Exit_Menu
