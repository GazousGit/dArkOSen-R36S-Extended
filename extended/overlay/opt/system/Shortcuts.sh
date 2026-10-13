#!/bin/bash

# =======================================================
# Shortcuts  (dArkOSen Extended)
#
# - Shows the key combinations of the system and of the
#   emulators (quit, menu, save states...), one page each.
# - Reminder before a game: perfmax, the script dArkOSen
#   runs before every launch, calls
#   /usr/local/bin/launch-reminder, which prints the page
#   of the emulator about to start for a few seconds.
#   This tool turns it on or off and sets its duration.
#
# The pages are plain text files: first line = title, lines
# starting with # are not shown. A file in <roms>/shortcuts/
# replaces the built-in one of the same name in
# /usr/share/dArkOSen-Extended/shortcuts/, so the texts can
# be corrected from a PC (README.txt there has the rules).
#
# Command line (no UI):
#   --repair        make sure the settings file and the hook
#                   in perfmax exist; run at boot by the
#                   self-repair service and by the image
#                   build (root given in SHORTCUTS_ROOT)
#   --remove-hook   take the hook out of perfmax
#   --status        print the state
# =======================================================
# MIT License - same terms as dArkOSen.

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

ROOT="${SHORTCUTS_ROOT:-}"; ROOT="${ROOT%/}"
D_PERFMAX="/usr/local/bin/perfmax"
D_HELPER="/usr/local/bin/launch-reminder"
D_CONF="/home/ark/.config/shortcuts.conf"
D_TEXTS="/usr/share/dArkOSen-Extended/shortcuts"
PERFMAX="$ROOT$D_PERFMAX"; CONF="$ROOT$D_CONF"; TEXTS="$ROOT$D_TEXTS"
HOOK_TAG="# shortcuts-hook"
HOOK_LINE="[ -x $D_HELPER ] && $D_HELPER  $HOOK_TAG"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="Shortcuts - dArkOSen Extended"

# Roms root: follow SD2 setups (Storage Settings rewrites the paths to /roms2)
ES_CFG="$ROOT/etc/emulationstation/es_systems.cfg"
if grep -q "<path>/roms2/" "$ES_CFG" 2>/dev/null && ! grep -q "<path>/roms/" "$ES_CFG"; then
    D_ROMS="/roms2"
else
    D_ROMS="/roms"
fi
USER_TEXTS="$ROOT$D_ROMS/shortcuts"

Own() { chown --reference="$(dirname "$CONF")" "$@" 2>/dev/null || :; }
Load_Conf() {
    REMINDER=1; DELAY=2
    [ -f "$CONF" ] && . "$CONF"
    [[ "$DELAY" =~ ^[0-9]+$ ]] || DELAY=2
}
Save_Conf() {
    mkdir -p "$(dirname "$CONF")"
    printf 'REMINDER=%s\nDELAY=%s\n' "$REMINDER" "$DELAY" > "$CONF"
    Own "$CONF"
}

# One tagged line at the end of perfmax (nothing in that script exits early)
Hook_Present() { grep -qF "$HOOK_TAG" "$PERFMAX" 2>/dev/null; }
Install_Hook() {
    [ -f "$PERFMAX" ] || return 1
    Hook_Present && return 0
    [ -z "$(tail -c1 "$PERFMAX")" ] || echo >> "$PERFMAX"      # upstream's file has no final newline
    echo "$HOOK_LINE" >> "$PERFMAX"
    Hook_Present
}
Remove_Hook() {
    Hook_Present || return 0
    local tmp="$PERFMAX.sc.tmp"
    grep -vF "$HOOK_TAG" "$PERFMAX" > "$tmp" && cat "$tmp" > "$PERFMAX"      # keep inode, mode and owner
    rm -f "$tmp"
}
Do_Repair() {
    Load_Conf
    [ -f "$CONF" ] || Save_Conf
    if Install_Hook; then echo "shortcuts: launch hook: OK"; else echo "shortcuts: launch hook: FAILED ($D_PERFMAX missing?)"; return 1; fi
}

# Pages: every <key>.txt, yours first; system, retroarch and retrorun lead the list
Pages() {
    { for d in "$TEXTS" "$USER_TEXTS"; do
          [ -d "$d" ] && find "$d" -maxdepth 1 -type f -iname '*.txt' -printf '%f\n'
      done; } | sed 's/\.[Tt][Xx][Tt]$//' | grep -vix 'readme' | sort -u \
      | awk '{ p = ($0 == "system") ? 0 : ($0 == "retroarch") ? 1 : ($0 == "retrorun") ? 2 : 3; print p "\t" $0 }' \
      | sort -k1,1n -k2,2 | cut -f2
}
Page_File() { if [ -f "$USER_TEXTS/$1.txt" ]; then echo "$USER_TEXTS/$1.txt"; else echo "$TEXTS/$1.txt"; fi; }
Lines() { sed -e 's/\r$//' -e '1s/^\xef\xbb\xbf//' "$1" | grep -v '^#'; }      # also files saved by Windows editors
Title() { Lines "$1" | head -1; }
Body()  { Lines "$1" | tail -n +2; }
Export() {      # copies the built-in texts next to the roms, keeping files that are already there
    local f n=0
    mkdir -p "$USER_TEXTS" || return 1
    for f in "$TEXTS"/*.txt; do
        [ -f "$f" ] || continue
        [ -e "$USER_TEXTS/$(basename "$f")" ] || { cp "$f" "$USER_TEXTS/" && n=$((n + 1)); }
    done
    Own -R "$USER_TEXTS"
    echo "$n"
}

case "${1:-}" in
    --repair)      Do_Repair; exit $? ;;
    --remove-hook) Remove_Hook; exit 0 ;;
    --status)      Load_Conf; Hook_Present && h="present" || h="missing"; echo "reminder=$REMINDER delay=$DELAY hook=$h texts=$D_ROMS/shortcuts"; exit 0 ;;
    --pages)       Pages; exit 0 ;;
    --export)      Export; exit $? ;;
    "") ;;
    *)  echo "Unknown option: $1" >&2; exit 1 ;;
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

# First run / every run: make sure the hook is in place
Do_Repair > /dev/null

while true; do
    Load_Conf
    [ "$REMINDER" = 1 ] && rs="ON, $DELAY s" || rs="OFF"
    Hook_Present && hk="OK" || hk="MISSING"
    keys=(); items=()
    while IFS= read -r k; do
        keys+=("$k"); items+=("${#keys[@]}" "$(Title "$(Page_File "$k")")")
    done < <(Pages)
    items+=(R "Reminder before a game: turn ON / OFF" D "Reminder duration" E "Copy the texts to $D_ROMS/shortcuts (to edit)")

    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "Shortcuts" \
        --menu "Reminder before a game: $rs | Launch hook: $hk\nYour own texts go in $D_ROMS/shortcuts" \
        21 68 12 "${items[@]}" 2>&1 > "$CURR_TTY") || Exit_Menu

    case "$CHOICE" in
        R) [ "$REMINDER" = 1 ] && REMINDER=0 || REMINDER=1; Save_Conf ;;
        D) d=$(dialog --clear --backtitle "$BACKTITLE" --title "Reminder duration" \
               --menu "How long the reminder stays on screen\nbefore the game starts." 15 46 6 \
               1 "1 s" 2 "2 s" 3 "3 s" 4 "4 s" 5 "5 s" 2>&1 > "$CURR_TTY") && { DELAY=$d; Save_Conf; } ;;
        E) n=$(Export); Msg "$n text file(s) copied to\n$D_ROMS/shortcuts\n\nEdit them on a PC: the first line is the title, lines\nstarting with # are not shown. A file there replaces\nthe built-in one of the same name." 13 58 ;;
        *) f=$(Page_File "${keys[$((CHOICE - 1))]}")
           dialog --clear --backtitle "$BACKTITLE" --title "$(Title "$f")" --msgbox "$(Body "$f")" 21 68 > "$CURR_TTY" ;;
    esac
done
