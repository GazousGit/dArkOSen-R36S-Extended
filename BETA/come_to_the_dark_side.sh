#!/bin/bash

# =======================================
# dArkOSen Clone Patcher v1.0
# by djparent
# =======================================

# Copyright (c) 2026 djparent
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# =======================================================
# Root privileges check
# =======================================================
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

# =======================================================
# Initialization
# =======================================================
export TERM=linux

# =======================================================
# Variables
# =======================================================
GPTOKEYB_PID=""
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"

T_STARTING="Starting, please wait..."
T_BACKTITLE="dArkOSen Clone Patcher"
T_MAIN_TITLE="Main Menu"
T_RIGHT="Right stick X/Y swapped"
T_LEFT="Left stick X/Y swapped"
T_SWAP="Sticks swapped left <--> right"
T_DEFAULT="Restore default setting"
T_EXIT="Exit"

# =======================================================
# Start gamepad input
# =======================================================
Start_GPTKeyb() {
    pkill -9 -f gptokeyb 2>/dev/null || true
    if [ -n "${GPTOKEYB_PID:-}" ]; then
        kill "$GPTOKEYB_PID" 2>/dev/null
    fi
    sleep 0.1
	/opt/inttools/gptokeyb -1 "$0" -c "$TMP_KEYS" > /dev/null 2>&1 &
    GPTOKEYB_PID=$!
}

# =======================================================
# Stop gamepad input
# =======================================================
Stop_GPTKeyb() {
    if [ -n "$GPTOKEYB_PID" ]; then
        kill "$GPTOKEYB_PID" 2>/dev/null
        GPTOKEYB_PID=""
    fi
}

# =======================================================
# Font Selection
# =======================================================
ORIGINAL_FONT=$(setfont -v 2>&1 | grep -o '/.*\.psf.*')
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz

# =======================================================
# Display Management
# =======================================================
printf "\e[?25l" > "$CURR_TTY"
dialog --clear
Stop_GPTKeyb
pgrep -f osk.py | xargs kill -9
printf "\033[H\033[2J" > "$CURR_TTY"
printf "$T_STARTING" > "$CURR_TTY"
sleep 0.5

# =======================================================
# Exit the script
# =======================================================
Exit_Menu() {
	trap - EXIT
    printf "\033[H\033[2J" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY"
	Stop_GPTKeyb
    rm -f "$TMP_KEYS"
    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        [ -n "$ORIGINAL_FONT" ] && setfont "$ORIGINAL_FONT"
    fi

    exit 0
}

# =======================================================
# Patch DTBs
# =======================================================
Dlg() {
    dialog --title "DTB Patch" --infobox "$1" 7 60 > /dev/tty1
    sleep 2
}

Compile_DTB() {
    dtc -I dts -O dtb -o "$2.tmp" "$1" 2>/dev/null && [ -s "$2.tmp" ] && mv "$2.tmp" "$2" || {
        rm -f "$2.tmp"
        return 1
    }
}

Patch_Boot_DTBs() {
    for dtb in /boot/*linux.dtb; do
        [ -f "$dtb" ] || continue

        dts="${dtb%.dtb}.dts"
        Dlg "Processing:\n$dtb"
		[ -f "$dtb.orig" ] || cp "$dtb" "$dtb.orig"
        dtc -I dtb -O dts -o "$dts" "$dtb" 2>/dev/null || {
            Dlg "ERROR: decompile failed:\n$dtb"
            rm -f "$dts"
            continue
        }

        if grep -q '^[[:space:]]*odroidgo3-joypad {' "$dts"; then
            if grep -q 'amux-channel-mapping' "$dts"; then
                Dlg "Already patched:\n$dtb"
            else
                awk '
                    { print }
                    /^[[:space:]]*odroidgo3-joypad \{/ {
                        print "\t\tamux-channel-mapping = <0 1 2 3>;"
                    }
                ' "$dts" > "$dts.tmp" && mv "$dts.tmp" "$dts"

                Compile_DTB "$dts" "$dtb" || {
                    Dlg "ERROR: recompile failed:\n$dtb"
                    continue
                }
				
                Dlg "Patched:\n$dtb"
            fi
        else
            Dlg "ERROR: odroidgo3-joypad node not found:\n$dtb"
        fi	
    done
}

# =======================================================
# Set AMUX Mapping
# =======================================================
Set_AMUX_Mapping() {
    [ $# -eq 4 ] || { Dlg "ERROR: need 4 values (got $#)"; return 1; }

    for v in "$@"; do
        case "$v" in
            0|1|2|3) ;;
            *) Dlg "ERROR: invalid value: $v (use 0-3)"; return 1 ;;
        esac
    done

    map="$1 $2 $3 $4"

    for dts in /boot/*linux.dts; do
        [ -f "$dts" ] || continue

        dtb="${dts%.dts}.dtb"

        Dlg "Processing:\n$dts"

        if ! grep -q 'amux-channel-mapping' "$dts"; then
            Dlg "ERROR: amux-channel-mapping not found:\n$dts"
            continue
        fi

        sed -i "s/amux-channel-mapping = <[^>]*>;/amux-channel-mapping = <$map>;/" "$dts"

        Compile_DTB "$dts" "$dtb" || {
            Dlg "ERROR: recompile failed:\n$dts"
            continue
        }

        Dlg "Mapping <$map> set:\n$dtb"
    done
}

# =======================================================
# Main Menu dialog
# =======================================================
Main_Menu() {
	while true; do
		# --- keep gptokeyb alive ---
		if [[ -z $(pgrep -f gptokeyb) ]]; then
			Start_GPTKeyb
		fi
		
		local CHOICE
		CHOICE=$(dialog \
			--clear \
			--colors \
			--no-collapse \
			--cancel-label "$T_EXIT" \
			--backtitle "$T_BACKTITLE" \
			--title "$T_MAIN_TITLE" \
			--menu "" \
			14 45 6 \
			"1" "$T_RIGHT" \
            "2" "$T_LEFT" \
			"3" "$T_SWAP" \
			"4" "$T_DEFAULT" \
            2>&1 > "$CURR_TTY")
			
			[[ $? -ne 0 ]] && Exit_Menu

			case "$CHOICE" in
				1) Set_AMUX_Mapping 1 0 2 3 ;;
				2) Set_AMUX_Mapping 0 1 3 2 ;;
				3) Set_AMUX_Mapping 2 3 0 1 ;;
				4) Set_AMUX_Mapping 0 1 2 3 ;;
			esac
	done
}

# =======================================================
# Gamepad Setup
# =======================================================
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
chmod 666 /dev/uinput
cp /opt/inttools/keys.gptk "$TMP_KEYS"
if grep -q '^b = backspace' "$TMP_KEYS"; then
    sed -i 's/^b = .*/b = esc/' "$TMP_KEYS"
    sed -i 's/^a = .*/a = enter/' "$TMP_KEYS"
fi
Start_GPTKeyb

# =======================================================
# Main Execution
# =======================================================
printf "\033[H\033[2J" > "$CURR_TTY"
dialog --clear
trap 'Exit_Menu' EXIT

Patch_Boot_DTBs

Main_Menu
