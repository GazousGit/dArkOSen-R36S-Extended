#!/bin/bash

# =======================================================
# PPSSPP: sync per-game settings between standalone and
# standalone-2021  (dArkOSen Extended)
#
# dArkOS keeps the two PPSSPP builds apart:
#   standalone      -> /roms/psp/ppsspp/
#   standalone-2021 -> /roms/psp/ppsspp-2021/
# (/home/ark/.config/ppsspp is re-pointed at launch). Each
# has its own PSP/SYSTEM folder, so per-game settings
# (<GAMEID>_ppsspp.ini, <GAMEID>_controls.ini) made with
# one build are invisible to the other, and so are saves.
#
# This tool copies the per-game files in the direction you
# choose (existing files on the target are backed up as
# .bak), and can optionally make the 2021 build use the
# standalone memory stick (saves, states and per-game
# settings shared) through PPSSPP's MemStickDirectory
# setting. Nothing here touches the main ppsspp.ini
# graphics settings of either build.
# =======================================================
# MIT License - same terms as dArkOSen.

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

# Roms root: follow SD2 setups
ES_CFG="/etc/emulationstation/es_systems.cfg"
if grep -q "<path>/roms2/psp/" "$ES_CFG" 2>/dev/null; then ROMS="/roms2"; else ROMS="/roms"; fi
[ -n "${PPSSPP_ROMS:-}" ] && ROMS="$PPSSPP_ROMS"     # tests
STD="$ROMS/psp/ppsspp"
V21="$ROMS/psp/ppsspp-2021"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="PPSSPP: sync standalone and 2021 - dArkOSen Extended"

Own() { chown ark:ark "$@" 2>/dev/null || chown 1000:1000 "$@" 2>/dev/null || :; }
Count_Game_Files() { find "$1/PSP/SYSTEM" -maxdepth 1 -type f \( -name '*_ppsspp.ini' -o -name '*_controls.ini' \) 2>/dev/null | wc -l; }
# Copy_Games FROM TO : per-game ini files only; existing targets are kept as .bak
Copy_Games() {
    local from=$1 to=$2 f n=0
    mkdir -p "$to/PSP/SYSTEM"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$to/PSP/SYSTEM/$(basename "$f")" ] && cp -f "$to/PSP/SYSTEM/$(basename "$f")" "$to/PSP/SYSTEM/$(basename "$f").bak"
        cp -f "$f" "$to/PSP/SYSTEM/" && n=$((n+1))
    done < <(find "$from/PSP/SYSTEM" -maxdepth 1 -type f \( -name '*_ppsspp.ini' -o -name '*_controls.ini' \) 2>/dev/null)
    Own -R "$to"
    echo "$n"
}
Memstick_Shared() { grep -q "^MemStickDirectory = $STD/" "$V21/PSP/SYSTEM/ppsspp.ini.sdl" 2>/dev/null; }
Set_Memstick() {   # $1 = "share" | "own"
    local ini="$V21/PSP/SYSTEM/ppsspp.ini.sdl"
    [ -f "$ini" ] || return 1
    [ -f "$ini.pre-ext" ] || cp -p "$ini" "$ini.pre-ext"
    sed -i '/^MemStickDirectory = /d' "$ini"
    if [ "$1" = share ]; then
        if grep -q '^\[General\]' "$ini"; then
            sed -i "/^\[General\]/a MemStickDirectory = $STD/" "$ini"
        else
            printf '[General]\nMemStickDirectory = %s/\n' "$STD" >> "$ini"
        fi
    fi
    Own "$ini" "$ini.pre-ext"
    return 0
}

case "${1:-}" in
    --copy-to-2021)   Copy_Games "$STD" "$V21"; exit 0 ;;
    --copy-to-std)    Copy_Games "$V21" "$STD"; exit 0 ;;
    --share-memstick) Set_Memstick share; exit $? ;;
    --own-memstick)   Set_Memstick own; exit $? ;;
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
Msg() { dialog --clear --backtitle "$BACKTITLE" --msgbox "$1" "${2:-9}" "${3:-60}" > "$CURR_TTY"; }

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

while true; do
    ns=$(Count_Game_Files "$STD"); nv=$(Count_Game_Files "$V21")
    [ -d "$V21" ] && v21="present" || v21="not created yet (launch standalone-2021 once)"
    Memstick_Shared && ms="shared (standalone's)" || ms="own"
    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "PPSSPP per-game settings" \
        --menu "standalone:      $STD  ($ns per-game files)\nstandalone-2021: $V21  ($nv per-game files, $v21)\n2021 memory stick: $ms" \
        18 70 6 \
        1 "Copy per-game settings: standalone -> 2021" \
        2 "Copy per-game settings: 2021 -> standalone" \
        3 "2021 uses the standalone memory stick (saves+settings shared)" \
        4 "2021 back to its own memory stick" \
        5 "What is a per-game file?" \
        2>&1 > "$CURR_TTY") || Exit_Menu
    case "$CHOICE" in
        1) n=$(Copy_Games "$STD" "$V21"); Msg "Copied $n per-game file(s) to\n$V21/PSP/SYSTEM/\n(previous versions kept as .bak)" ;;
        2) n=$(Copy_Games "$V21" "$STD"); Msg "Copied $n per-game file(s) to\n$STD/PSP/SYSTEM/\n(previous versions kept as .bak)" ;;
        3) if dialog --clear --backtitle "$BACKTITLE" --yesno "standalone-2021 will read and write saves, save states and per-game settings in\n$STD\n(PPSSPP setting MemStickDirectory). Its own graphics settings stay separate.\n\nExperimental: if the 2021 build misbehaves, use option 4.\nContinue?" 13 66 > "$CURR_TTY"; then
               Set_Memstick share && Msg "Done. The 2021 build now uses $STD." || Msg "Could not edit $V21/PSP/SYSTEM/ppsspp.ini.sdl\n(launch standalone-2021 once first)."
           fi ;;
        4) Set_Memstick own && Msg "Done. The 2021 build uses its own memory stick again." || Msg "Nothing to change." ;;
        5) Msg "PPSSPP stores game-specific settings (made with 'Create game config' in its menu) as\nPSP/SYSTEM/<GAMEID>_ppsspp.ini and <GAMEID>_controls.ini inside the memory stick folder.\n\nstandalone and standalone-2021 have separate folders, so a config made in one is not seen by the other until it is copied." 13 66 ;;
    esac
done
