#!/bin/bash

# =======================================================
# Shortcuts  (dArkOSen Extended)
#
# - Shows the key combinations of the system, of
#   EmulationStation and of the emulators (quit, menu,
#   save states...), one page each.
# - Reminder before a game: perfmax, the script dArkOSen
#   runs before every launch, calls
#   /usr/local/bin/launch-reminder, which prints the page
#   of the emulator about to start for up to 10 seconds;
#   A goes on at once. This tool turns it on or off and
#   sets the time.
# - Hotkey layout "universal": the same keys in every
#   emulator that can take them (see retroarch.txt):
#   FN = menu, SELECT + START = quit, SELECT + R1 / L1 =
#   save / load state, SELECT + R2 / L2 = next / previous
#   slot, SELECT + L3 = fast-forward. "darkosen" puts the
#   values of the dArkOSen image back. Only the keys
#   listed in the *_LAYOUT tables are touched.
#
# The pages are plain text files: first line = title, lines
# starting with # are not shown. A file in <roms>/shortcuts/
# replaces the built-in one of the same name in
# /usr/share/dArkOSen-Extended/shortcuts/, so the texts can
# be corrected from a PC (README.txt there has the rules).
# <key>.darkosen.txt is the page shown while the layout is
# "darkosen".
#
# Command line (no UI):
#   --repair          make sure the settings file and the
#                     hook in perfmax exist, and re-apply the
#                     universal layout to files an update
#                     put back to dArkOSen's values; run at
#                     boot by the self-repair service and by
#                     the image build (root in SHORTCUTS_ROOT)
#   --remove-hook     take the hook out of perfmax
#   --status          print the state
#   --layout NAME     apply the hotkey layout universal|darkosen
#   --layout-status   universal | darkosen | mixed | missing
#   --layout-report   the same, file by file
#   --page KEY        print the page file used for KEY
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
D_RA64="/home/ark/.config/retroarch/retroarch.cfg"
D_RA32="/home/ark/.config/retroarch32/retroarch.cfg"
D_M64="/home/ark/.config/mupen64plus/mupen64plus.cfg"
D_DS="/home/ark/.local/share/duckstation/settings.ini"
D_PPSSPP_OPT="/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/controls.ini"
D_FLYCAST="/home/ark/.config/flycast/mappings/SDL_GO-Super Gamepad.cfg"
D_DRASTIC="/opt/drastic/config/drastic.cfg"
D_GCDB="/opt/inttools/gamecontrollerdb.txt"
D_SBIN="/usr/local/sbin"
D_OGAGE_SCRIPTS="/usr/local/bin"
D_RETRORUN="/home/ark/.config/retrorun.cfg"
D_RETRORUN_BIN="/usr/local/bin/retrorun"      # and retrorun32: the hotkeys build carries RETRORUN_MARK
PERFMAX="$ROOT$D_PERFMAX"; CONF="$ROOT$D_CONF"; TEXTS="$ROOT$D_TEXTS"
HOOK_TAG="# shortcuts-hook"
HOOK_LINE="[ -x $D_HELPER ] && $D_HELPER  $HOOK_TAG"
WRAP_TAG="# dArkOSen Extended: universal hotkey layout"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="Shortcuts - dArkOSen Extended"

# ---- Hotkey layouts: key|universal|darkosen -------------------------------------------
# RetroArch buttons (retroarch.cfg, both builds): B=0 A=1 X=2 Y=3 L1=4 R1=5 L2=6 R2=7 UP=8
# DOWN=9 LEFT=10 RIGHT=11 SELECT=12 START=13 L3=14 R3=15 FN=16; the hotkey is SELECT
# (input_enable_hotkey_btn = 12, left as is). SELECT + L1 / R1 are also Wi-Fi / Bluetooth
# toggles of dArkOSen's hotkey daemon (ogage): the "universal" layout installs two wrappers
# in /usr/local/sbin (first on the daemon's PATH) that do nothing while a game runs.
RA_LAYOUT=(
    "input_menu_toggle_gamepad_combo|0|8"      # 8 = hold SELECT 2 s; 0 = none
    "input_menu_toggle_btn|16|nul"             # FN
    "input_load_state_btn|4|1"                 # L1 / A
    "input_save_state_btn|5|0"                 # R1 / B
    "input_state_slot_decrease_btn|6|3"        # L2 / Y
    "input_state_slot_increase_btn|7|2"        # R2 / X
    "input_toggle_fast_forward_btn|14|11"      # L3 / RIGHT
    "input_hold_fast_forward_btn|nul|9"        # - / DOWN
    "input_rewind_btn|10|10"                   # LEFT (hold)
    "input_reset_btn|0|7"                      # B / R2
    "input_screenshot_btn|1|14"                # A / L3
    "input_pause_toggle_btn|3|15"              # Y / R3 (R3 also speaks the battery level)
    "input_frame_advance_btn|nul|8"            # - / UP (pauses the game, see retroarch.darkosen.txt)
)
# mupen64plus.cfg [CoreEvents]: J0B12 = SELECT, then the same numbers (SDL joystick order)
M64_LAYOUT=(
    "Joy Mapping Load State|J0B12/B4|J0B12/B6"      # SELECT + L1 / L2
    "Joy Mapping Save State|J0B12/B5|J0B12/B7"      # SELECT + R1 / R2
    "Joy Mapping Increment Slot|J0B12/B7|"          # SELECT + R2 / -
    "Joy Mapping Fast Forward|J0B12/B14|"           # SELECT + L3 (hold) / -
    "Joy Mapping Pause|J0B12/B3|J0B12/B1"           # SELECT + Y / A
    "Joy Mapping Reset|J0B12/B0|J0B12/B2"           # SELECT + B / X
    "Joy Mapping Screenshot|J0B12/B1|"              # SELECT + A / -
)
# Ini-style `key = value` lines inside a section: several values = several lines (joined
# with ;), @none = no line. DuckStation settings.ini [Hotkeys] (SDL names, Back = SELECT;
# Guide = FN once gamecontrollerdb.txt declares it, see GCDB below).
DS_LAYOUT=(
    "LoadSelectedSaveState|SDL-0/Back & SDL-0/LeftShoulder|SDL-0/Back & SDL-0/+LeftTrigger"
    "SaveSelectedSaveState|SDL-0/Back & SDL-0/RightShoulder|SDL-0/Back & SDL-0/+RightTrigger"
    "SelectPreviousSaveStateSlot|SDL-0/Back & SDL-0/+LeftTrigger|SDL-0/Back & SDL-0/DPadDown"
    "SelectNextSaveStateSlot|SDL-0/Back & SDL-0/+RightTrigger|SDL-0/Back & SDL-0/DPadUp"
    "ToggleFastForward|SDL-0/Back & SDL-0/LeftStick|SDL-0/Back & SDL-0/DPadRight"
    "OpenPauseMenu|SDL-0/Guide;SDL-0/Back & SDL-0/X|SDL-0/Back & SDL-0/X"
)
# PPSSPP 1.20 controls.ini [ControlMapping]: device 10 = pad, 1 = keyboard; a:b combination
# is "a:b", alternatives are separated by commas. Pad codes: SELECT 196, L1 193, R1 192,
# L3 106, A 189, B 190, LEFT 21, FN (Guide) 4, L2 / R2 = trigger axes 4008 / 4010.
PPSSPP_LAYOUT=(
    "Pause|1-111,10-4|1-111"
    "Save State|10-196:10-192|10-107"
    "Load State|10-196:10-193|10-106"
    "Previous Slot|10-196:10-4008|@none"
    "Next Slot|10-196:10-4010|@none"
    "SpeedToggle|1-68,10-196:10-106|1-68"
    "Rewind|1-67,10-196:10-21|1-67"
    "Screenshot|10-196:10-189|@none"
    "Reset|10-196:10-190|@none"
)
# Flycast standalone mapping [digital]: raw pad numbers; single buttons only. FN opens the
# menu next to SELECT, L3 (held) fast-forwards.
FLYCAST_LAYOUT=(
    "bind16|16:btn_menu|@none"
    "bind14|14:btn_fforward|@none"
)
# DraStic drastic.cfg (pad = 1024 + number): FN = 1040 takes the menu from L3 = 1038, which
# takes "swap screens". Single buttons only.
DRASTIC_LAYOUT=(
    "controls_b[CONTROL_INDEX_MENU]|1040|1038"
    "controls_b[CONTROL_INDEX_SWAP_SCREENS]|1038|1040"
)
# retrorun.cfg (plain `key = value`, no section): read by the retrorun hotkeys build only
# (components/retrorun_hotkeys: navy1978/retrorun 3.0.0 + retrorun_hotkey_* settings); while
# dArkOSen's own build is installed the component is "missing" and the page shows its keys.
# Values are retrorun's button names on the R36S: F5 = FN, F3 = L3, TriggerLeft / TriggerRight
# = L2 / R2. Save / load state stay on SELECT + R1 / L1, the quit on SELECT + START.
RETRORUN_LAYOUT=(
    "retrorun_hotkey_menu|F5|@none"
    "retrorun_hotkey_slot_next|TriggerRight|@none"
    "retrorun_hotkey_slot_prev|TriggerLeft|@none"
    "retrorun_hotkey_fast_forward|F3|@none"
)
RETRORUN_MARK="retrorun_hotkey_menu"
GCDB_LINE='^190000004b4800000011000000010000,GO-Super Gamepad,'
GCDB_ADD='guide:b16,'
# ------------------------------------------------------------------------------------

# Roms root: follow SD2 setups (Storage Settings rewrites the paths to /roms2)
ES_CFG="$ROOT/etc/emulationstation/es_systems.cfg"
if grep -q "<path>/roms2/" "$ES_CFG" 2>/dev/null && ! grep -q "<path>/roms/" "$ES_CFG"; then
    D_ROMS="/roms2"
else
    D_ROMS="/roms"
fi
USER_TEXTS="$ROOT$D_ROMS/shortcuts"
D_PPSSPP_ROMS="$D_ROMS/psp/ppsspp/PSP/SYSTEM/controls.ini"

Own() { chown --reference="$(dirname "$CONF")" "$@" 2>/dev/null || :; }
Load_Conf() {
    REMINDER=1; DELAY=10; LAYOUT=darkosen
    [ -f "$CONF" ] && . "$CONF"
    [[ "$DELAY" =~ ^[0-9]+$ ]] || DELAY=10
    [ "$LAYOUT" = universal ] || LAYOUT=darkosen
}
Save_Conf() {
    mkdir -p "$(dirname "$CONF")"
    printf 'REMINDER=%s\nDELAY=%s\nLAYOUT=%s\n' "$REMINDER" "$DELAY" "$LAYOUT" > "$CONF"
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

# ---- file editing ----------------------------------------------------------------------
Col() { case "$1" in universal) echo 2 ;; darkosen) echo 3 ;; *) return 1 ;; esac; }
Field() { cut -d'|' -f"$2" <<<"$1"; }
# `key = "value"` lines (RetroArch, mupen64plus)
Cfg_Get() { sed -n "s#^$2 = \"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*\$#\1#p" "$1" | head -1; }
Cfg_Set() {      # file key value: replaces the line or appends it; keeps inode, mode and owner
    local f=$1 k=$2 v=$3 tmp="$1.sc.tmp"
    if grep -q "^$k = " "$f"; then
        sed "s#^$k = .*#$k = \"$v\"#" "$f" > "$tmp"
    else
        { cat "$f"; [ -z "$(tail -c1 "$f")" ] || echo; echo "$k = \"$v\""; } > "$tmp"
    fi
    cat "$tmp" > "$f"; rm -f "$tmp"
}
# `key = value` lines inside [section] ("" = the whole file); values joined with ;
BOM=$'\xef\xbb\xbf'      # PPSSPP writes its ini files with a byte order mark
Ini_Get() {
    awk -v sec="$2" -v key="$3" -v bom="$BOM" '
        BEGIN { insec = (sec == "") }
        NR == 1 && index($0, bom) == 1 { $0 = substr($0, length(bom) + 1) }
        /^\[[^]]*\]/ { s = $0; sub(/^\[/, "", s); sub(/\].*$/, "", s); insec = (sec == "" || s == sec); next }
        insec {
            line = $0; sub(/\r$/, "", line); eq = index(line, "=")
            if (eq == 0) next
            k = substr(line, 1, eq - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
            if (k != key) next
            v = substr(line, eq + 1); gsub(/^[ \t]+|[ \t]+$/, "", v)
            out = (out == "") ? v : out ";" v
        }
        END { print out }' "$1"
}
Ini_Set() {      # file section key values(;-joined, @none = remove); keeps inode, mode and owner
    local f=$1 tmp="$1.sc.tmp"
    awk -v sec="$2" -v key="$3" -v vals="$4" -v bom="$BOM" '
        function pr(s) { printf "%s%s\n", pfx, s; pfx = "" }      # the byte order mark stays on the first line
        function emit(   i) { if (vals != "@none") for (i = 1; i <= n; i++) pr(key " = " V[i]); done = 1 }
        function flush(   i) { for (i = 0; i < pend; i++) pr(""); pend = 0 }
        BEGIN { n = split(vals, V, ";"); insec = (sec == ""); seen = insec; pend = 0; pfx = "" }
        NR == 1 && index($0, bom) == 1 { $0 = substr($0, length(bom) + 1); pfx = bom }
        /^\[[^]]*\]/ {
            if (insec && !done) emit()
            flush()
            s = $0; sub(/^\[/, "", s); sub(/\].*$/, "", s)
            insec = (sec == "" || s == sec); if (insec) seen = 1
            pr($0); next
        }
        /^[ \t]*\r?$/ { if (insec) { pend++; next } pr($0); next }
        {
            if (insec) {
                line = $0; sub(/\r$/, "", line); eq = index(line, "=")
                if (eq > 0) { k = substr(line, 1, eq - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
                    if (k == key) { if (!done) { flush(); emit() }; next } }
            }
            flush(); pr($0)
        }
        END {
            if (insec && !done) emit()
            flush()
            if (!seen && !done && vals != "@none") { pr("[" sec "]"); emit() }
        }' "$f" > "$tmp"
    cat "$tmp" > "$f"; rm -f "$tmp"
}
Gcdb_Status() {      # gamecontrollerdb.txt: FN declared as the Guide button?
    local f="$ROOT$D_GCDB" line
    [ -f "$f" ] || { echo missing; return; }
    line=$(grep -m1 "$GCDB_LINE" "$f") || { echo missing; return; }
    case "$line" in *"$GCDB_ADD"*) echo universal ;; *) echo darkosen ;; esac
}
Gcdb_Set() {
    local f="$ROOT$D_GCDB" tmp
    tmp="$f.sc.tmp"
    if [ "$1" = universal ]; then
        sed "\\#$GCDB_LINE# { /$GCDB_ADD/! s/platform:/${GCDB_ADD}platform:/ }" "$f" > "$tmp"
    else
        sed "\\#$GCDB_LINE# s/$GCDB_ADD//" "$f" > "$tmp"
    fi
    cat "$tmp" > "$f"; rm -f "$tmp"
}
Wrap_Status() {      # the two ogage wrappers in /usr/local/sbin
    local n=0 s
    for s in toggle_wifi.sh toggle_bt.sh; do grep -qsF "$WRAP_TAG" "$ROOT$D_SBIN/$s" && n=$((n + 1)); done
    case "$n" in
        0) if [ -f "$ROOT$D_OGAGE_SCRIPTS/toggle_wifi.sh" ]; then echo darkosen; else echo missing; fi ;;
        2) echo universal ;;
        *) echo mixed ;;
    esac
}
Wrap_Set() {
    local s
    for s in toggle_wifi.sh toggle_bt.sh; do
        if [ "$1" = universal ]; then
            mkdir -p "$ROOT$D_SBIN"
            cat > "$ROOT$D_SBIN/$s" <<EOF
#!/bin/bash
$WRAP_TAG
# SELECT + L1 / R1 load and save a state in the emulators, and dArkOSen's hotkey daemon
# (ogage) runs this script on the same combination. Nothing happens while a game runs
# (perfmax creates /tmp/game-running, perfnorm removes it); otherwise dArkOSen's own
# script runs. Removed by Options > Shortcuts > Hotkey layout > darkosen.
[ -e /tmp/game-running ] && exit 0
exec $D_OGAGE_SCRIPTS/$s "\$@"
EOF
            chmod 755 "$ROOT$D_SBIN/$s"
        else
            grep -qsF "$WRAP_TAG" "$ROOT$D_SBIN/$s" && rm -f "$ROOT$D_SBIN/$s"
        fi
    done
}

# ---- components ------------------------------------------------------------------------
# name: file (or -), format (cfg|ini|gcdb|wrap), ini section, layout table
COMPONENTS="ra64 ra32 m64 ds ppsspp-opt ppsspp-roms flycast drastic retrorun gcdb wrap"
Comp_File() {
    case "$1" in
        ra64) echo "$ROOT$D_RA64" ;; ra32) echo "$ROOT$D_RA32" ;; m64) echo "$ROOT$D_M64" ;;
        ds) echo "$ROOT$D_DS" ;; ppsspp-opt) echo "$ROOT$D_PPSSPP_OPT" ;; ppsspp-roms) echo "$ROOT$D_PPSSPP_ROMS" ;;
        flycast) echo "$ROOT$D_FLYCAST" ;; drastic) echo "$ROOT$D_DRASTIC" ;; gcdb) echo "$ROOT$D_GCDB" ;;
        retrorun) echo "$ROOT$D_RETRORUN" ;;
        wrap) echo "$ROOT$D_OGAGE_SCRIPTS/toggle_wifi.sh" ;;
    esac
}
Comp_Section() { case "$1" in ds) echo Hotkeys ;; ppsspp-*) echo ControlMapping ;; flycast) echo digital ;; *) echo "" ;; esac; }
Comp_Entries() {      # prints the table of the component, one entry per line
    case "$1" in
        ra64|ra32) printf '%s\n' "${RA_LAYOUT[@]}" ;; m64) printf '%s\n' "${M64_LAYOUT[@]}" ;;
        ds) printf '%s\n' "${DS_LAYOUT[@]}" ;; ppsspp-*) printf '%s\n' "${PPSSPP_LAYOUT[@]}" ;;
        flycast) printf '%s\n' "${FLYCAST_LAYOUT[@]}" ;; drastic) printf '%s\n' "${DRASTIC_LAYOUT[@]}" ;;
        retrorun) printf '%s\n' "${RETRORUN_LAYOUT[@]}" ;;
    esac
}
Retrorun_Patched() { grep -qs "$RETRORUN_MARK" "$ROOT$D_RETRORUN_BIN" "$ROOT${D_RETRORUN_BIN}32"; }
Comp_Status() {       # universal | darkosen | mixed | missing
    local c=$1 f e k u d v allu=1 alld=1 sec
    case "$c" in gcdb) Gcdb_Status; return ;; wrap) Wrap_Status; return ;; retrorun) Retrorun_Patched || { echo missing; return; } ;; esac
    f=$(Comp_File "$c"); [ -f "$f" ] || { echo missing; return; }
    sec=$(Comp_Section "$c")
    while IFS= read -r e; do
        k=${e%%|*}; u=$(Field "$e" 2); d=$(Field "$e" 3)
        case "$c" in ra64|ra32|m64) v=$(Cfg_Get "$f" "$k") ;; *) v=$(Ini_Get "$f" "$sec" "$k"); [ "$u" = "@none" ] && u=""; [ "$d" = "@none" ] && d="" ;; esac
        [ "$v" = "$u" ] || allu=0
        [ "$v" = "$d" ] || alld=0
    done < <(Comp_Entries "$c")
    if [ "$allu" = 1 ]; then echo universal; elif [ "$alld" = 1 ]; then echo darkosen; else echo mixed; fi
}
Comp_Apply() {        # component layout -> 0 applied, 1 file missing
    local c=$1 name=$2 col f e k v sec
    col=$(Col "$name") || return 1
    case "$c" in
        gcdb) [ -f "$ROOT$D_GCDB" ] || return 1; Gcdb_Set "$name"; return 0 ;;
        wrap) [ -f "$ROOT$D_OGAGE_SCRIPTS/toggle_wifi.sh" ] || return 1; Wrap_Set "$name"; return 0 ;;
        retrorun) Retrorun_Patched || return 1 ;;
    esac
    f=$(Comp_File "$c"); [ -f "$f" ] || return 1
    sec=$(Comp_Section "$c")
    while IFS= read -r e; do
        k=${e%%|*}; v=$(Field "$e" "$col")
        case "$c" in ra64|ra32|m64) Cfg_Set "$f" "$k" "$v" ;; *) Ini_Set "$f" "$sec" "$k" "$v" ;; esac
    done < <(Comp_Entries "$c")
}
Layout_Status() {     # the layout found in the files that exist
    local c s r=""
    for c in $COMPONENTS; do
        s=$(Comp_Status "$c"); [ "$s" = missing ] && continue
        if [ -z "$r" ]; then r=$s; elif [ "$r" != "$s" ]; then r=mixed; fi
    done
    echo "${r:-missing}"
}
Layout_Report() { local c; for c in $COMPONENTS; do printf '%-12s %s  %s\n' "$c" "$(Comp_Status "$c")" "$(Comp_File "$c")"; done; }
Apply_Layout() {      # universal | darkosen
    local name=$1 c n=0
    Col "$name" >/dev/null || { echo "shortcuts: unknown layout '$name' (universal or darkosen)" >&2; return 1; }
    for c in $COMPONENTS; do
        if Comp_Apply "$c" "$name"; then n=$((n + 1))
        elif [ "$c" = retrorun ]; then echo "shortcuts: retrorun: hotkeys build not installed, skipped"
        else echo "shortcuts: $c: ${c#*-} file not found, skipped"; fi
    done
    [ "$n" -gt 0 ] || { echo "shortcuts: no configuration file found, layout not applied"; return 0; }
    Load_Conf; LAYOUT=$name; Save_Conf
    echo "shortcuts: hotkey layout '$name' applied to $n file(s)"
}
Migrate_Layout() {    # universal layout chosen: files back at dArkOSen's exact values (an update,
    local c n=0       # a first boot) get it again; files changed by hand ("mixed") are left alone
    Load_Conf; [ "$LAYOUT" = universal ] || return 0
    for c in $COMPONENTS; do
        [ "$(Comp_Status "$c")" = darkosen ] || continue
        Comp_Apply "$c" universal && n=$((n + 1))
    done
    [ "$n" -eq 0 ] || echo "shortcuts: universal layout re-applied to $n file(s)"
}
Do_Repair() {
    Load_Conf
    [ -f "$CONF" ] || Save_Conf
    Migrate_Layout
    if Install_Hook; then echo "shortcuts: launch hook: OK"; else echo "shortcuts: launch hook: FAILED ($D_PERFMAX missing?)"; return 1; fi
}

# ---- pages -----------------------------------------------------------------------------
# Every <key>.txt (the .darkosen variants are picked through their base name), yours first;
# system, emulationstation, retroarch and retrorun lead the list
Pages() {
    { for d in "$TEXTS" "$USER_TEXTS"; do
          [ -d "$d" ] && find "$d" -maxdepth 1 -type f -iname '*.txt' -printf '%f\n'
      done; } | sed 's/\.[Tt][Xx][Tt]$//; s/\.darkosen$//' | grep -vix 'readme' | sort -u \
      | awk '{ p = ($0 == "system") ? 0 : ($0 == "emulationstation") ? 1 : ($0 == "retroarch") ? 2 : ($0 == "retrorun") ? 3 : 4; print p "\t" $0 }' \
      | sort -k1,1n -k2,2 | cut -f2
}
Page_File() {      # same search as launch-reminder: yours first, the .darkosen variant first in that layout
    local k=$1 d lay
    Load_Conf; lay=$LAYOUT
    [ "$k" = retrorun ] && [ "$lay" = universal ] && ! Retrorun_Patched && lay=darkosen      # dArkOSen's own retrorun keeps its keys
    for d in "$USER_TEXTS" "$TEXTS"; do
        if [ "$lay" = darkosen ] && [ -f "$d/$k.darkosen.txt" ]; then echo "$d/$k.darkosen.txt"; return; fi
        if [ -f "$d/$k.txt" ]; then echo "$d/$k.txt"; return; fi
    done
    echo "$TEXTS/$k.txt"
}
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
    --repair)        Do_Repair; exit $? ;;
    --remove-hook)   Remove_Hook; exit 0 ;;
    --status)        Load_Conf; Hook_Present && h="present" || h="missing"; echo "reminder=$REMINDER delay=$DELAY hook=$h layout=$LAYOUT files=$(Layout_Status) texts=$D_ROMS/shortcuts"; exit 0 ;;
    --layout)        Apply_Layout "${2:-}"; exit $? ;;
    --layout-status) Layout_Status; exit 0 ;;
    --layout-report) Layout_Report; exit 0 ;;
    --page)          Page_File "${2:-}"; exit 0 ;;
    --pages)         Pages; exit 0 ;;
    --export)        Export; exit $? ;;
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
    ls=$(Layout_Status)
    case "$ls" in
        universal) lt="universal (FN menu, SELECT + R1/L1 states)" ;;
        darkosen)  lt="dArkOSen's own" ;;
        mixed)     lt="MIXED (changed by hand?) - pages: $LAYOUT" ;;
        *)         lt="no configuration file found" ;;
    esac
    keys=(); items=()
    while IFS= read -r k; do
        keys+=("$k"); items+=("${#keys[@]}" "$(Title "$(Page_File "$k")")")
    done < <(Pages)
    items+=(L "Hotkey layout: $lt" R "Reminder before a game: turn ON / OFF" D "Reminder duration" E "Copy the texts to $D_ROMS/shortcuts (to edit)")

    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "Shortcuts" \
        --menu "Reminder before a game: $rs | Launch hook: $hk\nYour own texts go in $D_ROMS/shortcuts" \
        22 70 14 "${items[@]}" 2>&1 > "$CURR_TTY") || Exit_Menu

    case "$CHOICE" in
        L) l=$(dialog --clear --backtitle "$BACKTITLE" --title "Hotkey layout" \
               --menu "The same keys in RetroArch, DuckStation, PPSSPP, the N64\nstandalone, Flycast, DraStic and retrorun with its hotkeys\nbuild (Saturn keeps its own). Current: $lt" 16 70 4 \
               universal "FN menu, SELECT + START quit, R1/L1 states, R2/L2 slot, L3 speed" \
               darkosen  "dArkOSen's values: each emulator its own keys" 2>&1 > "$CURR_TTY") || continue
           out=$(Apply_Layout "$l" 2>&1); Msg "$out\n\nThe pages shown before a game follow the layout." 12 66 ;;
        R) [ "$REMINDER" = 1 ] && REMINDER=0 || REMINDER=1; Save_Conf ;;
        D) d=$(dialog --clear --backtitle "$BACKTITLE" --title "Reminder duration" \
               --menu "How long the reminder stays on screen\nbefore the game starts.\nA (or B, Start) goes on at once." 15 46 6 \
               3 "3 s" 5 "5 s" 10 "10 s" 15 "15 s" 20 "20 s" 30 "30 s" 2>&1 > "$CURR_TTY") && { DELAY=$d; Save_Conf; } ;;
        E) n=$(Export); Msg "$n text file(s) copied to\n$D_ROMS/shortcuts\n\nEdit them on a PC: the first line is the title, lines\nstarting with # are not shown. A file there replaces\nthe built-in one of the same name." 13 58 ;;
        *) f=$(Page_File "${keys[$((CHOICE - 1))]}")
           dialog --clear --backtitle "$BACKTITLE" --title "$(Title "$f")" --msgbox "$(Body "$f")" 21 68 > "$CURR_TTY" ;;
    esac
done
