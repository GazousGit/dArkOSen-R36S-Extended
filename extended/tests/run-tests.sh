#!/bin/bash
# =======================================================
# Offline tests for Boot Video Manager and inject.sh
# Run on Linux as root (WSL, a container, a CI runner):
#   sudo bash extended/tests/run-tests.sh
# Needs bash, awk, python3. Optional: ffmpeg, shellcheck.
# =======================================================
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TOOL="$REPO/extended/bootvideo/Boot Video Manager.sh"
INJECT="$REPO/extended/build/inject.sh"
BUILD="$REPO/extended/build/build-image.sh"
FIXBOOT="$REPO/extended/build/fix-boot.sh"
GROW="$REPO/extended/build/grow-root.sh"
T=$(mktemp -d)
trap 'umount "$T/root9" "$T/rootbtrfs" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAILED=0

ok()   { PASS=$((PASS+1)); echo "  ok   $*"; }
fail() { FAILED=$((FAILED+1)); echo "  FAIL $*"; }
expect() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi; }

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# A fake dArkOSen root: the real upstream ES script, a small es_systems.cfg,
# and a "populated" roms partition (launchimages exists, as after first boot).
make_root() {   # $1 = dir, $2 = roms path used in es_systems.cfg (/roms or /roms2)
    local R=$1 ROMS=${2:-/roms}
    mkdir -p "$R/usr/bin/emulationstation" "$R/etc/emulationstation" "$R/etc/systemd/system" \
             "$R/home/ark/.config" "$R/roms" "$R/roms2" "$R$ROMS/launchimages" \
             "$R/opt/system/System" "$R/usr/local/bin"
    cp "$REPO/usr/bin/emulationstation/emulationstation.sh" "$R/usr/bin/emulationstation/"
    chmod 755 "$R/usr/bin/emulationstation/emulationstation.sh"
    cp "$REPO/usr/local/bin/perfmax" "$R/usr/local/bin/"; chmod 755 "$R/usr/local/bin/perfmax"
    cat > "$R/etc/emulationstation/es_systems.cfg" <<EOF
<?xml version="1.0"?>
<systemList>
  <system>
    <name>nes</name>
    <fullname>Nintendo Entertainment System</fullname>
    <path>$ROMS/nes/</path>
    <extension>.nes .NES .zip .ZIP</extension>
    <command>/usr/local/bin/perfnorm %ROM%</command>
    <platform>nes</platform>
    <theme>nes</theme>
  </system>
  <system>
    <name>options</name>
    <fullname>Options</fullname>
    <path>/opt/system/</path>
    <extension>.sh</extension>
    <command>sudo chmod 666 /dev/tty1; %ROM% 2>&amp;1 > /dev/tty1</command>
    <platform>ignore</platform>
    <theme>options</theme>
  </system>
</systemList>
EOF
    echo 'root:x:0:0:root:/root:/bin/bash'              > "$R/etc/passwd"
    echo 'ark:x:1000:1000:ark:/home/ark:/bin/bash'     >> "$R/etc/passwd"
    mkdir -p "$R/home/ark/.config/retroarch" "$R/home/ark/.emulationstation"
    # dArkOSen's es_settings.cfg: the settings follow the XML declaration, no root element
    printf '<?xml version="1.0"?>\n<bool name="InvertButtons" value="true" />\n<string name="ThemeSet" value="es-theme-retrodark" />\n' > "$R/home/ark/.emulationstation/es_settings.cfg"
    printf 'reicast_alpha_sorting = "per-strip (fast, least accurate)"\nsnes9x_overclock = "disabled"\n' > "$R/home/ark/.config/retroarch/retroarch-core-options.cfg"
    # the hotkey lines of dArkOSen's retroarch.cfg (both builds) and mupen64plus.cfg, as in 10152026
    mkdir -p "$R/home/ark/.config/retroarch32" "$R/home/ark/.config/mupen64plus"
    for b in retroarch retroarch32; do
        cat > "$R/home/ark/.config/$b/retroarch.cfg" <<EOF
input_enable_hotkey_btn = "12"
input_exit_emulator_btn = "13"
input_frame_advance_btn = "8"
input_hold_fast_forward_btn = "9"
input_load_state_btn = "1"
input_menu_toggle_btn = "nul"
input_menu_toggle_gamepad_combo = "8"
input_pause_toggle_btn = "15"
input_player1_a_btn = "1"
input_quit_gamepad_combo = "4"
input_remapping_directory = "~/.config/$b/config/remaps"
input_reset_btn = "7"
input_rewind_btn = "10"
input_save_state_btn = "0"
input_screenshot_btn = "14"
input_state_slot_decrease_btn = "3"
input_state_slot_increase_btn = "2"
input_toggle_fast_forward_btn = "11"
EOF
    done
    cat > "$R/home/ark/.config/mupen64plus/mupen64plus.cfg" <<'EOF'
[CoreEvents]

# Joystick event string for stopping the emulator
Joy Mapping Stop = "J0B12/B13"
# Joystick event string for saving the emulator state
Joy Mapping Save State = "J0B12/B7"
# Joystick event string for loading the emulator state
Joy Mapping Load State = "J0B12/B6"
# Joystick event string for advancing the save state slot
Joy Mapping Increment Slot = ""
# Joystick event string for resetting the emulator
Joy Mapping Reset = "J0B12/B2"
# Joystick event string for taking a screenshot
Joy Mapping Screenshot = ""
# Joystick event string for pausing the emulator
Joy Mapping Pause = "J0B12/B1"
# Joystick event string for fast-forward
Joy Mapping Fast Forward = ""


[Input-SDL-Control1]

# Mupen64Plus SDL Input Plugin config parameter version number.  Please don't change this version number.
version = 2.000000
EOF
    # DuckStation, PPSSPP (the /opt backup and the copy next to the roms), Flycast standalone,
    # DraStic, the SDL controller database and the daemon scripts, as shipped by 10152026
    mkdir -p "$R/home/ark/.local/share/duckstation" "$R/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM" \
             "$R/home/ark/.config/flycast/mappings" "$R/opt/drastic/config" "$R/opt/inttools"
    cat > "$R/home/ark/.local/share/duckstation/settings.ini" <<'EOF'
[Main]
PauseOnMenu = true
SaveStateOnExit = true

[Hotkeys]
LoadSelectedSaveState = SDL-0/Back & SDL-0/+LeftTrigger
OpenPauseMenu = SDL-0/Back & SDL-0/X
PowerOff = SDL-0/Back & SDL-0/Start
Reset = SDL-0/Back & SDL-0/B
Rewind = SDL-0/Back & SDL-0/DPadLeft
SaveSelectedSaveState = SDL-0/Back & SDL-0/+RightTrigger
Screenshot = SDL-0/Back & SDL-0/A
SelectNextSaveStateSlot = SDL-0/Back & SDL-0/DPadUp
SelectPreviousSaveStateSlot = SDL-0/Back & SDL-0/DPadDown
ToggleFastForward = SDL-0/Back & SDL-0/DPadRight
ToggleWidescreen = SDL-0/Back & SDL-0/Y

[Logging]
LogLevel = Info
EOF
    # PPSSPP's backup copy (the one next to the roms appears at the first launch); PPSSPP
    # writes the file with a UTF-8 byte order mark, like the real one
    printf '\xef\xbb\xbf' > "$R/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/controls.ini"
    cat >> "$R/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/controls.ini" <<'EOF'
[ControlMapping]
Up = 10-19
Down = 10-20
Select = 10-196
Start = 10-197
SpeedToggle = 1-68
Pause = 1-111
Rewind = 1-67
Save State = 10-107
Load State = 10-106
EOF
    cat > "$R/home/ark/.config/flycast/mappings/SDL_GO-Super Gamepad.cfg" <<'EOF'
[analog]
bind0 = 0-:btn_analog_left
bind1 = 0+:btn_analog_right

[digital]
bind0 = 0:btn_a
bind1 = 1:btn_b
bind10 = 10:btn_dpad1_left
bind11 = 11:btn_dpad1_right
bind12 = 12:btn_menu
bind13 = 13:btn_start
bind2 = 2:btn_y
bind3 = 3:btn_x

[emulator]
dead_zone = 10
mapping_name = GO-Super Gamepad
version = 4
EOF
    cat > "$R/opt/drastic/config/drastic.cfg" <<'EOF'
frameskip_type = 2
controls_a[CONTROL_INDEX_MENU] = 1038
controls_a[CONTROL_INDEX_SWAP_SCREENS] = 115
controls_b[CONTROL_INDEX_UP] = 1032
controls_b[CONTROL_INDEX_MENU] = 1038
controls_b[CONTROL_INDEX_SAVE_STATE] = 65535
controls_b[CONTROL_INDEX_SWAP_SCREENS] = 1040
EOF
    cat > "$R/opt/inttools/gamecontrollerdb.txt" <<'EOF'
19000000010000000100000001010000,odroidgo2 joypad,a:b1,b:b0,platform:Linux,
190000004b4800000011000000010000,GO-Super Gamepad,x:b2,a:b1,b:b0,y:b3,back:b12,start:b13,dpleft:b10,dpdown:b9,dpright:b11,dpup:b8,leftshoulder:b4,lefttrigger:b6,rightshoulder:b5,righttrigger:b7,leftstick:b14,rightstick:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3,platform:Linux,
03000000091200000031000011010000,OpenSimHardware OSH PB Controller,a:b0,b:b1,platform:Linux,
EOF
    printf '#!/bin/bash\necho wifi toggled\n' > "$R/usr/local/bin/toggle_wifi.sh"; printf '#!/bin/bash\necho bt toggled\n' > "$R/usr/local/bin/toggle_bt.sh"
    chmod 755 "$R/usr/local/bin/toggle_wifi.sh" "$R/usr/local/bin/toggle_bt.sh"
    # retrorun.cfg (first lines of 10152026's) and dArkOSen's own retrorun builds, which know no retrorun_hotkey_* setting
    printf '# ---- RETRORUN INTERNAL SETTINGS ----\nretrorun_screenshot_folder = /roms/dreamcast\nretrorun_alternative_input_mode = true\nretrorun_swap_l1r1_with_l2r2 = true\n# ---- FLYCAST ----\nreicast_threaded_rendering = enabled\n' > "$R/home/ark/.config/retrorun.cfg"
    printf 'stock retrorun 3.0.0\n' > "$R/usr/local/bin/retrorun"; printf 'stock retrorun32 3.0.0\n' > "$R/usr/local/bin/retrorun32"
}
xml_ok() { python3 -I -c 'import sys,xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$1"; }
count_systems() { python3 -I -c 'import sys,xml.etree.ElementTree as E; print(sum(1 for s in E.parse(sys.argv[1]).getroot() if s.findtext("name")==sys.argv[2]))' "$1" "$2"; }

echo "== syntax"
expect "bash -n Boot Video Manager.sh" bash -n "$TOOL"
expect "bash -n inject.sh"             bash -n "$INJECT"
expect "bash -n build-image.sh"        bash -n "$BUILD"
expect "bash -n fix-boot.sh"          bash -n "$FIXBOOT"
expect "bash -n grow-root.sh"         bash -n "$GROW"
if command -v shellcheck >/dev/null; then
    expect "shellcheck Boot Video Manager.sh" shellcheck -S warning -e SC1090,SC1091,SC2016,SC2024 "$TOOL"
    expect "shellcheck inject.sh"             shellcheck -S warning "$INJECT"
    expect "shellcheck build-image.sh"        shellcheck -S warning -e SC2016 "$BUILD"
    expect "shellcheck fix-boot.sh"          shellcheck -S warning "$FIXBOOT"
    expect "shellcheck grow-root.sh"         shellcheck -S warning "$GROW"
    expect "shellcheck launch-reminder"      shellcheck -S warning -e SC1090 "$REPO/extended/overlay/usr/local/bin/launch-reminder"
    expect "shellcheck run-tests.sh"          shellcheck -S warning -e SC2016 "$0"
else
    echo "  skip shellcheck (not installed)"
fi
for f in "$REPO"/components/flycast_32_hack/*.sh; do
    expect "bash -n flycast_32_hack/$(basename "$f")" bash -n "$f"
    if command -v shellcheck >/dev/null; then
        expect "shellcheck flycast_32_hack/$(basename "$f")" shellcheck -S warning "$f"
    fi
done
for f in "$REPO"/extended/overlay/opt/system/Advanced/*.sh "$REPO"/extended/overlay/opt/system/*.sh "$REPO"/extended/overlay/usr/local/bin/*; do
    expect "bash -n $(basename "$f")" bash -n "$f"
    if command -v shellcheck >/dev/null; then
        expect "shellcheck $(basename "$f")" shellcheck -S warning -e SC1090,SC1091,SC2016 "$f"
    fi
done

echo "== offline install into a fake root"
R="$T/root"; make_root "$R"
cp "$R/usr/bin/emulationstation/emulationstation.sh" "$T/es.orig"
cp "$R/etc/emulationstation/es_systems.cfg" "$T/cfg.orig"
expect "--install-root exits 0" bash "$TOOL" --install-root "$R"
HELPER="$R/usr/local/bin/bootvideo.sh"; CONF="$R/home/ark/.config/bootvideo.conf"
ES="$R/usr/bin/emulationstation/emulationstation.sh"; CFG="$R/etc/emulationstation/es_systems.cfg"
UNIT="$R/etc/systemd/system/bootvideo-repair.service"
WANTS="$R/etc/systemd/system/multi-user.target.wants/bootvideo-repair.service"
expect "helper written and executable"        test -x "$HELPER"
expect "helper has valid bash syntax"         bash -n "$HELPER"
expect "repair wrapper written"               test -x "$R/usr/local/bin/bootvideo-repair"
expect "service unit written"                 test -f "$UNIT"
expect "service enabled via wants symlink"    test -L "$WANTS"
expect "wants symlink points to the unit"     test "$(readlink "$WANTS")" = "/etc/systemd/system/bootvideo-repair.service"
expect "unit runs before emulationstation"    grep -q '^Before=emulationstation.service' "$UNIT"
expect "unit waits for the roms mount"        grep -q '^RequiresMountsFor=/roms' "$UNIT"
expect "tool copied to /opt/system/System"    cmp -s "$TOOL" "$R/opt/system/System/Boot Video Manager.sh"
expect "config: ENABLED=1"                    grep -q '^ENABLED=1$' "$CONF"
expect "config: ES_ENTRY=1"                   grep -q '^ES_ENTRY=1$' "$CONF"
expect "config: VOLUME=0 (system volume)"     grep -q '^VOLUME=0$' "$CONF"
expect "config: DIR=/roms/bootvideos"         grep -q '^DIR="/roms/bootvideos"$' "$CONF"
expect "config owned by ark (1000:1000)"      test "$(stat -c %u:%g "$CONF")" = "1000:1000"
# per-video volume through the helper (its DIR must point into the fake root)
printf 'DIR="%s"\n' "$R/roms/bootvideos" > "$T/bv.conf"; VOLS="$R/roms/bootvideos/.volumes.txt"
bv() { env BOOTVIDEO_CONF="$T/bv.conf" bash "$HELPER" --volume "$@"; }
expect "volume: unset video reports 100"      test "$(bv "Intro & Logo.mp4")" = "100"
expect "volume: set 150 and read it back"     test "$(bv "Intro & Logo.mp4" 150)" = "150"
expect "volume: stored as name=percent"       grep -qxF 'Intro & Logo.mp4=150' "$VOLS"
expect "volume: a path works like a name"     test "$(bv "$R/roms/bootvideos/disabled/Intro & Logo.mp4")" = "150"
expect "volume: second video stored too"      test "$(bv "a=b.mp4" 50)" = "50" && grep -qxF 'a=b.mp4=50' "$VOLS"
expect "volume: first entry kept"             grep -qxF 'Intro & Logo.mp4=150' "$VOLS"
expect "volume: 100 removes the entry"        test "$(bv "Intro & Logo.mp4" 100)" = "100" && ! grep -qF 'Intro & Logo' "$VOLS"
expect "volume: out of range is refused"      test "$(bv "a=b.mp4" 400 2>/dev/null; echo "rc=$?")" = "rc=1"
expect "volume: value kept after refusal"     test "$(bv "a=b.mp4")" = "50"
expect "volume: file owned by ark"            test "$(stat -c %u:%g "$VOLS")" = "1000:1000"
expect "volume: ffplay gain filter written"   grep -qF "args+=(-af \"\$gain\")" "$HELPER"
expect "bootvideos/disabled created"          test -d "$R/roms/bootvideos/disabled"
expect "bootvideos owned by ark"              test "$(stat -c %u:%g "$R/roms/bootvideos")" = "1000:1000"
expect "ES script still parses"               bash -n "$ES"
expect "ES script mode kept (755)"            test "$(stat -c %a "$ES")" = "755"
expect "exactly one hook line"                test "$(grep -c '# bootvideo-hook' "$ES")" = "1"
expect "hook line follows esdir= line"        awk '/esdir="\$\(dirname \$0\)"/{e=NR} /# bootvideo-hook/{h=NR} END{exit !(h==e+1)}' "$ES"
expect "hook references the device helper"    grep -q '\[ -x /usr/local/bin/bootvideo.sh \] && /usr/local/bin/bootvideo.sh' "$ES"
expect "ES backup equals the original"        cmp -s "$T/es.orig" "$ES.pre-bootvideo"
expect "es_systems.cfg is valid XML"          xml_ok "$CFG"
expect "exactly one bootvideos system"        test "$(count_systems "$CFG" bootvideos)" = "1"
expect "bootvideos path is /roms/bootvideos/" grep -q '<path>/roms/bootvideos/</path>' "$CFG"
expect "bootvideos command uses the helper"   grep -q '<command>/usr/local/bin/bootvideo.sh --menu %ROM%</command>' "$CFG"
expect "other systems untouched"              test "$(count_systems "$CFG" nes)" = "1"
expect "cfg backup equals the original"       cmp -s "$T/cfg.orig" "$CFG.pre-bootvideo"

echo "== idempotency"
S1=$(sha256sum "$ES" "$CFG" "$HELPER" "$CONF" | sha256sum)
expect "second --install-root exits 0" bash "$TOOL" --install-root "$R"
S2=$(sha256sum "$ES" "$CFG" "$HELPER" "$CONF" | sha256sum)
expect "nothing changed on the second run"    test "$S1" = "$S2"
expect "still exactly one hook line"          test "$(grep -c '# bootvideo-hook' "$ES")" = "1"
expect "still exactly one bootvideos system"  test "$(count_systems "$CFG" bootvideos)" = "1"

echo "== OTA simulation: upstream replaces emulationstation.sh and es_systems.cfg, then --repair"
cp "$T/es.orig" "$ES"; cp "$T/cfg.orig" "$CFG"; rm -f "$HELPER"
expect "--repair exits 0" env BOOTVIDEO_ROOT="$R" bash "$TOOL" --repair
expect "hook re-added once"                   test "$(grep -c '# bootvideo-hook' "$ES")" = "1"
expect "ES entry re-added once"               test "$(count_systems "$CFG" bootvideos)" = "1"
expect "helper re-written"                    test -x "$HELPER"
expect "config kept ENABLED=1"                grep -q '^ENABLED=1$' "$CONF"

echo "== v2 upgrade: config without ES_ENTRY but with a cfg backup"
R2="$T/root2"; make_root "$R2"
printf 'ENABLED=1\nSOUND=0\nMAXLEN=30\nMODE=single\nFILE="intro.mp4"\nDIR="/roms/bootvideos"\n' > "$R2/home/ark/.config/bootvideo.conf"
cp "$R2/etc/emulationstation/es_systems.cfg" "$R2/etc/emulationstation/es_systems.cfg.pre-bootvideo"
expect "--repair on a v2 layout exits 0" env BOOTVIDEO_ROOT="$R2" bash "$TOOL" --repair
expect "v2 settings preserved (MAXLEN=30)"    grep -q '^MAXLEN=30$' "$R2/home/ark/.config/bootvideo.conf"
expect "v2 settings preserved (FILE)"         grep -q '^FILE="intro.mp4"$' "$R2/home/ark/.config/bootvideo.conf"
expect "ES_ENTRY key added"                   grep -q '^ES_ENTRY=' "$R2/home/ark/.config/bootvideo.conf"
expect "ES entry restored from the v2 marker" test "$(count_systems "$R2/etc/emulationstation/es_systems.cfg" bootvideos)" = "1"

echo "== roms on SD2"
R3="$T/root3"; make_root "$R3" /roms2
expect "--install-root with /roms2 paths exits 0" bash "$TOOL" --install-root "$R3"
expect "config: DIR=/roms2/bootvideos"        grep -q '^DIR="/roms2/bootvideos"$' "$R3/home/ark/.config/bootvideo.conf"
expect "ES path is /roms2/bootvideos/"        grep -q '<path>/roms2/bootvideos/</path>' "$R3/etc/emulationstation/es_systems.cfg"
expect "bootvideos created on roms2"          test -d "$R3/roms2/bootvideos/disabled"
expect "nothing created on roms"              test ! -e "$R3/roms/bootvideos"

echo "== roms partition not ready (image build, or before first boot)"
R4="$T/root4"; make_root "$R4"; rmdir "$R4/roms/launchimages"
expect "--install-root exits 0 without a roms partition" bash "$TOOL" --install-root "$R4"
expect "no bootvideos folder created in the root fs"     test ! -e "$R4/roms/bootvideos"
expect "hook and ES entry installed anyway"              test "$(grep -c '# bootvideo-hook' "$R4/usr/bin/emulationstation/emulationstation.sh")" = "1"
mkdir -p "$R4/roms/launchimages"
expect "--repair exits 0 once roms is populated"         env BOOTVIDEO_ROOT="$R4" bash "$TOOL" --repair
expect "bootvideos folder created at the next repair"    test -d "$R4/roms/bootvideos/disabled"

echo "== hook fallback anchor (esdir line missing)"
R5="$T/root5"; make_root "$R5"
sed -i 's/esdir="\$(dirname \$0)"/esdir="\/usr\/bin\/emulationstation"/' "$R5/usr/bin/emulationstation/emulationstation.sh"
expect "--install-root exits 0 without the esdir anchor" bash "$TOOL" --install-root "$R5"
expect "hook inserted once via fallback"      test "$(grep -c '# bootvideo-hook' "$R5/usr/bin/emulationstation/emulationstation.sh")" = "1"
expect "hook sits in the normal boot branch"  awk '/BOOT_TO_RETROARCH" \]; then/{b=NR} /# bootvideo-hook/{h=NR} END{exit !(h==b+1)}' "$R5/usr/bin/emulationstation/emulationstation.sh"
expect "ES script still parses"               bash -n "$R5/usr/bin/emulationstation/emulationstation.sh"

echo "== inject.sh with shipped videos"
mkdir -p "$T/vids"
if command -v ffmpeg >/dev/null; then
    ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=15 -t 1 -pix_fmt yuv420p "$T/vids/Intro & Logo.mp4"
    ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=15 -t 1 -pix_fmt yuv420p "$T/vids/second.mp4"
else
    echo "fake" > "$T/vids/Intro & Logo.mp4"; echo "fake" > "$T/vids/second.mp4"
fi
echo "not a video" > "$T/vids/README.md"
R6="$T/root6"; make_root "$R6"; rmdir "$R6/roms/launchimages"      # like the image build: roms not available
OUTI=$(bash "$INJECT" "$R6" "$T/vids" 09302026 2>&1); RC=$?
SEED="$R6/usr/share/dArkOSen-Extended/bootvideos"
expect "inject.sh exits 0"                    test "$RC" = "0"
expect "inject.sh installed the tool"         test -x "$R6/opt/system/System/Boot Video Manager.sh"
expect "inject.sh wrote the build stamp"      grep -q '^DARKOSEN_EXTENDED_UPSTREAM_TAG=09302026$' "$R6/etc/dArkOSen-Extended.release"
expect "two videos in the seed folder"        test "$(ls "$SEED"/*.mp4 | wc -l)" = "2"
expect "README not shipped"                   test ! -e "$SEED/README.md"
expect "nothing written to the roms mount point" test ! -e "$R6/roms/bootvideos"
expect "inject reports 2 shipped videos"      grep -q 'shipped   -> 2 video' <<<"$OUTI"
DCTOOL="opt/system/Advanced/Dreamcast Tuning (retrorun).sh"
expect "overlay tool installed (755)"         test "$(stat -c %a "$R6/$DCTOOL")" = "755"
expect "overlay seed copy kept"               cmp -s "$REPO/extended/overlay/$DCTOOL" "$R6/usr/share/dArkOSen-Extended/overlay/$DCTOOL"
expect "overlay README not installed"         test ! -e "$R6/README.md"
expect "inject reports overlay files"         grep -qE 'overlay   -> [1-9][0-9]* file' <<<"$OUTI"
RACO6="$R6/home/ark/.config/retroarch/retroarch-core-options.cfg"
expect "N64 preset applied in the image"      grep -qx 'mupen64plus-43screensize = "320x240"' "$RACO6"
expect "N64 preset: FB emulation stays on"    grep -qx 'mupen64plus-EnableFBEmulation = "True"' "$RACO6"
expect "other cores' options untouched"       grep -qx 'snes9x_overclock = "disabled"' "$RACO6"
expect "N64 backup kept for restore"          test -f "$RACO6.mupen64plus.pre-ext"
ESS6="$R6/home/ark/.emulationstation/es_settings.cfg"
expect "N64 default emulator is retroarch"    grep -qx '<string name="n64.emulator" value="retroarch" />' "$ESS6"
expect "N64 default core is mupen64plus_next" grep -qx '<string name="n64.core" value="mupen64plus_next" />' "$ESS6"
expect "other ES settings kept"               test "$(grep -cE 'InvertButtons|ThemeSet|xml version' "$ESS6")" = "3"
rm -f "$R6/$DCTOOL"                                                     # an OTA update removed it
# first regular boot: roms is mounted and populated, the repair service seeds the videos once
mkdir -p "$R6/roms/launchimages"
expect "--repair exits 0 (first boot with roms)" env BOOTVIDEO_ROOT="$R6" bash "$TOOL" --repair
expect "overlay tool restored by --repair"    test -x "$R6/$DCTOOL"
expect "shipped videos copied to bootvideos"  test "$(ls "$R6/roms/bootvideos/"*.mp4 | wc -l)" = "2"
expect "video with & and spaces copied"       test -f "$R6/roms/bootvideos/Intro & Logo.mp4"
expect "seed marker written"                  test -e "$R6/roms/bootvideos/.seeded"
expect "copied videos owned by ark"           test "$(stat -c %u:%g "$R6/roms/bootvideos/second.mp4")" = "1000:1000"
rm -f "$R6/roms/bootvideos/second.mp4"                                # the user deletes one
expect "--repair exits 0 (later boot)"        env BOOTVIDEO_ROOT="$R6" bash "$TOOL" --repair
expect "deleted video is not copied again"    test ! -e "$R6/roms/bootvideos/second.mp4"
expect "inject.sh without videos exits 0"     bash "$INJECT" "$R6" "" 09302026
expect "N64 default still set exactly once"   test "$(grep -c '<string name="n64\.' "$ESS6")" = "2"
expect "seed folder removed when no videos"   test ! -e "$SEED"

echo "== inject.sh with files for the roms partition (appended to roms.tar)"
R7="$T/root7"; make_root "$R7"; rmdir "$R7/roms/launchimages"       # image build: roms not available
mkdir -p "$T/up/roms/bios" "$T/up/roms/launchimages"                 # what dArkOSen ships in /roms.tar
echo upstream > "$T/up/roms/bios/shipped.bin"; echo img > "$T/up/roms/launchimages/loading.jpg"
tar -cf "$T/roms.tar.orig" -C "$T/up" roms
cp "$T/roms.tar.orig" "$R7/roms.tar"
NORIG=$(tar -tf "$T/roms.tar.orig" | wc -l)
PD="$T/romsdir"; mkdir -p "$PD/bios/dc" "$PD/bootvideos" "$PD/psp/ppsspp/PSP/SYSTEM"
echo "not shipped" > "$PD/README.md"; echo '*' > "$PD/.gitignore"
head -c 70000 /dev/urandom > "$PD/bios/scph1001.bin"
echo flash > "$PD/bios/dc/DC boot & flash (v1).bin"
echo mine > "$PD/bios/SHIPPED.BIN"                                   # dArkOSen has bios/shipped.bin
echo video > "$PD/bootvideos/Logo.mp4"
echo ini > "$PD/psp/ppsspp/PSP/SYSTEM/ULUS10041_ppsspp.ini"
OUTR=$(bash "$INJECT" "$R7" "" 09302026 "$PD" 2>&1); RC=$?
expect "inject.sh exits 0"                    test "$RC" = "0"
expect "4 entries appended to roms.tar"       test "$(tar -tf "$R7/roms.tar" | wc -l)" = "$((NORIG + 4))"
expect "BIOS file listed as roms/bios/..."    bash -c 'tar -tf "$1" | grep -qx "roms/bios/scph1001.bin"' _ "$R7/roms.tar"
expect "README and .gitignore not shipped"    bash -c '! tar -tf "$1" | grep -qiE "readme|gitignore"' _ "$R7/roms.tar"
expect "file dArkOSen ships is not replaced"  bash -c '! tar -tf "$1" | grep -qx "roms/bios/SHIPPED.BIN"' _ "$R7/roms.tar"
expect "inject reports 4 files"               grep -q 'roms      -> 4 file' <<<"$OUTR"
expect "build stamp records the count"        grep -qx 'DARKOSEN_EXTENDED_ROMS_FILES=4' "$R7/etc/dArkOSen-Extended.release"
expect "nothing written to the roms mount point" test -z "$(ls -A "$R7/roms")"
# dArkOSen's first boot: pv -n /roms.tar | tar ... -xf - -C /   (into the new EASYROMS partition)
mkdir -p "$T/fb"
expect "first-boot extraction exits 0"        bash -c 'cat "$1" | tar --no-same-permissions --no-same-owner --warning=no-timestamp -xf - -C "$2"' _ "$R7/roms.tar" "$T/fb"
expect "BIOS file identical after extraction" cmp -s "$PD/bios/scph1001.bin" "$T/fb/roms/bios/scph1001.bin"
expect "name with spaces, & and () kept"      cmp -s "$PD/bios/dc/DC boot & flash (v1).bin" "$T/fb/roms/bios/dc/DC boot & flash (v1).bin"
expect "video lands in roms/bootvideos"       test -f "$T/fb/roms/bootvideos/Logo.mp4"
expect "nested settings file lands in place"  test -f "$T/fb/roms/psp/ppsspp/PSP/SYSTEM/ULUS10041_ppsspp.ini"
expect "dArkOSen's own file keeps its content" grep -qx upstream "$T/fb/roms/bios/shipped.bin"
expect "rest of roms.tar intact"              test -f "$T/fb/roms/launchimages/loading.jpg"
S1=$(sha256sum < "$R7/roms.tar")
expect "second inject.sh run exits 0"         bash "$INJECT" "$R7" "" 09302026 "$PD"
expect "second run appends nothing"           test "$S1" = "$(sha256sum < "$R7/roms.tar")"
R8="$T/root8"; make_root "$R8"; cp "$T/roms.tar.orig" "$R8/roms.tar"
mkdir -p "$T/romsempty"; echo "not shipped" > "$T/romsempty/README.md"
expect "folder with only a README exits 0"    bash "$INJECT" "$R8" "" 09302026 "$T/romsempty"
expect "inject.sh without a roms folder exits 0" bash "$INJECT" "$R8" "" 09302026
expect "roms.tar untouched in both cases"     cmp -s "$T/roms.tar.orig" "$R8/roms.tar"
rm -f "$R8/roms.tar"                                                  # an image that already went through first boot
OUTN=$(bash "$INJECT" "$R8" "" 09302026 "$PD" 2>&1); RC=$?
expect "files but no roms.tar: inject.sh fails" test "$RC" != "0"
expect "and says why"                         grep -q 'roms.tar not found' <<<"$OUTN"
R9="$T/root9"; mkdir -p "$R9"
if mount -t tmpfs -o size=48m tmpfs "$R9" 2>/dev/null; then           # a root filesystem with 48 MB free
    make_root "$R9"; cp "$T/roms.tar.orig" "$R9/roms.tar"
    mkdir -p "$T/romsbig/bios"; head -c 20000000 /dev/zero > "$T/romsbig/bios/big.bin"
    OUTB=$(bash "$INJECT" "$R9" "" 09302026 "$T/romsbig" 2>&1); RC=$?
    expect "files leaving under 32 MB free are refused" test "$RC" != "0"
    expect "and the message gives the sizes"  grep -q '19 MB.*32 MB must remain' <<<"$OUTB"
    expect "roms.tar untouched after the refusal" cmp -s "$T/roms.tar.orig" "$R9/roms.tar"
    head -c 2000000 /dev/zero > "$T/romsbig/bios/big.bin"
    expect "files that fit are accepted"      bash "$INJECT" "$R9" "" 09302026 "$T/romsbig"
    umount "$R9"
else
    echo "  skip free-space checks (cannot mount a tmpfs)"
fi
RB="$T/btrfs.img"; RBM="$T/rootbtrfs"; mkdir -p "$RBM"
if command -v mkfs.btrfs >/dev/null && truncate -s 256M "$RB" && mkfs.btrfs -q "$RB" >/dev/null 2>&1 \
   && mount -o loop,compress-force=zlib:1 "$RB" "$RBM" 2>/dev/null; then     # like build-image.sh mounts dArkOSen's root
    make_root "$RBM"; cp "$T/roms.tar.orig" "$RBM/roms.tar"
    mkdir -p "$T/romsz/bios"; head -c 230000000 /dev/zero > "$T/romsz/bios/big-but-compressible.bin"
    FREEZ=$(df --output=avail -k "$RBM" | tail -1 | tr -d ' ')
    OUTZ=$(bash "$INJECT" "$RBM" "" 10152026 "$T/romsz" 2>&1); RC=$?
    expect "compressed root: files larger than the free space are accepted" test "$RC" = "0" -a "$FREEZ" -lt 235000
    expect "the log gives size and space used"    grep -qE 'roms.tar \+1 file\(s\), 219 MB, [0-9]+ MB used on the root filesystem' <<<"$OUTZ"
    expect "the archive reads back"               bash -c 'test "$(tar -tf "$1" | wc -l)" = "$2"' _ "$RBM/roms.tar" "$((NORIG + 1))"
    umount "$RBM"
else
    echo "  skip compressed-root checks (no btrfs here)"
fi
echo "== themes and EmulationStation settings from the personal folder"
RT="$T/roottheme"; make_root "$RT"; cp "$T/roms.tar.orig" "$RT/roms.tar"
mkdir -p "$RT/tempthemes/es-theme-switch"; echo upstream > "$RT/tempthemes/es-theme-switch/theme.xml"
PT="$T/romstheme"; mkdir -p "$PT/themes/es-theme-nes-box/_inc" "$PT/themes/ES-THEME-SWITCH" "$PT/bios"
echo nes > "$PT/themes/es-theme-nes-box/theme.xml"; head -c 4096 /dev/urandom > "$PT/themes/es-theme-nes-box/_inc/bg.png"
echo mine > "$PT/themes/ES-THEME-SWITCH/theme.xml"; echo bios > "$PT/bios/x.bin"
printf '\xef\xbb\xbf<string name="GamelistViewStyle" value="video" />\r\n  <string name="ThemeSet" value="es-theme-nes-box" />\r\nnot a setting\r\n' > "$PT/es_settings.cfg"
OUTT=$(bash "$INJECT" "$RT" "" 10152026 "$PT" 2>&1); RC=$?
ESR="$RT/home/ark/.emulationstation/es_settings.cfg"
expect "inject with themes exits 0"           test "$RC" = "0"
expect "a new theme goes to /tempthemes"      cmp -s "$PT/themes/es-theme-nes-box/_inc/bg.png" "$RT/tempthemes/es-theme-nes-box/_inc/bg.png"
expect "a theme dArkOSen ships is kept (any case)" bash -c 'grep -qx upstream "$1/es-theme-switch/theme.xml" && test ! -e "$1/ES-THEME-SWITCH"' _ "$RT/tempthemes"
expect "and the log says so"                  grep -q 'theme ES-THEME-SWITCH is already in /tempthemes, not replaced' <<<"$OUTT"
expect "the log lists the added theme"        grep -qE '/tempthemes \+1 theme\(s\), 0 MB, [0-9]+ MB used on the root filesystem: es-theme-nes-box$' <<<"$OUTT"
expect "themes stay out of roms.tar"          bash -c '! tar -tf "$1" | grep -q "^roms/themes/"' _ "$RT/roms.tar"
expect "other files still go to roms.tar"     bash -c 'tar -tf "$1" | grep -qx roms/bios/x.bin' _ "$RT/roms.tar"
expect "es_settings.cfg stays out of roms.tar" bash -c '! tar -tf "$1" | grep -q es_settings' _ "$RT/roms.tar"
expect "build stamp: 1 theme, 2 settings"     bash -c 'grep -qx DARKOSEN_EXTENDED_THEMES=1 "$1" && grep -qx DARKOSEN_EXTENDED_ES_SETTINGS=2 "$1"' _ "$RT/etc/dArkOSen-Extended.release"
expect "es_settings: a new setting is added"  grep -qx '<string name="GamelistViewStyle" value="video" />' "$ESR"
expect "an existing one is replaced, not doubled" bash -c 'test "$(grep -c "name=\"ThemeSet\"" "$1")" = 1 && grep -qx "<string name=\"ThemeSet\" value=\"es-theme-nes-box\" />" "$1"' _ "$ESR"
expect "the other lines and the N64 default stay" bash -c 'grep -q "name=\"InvertButtons\" value=\"true\"" "$1" && grep -q "name=\"n64.emulator\"" "$1"' _ "$ESR"
expect "anything else is ignored, no CR or BOM" bash -c '! grep -q "not a setting" "$1" && ! grep -q "$(printf "\r")" "$1" && ! grep -q "$(printf "\357\273\277")" "$1"' _ "$ESR"
expect "every line still parses (flat layout)" python3 -I -c 'import sys,xml.etree.ElementTree as E; E.fromstring("<r>" + open(sys.argv[1]).read().split("?>", 1)[-1] + "</r>")' "$ESR"
RT2="$T/roottheme2"; make_root "$RT2"; cp "$T/roms.tar.orig" "$RT2/roms.tar"     # before 10152026: no /tempthemes
bash "$INJECT" "$RT2" "" 09302026 "$PT" >/dev/null 2>&1
expect "no /tempthemes: themes go into roms.tar" bash -c 'tar -tf "$1" | grep -qx roms/themes/es-theme-nes-box/theme.xml' _ "$RT2/roms.tar"

echo "== grow-root.sh: more room on the root partition, EASYROMS moved along"
GI="$T/grow.img"; S3=542720
if command -v sfdisk >/dev/null && command -v jq >/dev/null && truncate -s 300M "$GI" \
   && printf 'label: dos\nlabel-id: 0x6ebc7c15\nstart=2048, size=16384, type=c, bootable\nstart=18432, size=524288, type=83\nstart=%s, size=16384, type=7\n' "$S3" | sfdisk -q "$GI" 2>/dev/null; then
    BTRFS_OK=0; GL=""; GM="$T/growmnt"; mkdir -p "$GM"
    if command -v mkfs.btrfs >/dev/null && GL=$(losetup --find --show --partscan "$GI" 2>/dev/null); then
        udevadm settle 2>/dev/null || sleep 1
        if mkfs.btrfs -q "${GL}p2" >/dev/null 2>&1 && mount "${GL}p2" "$GM" 2>/dev/null; then
            echo marker > "$GM/marker"; umount "$GM"; BTRFS_OK=1
        fi
        losetup -d "$GL"
    fi
    head -c 8M /dev/urandom | dd of="$GI" bs=512 seek="$S3" conv=notrunc status=none       # stands for EASYROMS
    dd if="$GI" of="$T/p3.before" bs=512 skip="$S3" count=16384 status=none
    sfdisk -d "$GI" | grep -E '^label-id|img1 ' > "$T/fixed.before"
    OUTG=$(bash "$GROW" "$GI" 2 64 2>&1); RC=$?
    expect "grow-root.sh exits 0"                 test "$RC" = "0"
    expect "says what it did"                     grep -q 'partition 2 +64 MiB (524288 -> 655360 sectors), 1 partition(s) after it moved' <<<"$OUTG"
    expect "image 64 MiB bigger"                  test "$(stat -c %s "$GI")" = "$(( 364 * 1048576 ))"
    expect "partition 2 grown in place"           bash -c 'sfdisk -d "$1" | grep -q "img2 : start= *18432, size= *655360, type=83"' _ "$GI"
    expect "partition 3 moved by the same amount" bash -c 'sfdisk -d "$1" | grep -q "img3 : start= *$2, size= *16384, type=7"' _ "$GI" "$((S3 + 131072))"
    expect "its data moved with it"               bash -c 'cmp -s "$1" <(dd if="$2" bs=512 skip="$3" count=16384 status=none)' _ "$T/p3.before" "$GI" "$((S3 + 131072))"
    expect "partition 1, boot flag, disk id unchanged" bash -c 'cmp -s "$1" <(sfdisk -d "$2" | grep -E "^label-id|img1 ")' _ "$T/fixed.before" "$GI"
    expect "a partition that does not exist fails" bash -c '! bash "$1" "$2" 4 64 2>/dev/null' _ "$GROW" "$GI"
    expect "bad arguments fail"                   bash -c '! bash "$1" "$2" 2 0 2>/dev/null && ! bash "$1" "$2" x 64 2>/dev/null' _ "$GROW" "$GI"
    if [ "$BTRFS_OK" = 1 ] && GL=$(losetup --find --show --partscan "$GI" 2>/dev/null); then
        udevadm settle 2>/dev/null || sleep 1
        mount "${GL}p2" "$GM"; b0=$(df --output=size -k "$GM" | tail -1 | tr -d ' ')
        btrfs filesystem resize max "$GM" >/dev/null 2>&1; b1=$(df --output=size -k "$GM" | tail -1 | tr -d ' ')
        expect "btrfs grows into the new space (resize max)" test "$((b1 - b0))" = "65536"
        expect "and keeps its files"              grep -qx marker "$GM/marker"
        umount "$GM"
        expect "btrfs check clean afterwards"     btrfs check --readonly "${GL}p2"
        losetup -d "$GL"
    else
        echo "  skip btrfs part of grow-root (no btrfs or loop device here)"
    fi
    GG="$T/gpt.img"; truncate -s 64M "$GG"; printf 'label: gpt\nstart=2048, size=16384\nstart=18432, size=16384\n' | sfdisk -q "$GG" 2>/dev/null
    expect "GPT disks are refused"                bash -c '! bash "$1" "$2" 1 8 2>/dev/null' _ "$GROW" "$GG"
else
    echo "  skip grow-root checks (no sfdisk or jq)"
fi

RG="$REPO/extended/roms/.gitignore"
expect "extended/roms ignores every file"     grep -qx '\*' "$RG"
expect "only .gitignore and README.md are kept in git" test "$(grep -c '^!' "$RG")" = "2"

echo "== fix-boot.sh: model selector entries whose boot.ini names a missing device tree"
B="$T/boot"; mkdir -p "$B/dtb/r36s/R36S-V12 2023-08-18 Panel 4" "$B/dtb/r36s/R36S-V12 2023-08-18 Panel 0" "$B/dtb/r36s/Two candidates"
mkini() { printf 'odroidgoa-uboot-config\r\nsetenv dtb_loadaddr "0x01f00000"\r\nload mmc 1:1 ${loadaddr} Image\r\nload mmc 1:1 ${dtb_loadaddr} %s\r\nbooti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}\r\n' "$2" > "$1"; }
P4="$B/dtb/r36s/R36S-V12 2023-08-18 Panel 4"; P0="$B/dtb/r36s/R36S-V12 2023-08-18 Panel 0"; TWO="$B/dtb/r36s/Two candidates"
mkini "$B/boot.ini" rk3326-r36s-linux.dtb; touch "$B/rk3326-r36s-linux.dtb"
mkini "$P4/boot.ini" rk3326-r36h-linux.dtb; touch "$P4/rk3326-r36s-linux.dtb" "$P4/rg351mp-uboot.dtb"     # as in the 09302026 image
mkini "$P0/boot.ini" rk3326-r36s-linux.dtb; touch "$P0/rk3326-r36s-linux.dtb" "$P0/rg351mp-uboot.dtb"
mkini "$TWO/boot.ini" rk3326-x-linux.dtb; touch "$TWO/rk3326-a-linux.dtb" "$TWO/rk3326-b-linux.dtb"
cp "$P4/boot.ini" "$T/p4.ini.orig"; cp "$P0/boot.ini" "$T/p0.ini.orig"; cp "$TWO/boot.ini" "$T/two.ini.orig"
OUTF=$(bash "$FIXBOOT" "$B" 2>&1); RC=$?
expect "fix-boot.sh exits 0"                  test "$RC" = "0"
expect "reports one entry fixed"              grep -qx 'fix-boot: 1 entry fixed' <<<"$OUTF"
expect "Panel 4 now loads the dtb of its folder" grep -q 'load mmc 1:1 ${dtb_loadaddr} rk3326-r36s-linux.dtb' "$P4/boot.ini"
expect "only that line changed"               test "$(diff "$T/p4.ini.orig" "$P4/boot.ini" | grep -c '^[<>]')" = "2"
expect "Windows line endings kept"            test "$(grep -c $'\r$' "$P4/boot.ini")" = "5"
expect "consistent entries untouched"         cmp -s "$T/p0.ini.orig" "$P0/boot.ini"
expect "ambiguous entry left alone"           cmp -s "$T/two.ini.orig" "$TWO/boot.ini"
expect "and reported"                         grep -q 'Two candidates: boot.ini loads rk3326-x-linux.dtb, which is missing; 2 candidate' <<<"$OUTF"
expect "second run fixes nothing"             bash -c 'bash "$1" "$2" | grep -qx "fix-boot: 0 entries fixed"' _ "$FIXBOOT" "$B"
expect "not a BOOT partition: fails"          bash -c '! bash "$1" "$2" 2>/dev/null' _ "$FIXBOOT" "$T/vids"

echo "== overlay tool: Dreamcast Tuning (retrorun)"
DC="$REPO/extended/overlay/opt/system/Advanced/Dreamcast Tuning (retrorun).sh"
RC="$T/retrorun.cfg"
cat > "$RC" <<'EOF'
# ---- RETRORUN INTERNAL SETTINGS ----
retrorun_screenshot_folder = /roms/dreamcast
retrorun_alternative_input_mode = true
retrorun_swap_l1r1_with_l2r2 = true
# ---- FLYCAST ----
reicast_threaded_rendering = enabled
reicast_anisotropic_filtering = off
reicast_enable_dsp = disabled
reicast_enable_rtt = disabled
# Alpha sorting should be set to per strip
reicast_alpha_sorting = per-strip (fast, least accurate)
reicast_auto_skip_frame = enabled
reicast_framerate = normal
reicast_anisotropic_filtering = disabled
#PARALLEL
parallel-n64-framerate = fullspeed
parallel-n64-screensize = 640x480
EOF
cp "$RC" "$T/retrorun.orig"
expect "--fast exits 0"                       bash "$DC" --fast "$RC"
expect "backup of the original kept"          cmp -s "$T/retrorun.orig" "$RC.pre-ext"
expect "internal resolution 320x240 added"    grep -qx 'reicast_internal_resolution = 320x240' "$RC"
expect "added lines sit in the FLYCAST block" awk '/^# ---- FLYCAST ----/{f=NR} /^#PARALLEL/{p=NR} /^reicast_internal_resolution/{r=NR} END{exit !(r>f && r<p)}' "$RC"
expect "synchronous rendering disabled"       grep -qx 'reicast_synchronous_rendering = disabled' "$RC"
expect "cable type VGA (RGB)"                 grep -qx 'reicast_cable_type = VGA (RGB)' "$RC"
expect "duplicate anisotropic lines merged"   test "$(grep -c '^reicast_anisotropic_filtering' "$RC")" = "1"
expect "anisotropic filtering = off"          grep -qx 'reicast_anisotropic_filtering = off' "$RC"
expect "existing values kept once"            test "$(grep -c '^reicast_alpha_sorting' "$RC")" = "1"
expect "retrorun_* lines untouched"           grep -qx 'retrorun_swap_l1r1_with_l2r2 = true' "$RC"
expect "parallel-n64 lines untouched"         grep -qx 'parallel-n64-screensize = 640x480' "$RC"
expect "comments kept"                        grep -q '^# Alpha sorting should be set to per strip' "$RC"
expect "--fast is idempotent"                 bash -c 'bash "$1" --fast "$2" && test "$(grep -c "^reicast_internal_resolution" "$2")" = 1' _ "$DC" "$RC"
expect "--show lists the options"             bash -c 'bash "$1" --show "$2" | grep -q "^reicast_internal_resolution = 320x240"' _ "$DC" "$RC"
expect "--restore exits 0"                    bash "$DC" --restore "$RC"
expect "restore gives the original file back" cmp -s "$T/retrorun.orig" "$RC"
expect "backup removed after restore"         test ! -e "$RC.pre-ext"

echo "== overlay tool: Swap A-B in EmulationStation only"
SW="$REPO/extended/overlay/opt/system/Advanced/Swap A-B in EmulationStation only.sh"
ESS="$T/es_settings.cfg"
printf '<?xml version="1.0"?>\n<config>\n\t<bool name="DrawClock" value="true" />\n\t<bool name="FavoritesFirst" value="true" />\n\t<string name="ThemeSet" value="es-theme-nes-box" />\n</config>\n' > "$ESS"
cp "$ESS" "$T/es_settings.orig"
expect "--toggle exits 0 (normal -> swapped)" bash "$SW" --toggle "$ESS"
expect "InvertButtons=true added"             grep -q '<bool name="InvertButtons" value="true" />' "$ESS"
expect "added right after <config>"           awk '/<config>/{c=NR} /InvertButtons/{i=NR} END{exit !(i==c+1)}' "$ESS"
expect "es_settings.cfg still valid XML"      xml_ok "$ESS"
expect "exactly one InvertButtons line"       test "$(grep -c InvertButtons "$ESS")" = "1"
expect "--toggle exits 0 (swapped -> normal)" bash "$SW" --toggle "$ESS"
expect "file back to the original"            cmp -s "$T/es_settings.orig" "$ESS"
printf '<?xml version="1.0"?>\n<bool name="DrawClock" value="true" />\n<string name="ThemeSet" value="es-theme-nes-box" />\n' > "$ESS"   # dArkOSen's layout: no <config>
cp "$ESS" "$T/es_settings.flat"
expect "--toggle on a file without <config>"  bash "$SW" --toggle "$ESS"
expect "InvertButtons added after the XML declaration" awk '/xml version/{x=NR} /InvertButtons" value="true"/{i=NR} END{exit !(i==x+1)}' "$ESS"
expect "--toggle back"                        bash "$SW" --toggle "$ESS"
expect "flat file back to the original"       cmp -s "$T/es_settings.flat" "$ESS"

echo "== overlay tool: N64 Tuning (mupen64plus-next)"
N64="$REPO/extended/overlay/opt/system/Advanced/N64 Tuning (mupen64plus-next).sh"
RO="$T/retroarch-core-options.cfg"
printf 'mupen64plus-43screensize = "640x480"\nreicast_alpha_sorting = "per-strip (fast, least accurate)"\nsnes9x_overclock = "disabled"\n' > "$RO"
cp "$RO" "$T/ro.orig"
expect "--wiki exits 0"                       bash "$N64" --wiki "$RO"
expect "backup holds the old mupen64plus line" grep -qx 'mupen64plus-43screensize = "640x480"' "$RO.mupen64plus.pre-ext"
expect "resolution replaced in place (once)"  test "$(grep -c '^mupen64plus-43screensize' "$RO")" = "1"
expect "wiki: 4:3 resolution 320x240"         grep -qx 'mupen64plus-43screensize = "320x240"' "$RO"
expect "wiki: wide resolution 640x360"        grep -qx 'mupen64plus-169screensize = "640x360"' "$RO"
expect "wiki: threaded renderer on"           grep -qx 'mupen64plus-ThreadedRenderer = "True"' "$RO"
expect "wiki: hybrid filter off"              grep -qx 'mupen64plus-HybridFilter = "False"' "$RO"
expect "wiki: framebuffer emulation on"       grep -qx 'mupen64plus-EnableFBEmulation = "True"' "$RO"
expect "wiki: LOD emulation on"               grep -qx 'mupen64plus-EnableLODEmulation = "True"' "$RO"
expect "wiki: color buffer to RDRAM off"      grep -qx 'mupen64plus-EnableCopyColorToRDRAM = "Off"' "$RO"
expect "wiki: depth buffer to RDRAM software" grep -qx 'mupen64plus-EnableCopyDepthToRDRAM = "Software"' "$RO"
expect "wiki: accurate texture coordinates"   grep -qx 'mupen64plus-EnableInaccurateTextureCoordinates = "False"' "$RO"
expect "wiki: less accurate blending on"      grep -qx 'mupen64plus-EnableLegacyBlending = "True"' "$RO"
expect "wiki: overscan off"                   grep -qx 'mupen64plus-EnableOverscan = "Disabled"' "$RO"
expect "wiki: texture cache 8000"             grep -qx 'mupen64plus-MaxTxCacheSize = "8000"' "$RO"
expect "options the wiki does not show are left alone" bash -c '! grep -qE "^mupen64plus-(FrameDuping|EnableN64DepthCompare|cpucore|CountPerOp|pak1)" "$1"' _ "$RO"
expect "values are quoted (RetroArch format)" bash -c '! grep -E "^mupen64plus-[^=]+= [^\"]" "$1"' _ "$RO"
expect "no duplicate keys"                    bash -c 'test "$(grep "^mupen64plus-" "$1" | cut -d= -f1 | sort | uniq -d | wc -l)" = 0' _ "$RO"
expect "other cores untouched"                grep -qx 'reicast_alpha_sorting = "per-strip (fast, least accurate)"' "$RO"
expect "--wiki is idempotent"                 bash -c 'bash "$1" --wiki "$2" && test "$(grep -c "^mupen64plus-" "$2")" -eq 35' _ "$N64" "$RO"
expect "backup still the original line"       test "$(cat "$RO.mupen64plus.pre-ext")" = 'mupen64plus-43screensize = "640x480"'
expect "--show lists the lines"               bash -c 'bash "$1" --show "$2" | grep -q "^mupen64plus-rdp-plugin = \"gliden64\""' _ "$N64" "$RO"
expect "--restore exits 0"                    bash "$N64" --restore "$RO"
expect "restore gives the original back"      bash -c 'diff <(sort "$1") <(sort "$2") >/dev/null' _ "$T/ro.orig" "$RO"
expect "backup removed after restore"         test ! -e "$RO.mupen64plus.pre-ext"
printf 'snes9x_overclock = "disabled"\n' > "$RO"
expect "--wiki on a file without mupen lines" bash "$N64" --wiki "$RO"
expect "empty backup recorded"                test -f "$RO.mupen64plus.pre-ext" -a ! -s "$RO.mupen64plus.pre-ext"
expect "--restore removes all mupen lines"    bash -c 'bash "$1" --restore "$2" && test "$(grep -c "^mupen64plus-" "$2")" = 0' _ "$N64" "$RO"
# a device that got the earlier "fast" preset: the user had pak2 set, the old tool added the rest
printf 'mupen64plus-pak2 = "rumble"\n' > "$RO.mupen64plus.pre-ext"
printf 'snes9x_overclock = "disabled"\nmupen64plus-pak2 = "rumble"\nmupen64plus-EnableFBEmulation = "False"\nmupen64plus-FrameDuping = "True"\nmupen64plus-EnableLODEmulation = "False"\n' > "$RO"
expect "--wiki over the earlier fast preset"  bash "$N64" --wiki "$RO"
expect "framebuffer emulation back on"        grep -qx 'mupen64plus-EnableFBEmulation = "True"' "$RO"
expect "frame duping line of the old preset gone" bash -c '! grep -q "^mupen64plus-FrameDuping" "$1"' _ "$RO"
expect "the user's own line kept"             grep -qx 'mupen64plus-pak2 = "rumble"' "$RO"
expect "backup is the pre-tool state again"   test "$(cat "$RO.mupen64plus.pre-ext")" = 'mupen64plus-pak2 = "rumble"'
# N64 default emulator in EmulationStation's settings
ESN="$T/es_n64.cfg"
printf '<?xml version="1.0"?>\n<config>\n\t<string name="n64.emulator" value="retroarch32" />\n\t<string name="ThemeSet" value="es-theme-nes-box" />\n</config>\n' > "$ESN"
expect "--es-default exits 0"                 bash "$N64" --es-default "$ESN"
expect "previous N64 default replaced"        test "$(grep -c 'n64.emulator' "$ESN")" = "1" -a "$(grep -c 'value="retroarch32"' "$ESN")" = "0"
expect "emulator retroarch, core mupen64plus_next" test "$(grep -cE 'name="n64.emulator" value="retroarch" />|name="n64.core" value="mupen64plus_next" />' "$ESN")" = "2"
expect "lines sit inside <config>, valid XML" xml_ok "$ESN"
expect "--es-default is idempotent"           bash -c 'a=$(sha256sum < "$2"); bash "$1" --es-default "$2" && test "$a" = "$(sha256sum < "$2")"' _ "$N64" "$ESN"
expect "--es-default without the file fails"  bash -c '! bash "$1" --es-default "$2/nope.cfg"' _ "$N64" "$T"
# per-game option files
RAH="$T/rahome"; NR="$T/n64roms"; mkdir -p "$RAH/retroarch32" "$NR"
printf 'parallel-n64-cpucore = "dynamic_recompiler"\nparallel-n64-gfxplugin = "rice"\nparallel-n64-gfxplugin-accuracy = "low"\nparallel-n64-screensize = "320x240"\nsnes9x_overclock = "disabled"\n' > "$RAH/retroarch32/retroarch-core-options.cfg"
cp "$RAH/retroarch32/retroarch-core-options.cfg" "$T/ra32.orig"
touch "$NR/Pokemon Stadium (Europe) (Rev A).n64" "$NR/Pokemon Stadium 2 (Europe).n64" "$NR/Pokemon Stadium (USA).txt" "$NR/Paper Mario (Europe).n64"
PGO="$RAH/retroarch32/config/ParaLLEl N64/Pokemon Stadium (Europe) (Rev A).opt"
expect "--per-game writes one file"           bash -c 'test "$(N64_RA_HOME="$2" N64_ROMS="$3" bash "$1" --per-game | wc -l)" = 1' _ "$N64" "$RAH" "$NR"
expect "option file named after the rom"      test -f "$PGO"
expect "per-game: glide64 plugin"             grep -qx 'parallel-n64-gfxplugin = "glide64"' "$PGO"
expect "per-game: medium accuracy"            grep -qx 'parallel-n64-gfxplugin-accuracy = "medium"' "$PGO"
expect "per-game: 640x480"                    grep -qx 'parallel-n64-screensize = "640x480"' "$PGO"
expect "per-game: other options of the core carried over" grep -qx 'parallel-n64-cpucore = "dynamic_recompiler"' "$PGO"
expect "per-game: one line per key, this core only" test "$(cut -d= -f1 "$PGO" | sort -u | wc -l)" = "4" -a "$(wc -l < "$PGO")" = "4"
expect "no file for Pokemon Stadium 2 or others" test "$(find "$RAH/retroarch32/config" -name '*.opt' | wc -l)" = "1"
expect "global options untouched"             cmp -s "$T/ra32.orig" "$RAH/retroarch32/retroarch-core-options.cfg"

echo "== overlay tool: PPSSPP Sync standalone and 2021"
PP="$REPO/extended/overlay/opt/system/Advanced/PPSSPP Sync standalone and 2021.sh"
PR="$T/roms"; mkdir -p "$PR/psp/ppsspp/PSP/SYSTEM" "$PR/psp/ppsspp-2021/PSP/SYSTEM"
printf '[Graphics]\nRenderingMode = 1\n' > "$PR/psp/ppsspp/PSP/SYSTEM/ULUS10041_ppsspp.ini"
printf '[ControlMapping]\n' > "$PR/psp/ppsspp/PSP/SYSTEM/ULUS10041_controls.ini"
printf '[General]\nFirstRun = False\n' > "$PR/psp/ppsspp/PSP/SYSTEM/ppsspp.ini"
printf '[General]\nFirstRun = False\n[Graphics]\n' > "$PR/psp/ppsspp-2021/PSP/SYSTEM/ppsspp.ini.sdl"
printf 'old\n' > "$PR/psp/ppsspp-2021/PSP/SYSTEM/ULUS10041_ppsspp.ini"
cp "$PR/psp/ppsspp-2021/PSP/SYSTEM/ppsspp.ini.sdl" "$T/sdl.orig"
expect "--copy-to-2021 copies 2 files"        bash -c 'test "$(PPSSPP_ROMS="$2" bash "$1" --copy-to-2021)" = 2' _ "$PP" "$PR"
expect "per-game ini copied"                  cmp -s "$PR/psp/ppsspp/PSP/SYSTEM/ULUS10041_ppsspp.ini" "$PR/psp/ppsspp-2021/PSP/SYSTEM/ULUS10041_ppsspp.ini"
expect "previous target kept as .bak"         grep -qx old "$PR/psp/ppsspp-2021/PSP/SYSTEM/ULUS10041_ppsspp.ini.bak"
expect "main ppsspp.ini NOT copied"           test ! -e "$PR/psp/ppsspp-2021/PSP/SYSTEM/ppsspp.ini"
expect "--share-memstick exits 0"             env PPSSPP_ROMS="$PR" bash "$PP" --share-memstick
expect "MemStickDirectory set under [General]" awk -v d="MemStickDirectory = $PR/psp/ppsspp/" '/^\[General\]/{g=NR} $0==d{m=NR} END{exit !(m==g+1)}' "$PR/psp/ppsspp-2021/PSP/SYSTEM/ppsspp.ini.sdl"
expect "--own-memstick exits 0"               env PPSSPP_ROMS="$PR" bash "$PP" --own-memstick
expect "ppsspp.ini.sdl back to the original"  cmp -s "$T/sdl.orig" "$PR/psp/ppsspp-2021/PSP/SYSTEM/ppsspp.ini.sdl"

echo "== overlay tool: Shortcuts and the launch reminder"
SC="$REPO/extended/overlay/opt/system/Shortcuts.sh"
LR="$REPO/extended/overlay/usr/local/bin/launch-reminder"
STX="$REPO/extended/overlay/usr/share/dArkOSen-Extended/shortcuts"
PM6="$R6/usr/local/bin/perfmax"                                       # R6 went through inject.sh above
expect "helper installed (755)"               test "$(stat -c %a "$R6/usr/local/bin/launch-reminder")" = "755"
expect "tool installed in Options (755)"      test "$(stat -c %a "$R6/opt/system/Shortcuts.sh")" = "755"
expect "built-in pages installed"             test -f "$R6/usr/share/dArkOSen-Extended/shortcuts/retroarch.txt"
expect "exactly one hook line in perfmax"     test "$(grep -c '# shortcuts-hook' "$PM6")" = "1"
expect "the hook is the last line"            bash -c 'tail -1 "$1" | grep -q "launch-reminder  # shortcuts-hook$"' _ "$PM6"
expect "perfmax still parses, mode kept"      bash -c 'bash -n "$1" && test "$(stat -c %a "$1")" = 755' _ "$PM6"
expect "upstream's lines untouched"           bash -c 'diff <(grep -v "# shortcuts-hook" "$1") <(cat "$2"; echo) >/dev/null' _ "$PM6" "$REPO/usr/local/bin/perfmax"
expect "settings written, reminder on, 10 s, universal layout" test "$(tr '\n' ' ' < "$R6/home/ark/.config/shortcuts.conf")" = "REMINDER=1 DELAY=10 LAYOUT=universal "
expect "--status reports the hook"            bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --status | grep -q "reminder=1 delay=10 hook=present layout=universal files=universal"' _ "$SC" "$R6"
cp "$REPO/usr/local/bin/perfmax" "$PM6"                                # an OTA update replaced perfmax
printf 'REMINDER=0\nDELAY=4\n' > "$R6/home/ark/.config/shortcuts.conf" # and the user had turned the reminder off
expect "--repair (self-repair service) exits 0" env BOOTVIDEO_ROOT="$R6" bash "$TOOL" --repair
expect "hook re-added once"                   test "$(grep -c '# shortcuts-hook' "$PM6")" = "1"
expect "the user's settings are kept"         test "$(tr '\n' ' ' < "$R6/home/ark/.config/shortcuts.conf")" = "REMINDER=0 DELAY=4 "
expect "--remove-hook gives upstream's file back" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --remove-hook && diff "$3" <(cat "$4"; echo) >/dev/null' _ "$SC" "$R6" "$PM6" "$REPO/usr/local/bin/perfmax"
expect "pages: system, ES, retroarch, retrorun first; README and .darkosen variants are not pages" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --pages | tr '\n' ' ')" = "system emulationstation retroarch retrorun drastic.drastic dreamcast.standalone-Flycast duckstation-standalone n64 ppsspp ppsspp.standalone-2021 saturn standalone "
expect "--export copies the pages and the README" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --export)" = "$(ls "$STX"/*.txt | wc -l)" -a -f "$R6/roms/shortcuts/README.txt" -a -f "$R6/roms/shortcuts/retroarch.darkosen.txt"
echo "MINE" > "$R6/roms/shortcuts/n64.txt"
expect "a second export keeps edited files"   test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --export)" = "0" -a "$(cat "$R6/roms/shortcuts/n64.txt")" = "MINE"
expect "pages shown before a game fit 40 columns" bash -c '! grep -v "^#" "$1"/*.txt | grep -v "/README.txt:" | cut -d: -f2- | grep -qE "^.{39,}"' _ "$STX"
expect "pages fit the screen: title + 11 lines" bash -c 'for f in "$1"/*.txt; do case "$f" in */README.txt) continue ;; esac; test "$(grep -vc "^#" "$f")" -le 12 || exit 1; done' _ "$STX"

echo "== hotkey layout applied by the build (10 files), reversible byte for byte"
RC6="$R6/home/ark/.config"
RL="$T/layout-ref"; make_root "$RL"                                  # dArkOSen's files, for comparison
ppsspp_roms() { mkdir -p "$1/roms/psp/ppsspp/PSP/SYSTEM"; cp "$RL/opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/controls.ini" "$1/roms/psp/ppsspp/PSP/SYSTEM/"; }
ppsspp_roms "$RL"
printf 'REMINDER=0\nDELAY=4\nLAYOUT=universal\n' > "$R6/home/ark/.config/shortcuts.conf"   # the user keeps the universal layout
ppsspp_roms "$R6"                                                     # the first boot extracted the user's old copy: the repair service at boot migrates it
expect "--repair migrates the PPSSPP copy that appeared next to the roms" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --repair | grep -q "re-applied to 1 file"' _ "$SC" "$R6"
expect "retroarch.cfg: hold SELECT no longer opens the menu, FN does" bash -c 'grep -qx "input_menu_toggle_gamepad_combo = \"0\"" "$1" && grep -qx "input_menu_toggle_btn = \"16\"" "$1"' _ "$RC6/retroarch/retroarch.cfg"
expect "retroarch.cfg: R1 / L1 save / load"        bash -c 'grep -qx "input_save_state_btn = \"5\"" "$1" && grep -qx "input_load_state_btn = \"4\"" "$1"' _ "$RC6/retroarch/retroarch.cfg"
expect "retroarch.cfg: R2 / L2 next / previous slot" bash -c 'grep -qx "input_state_slot_increase_btn = \"7\"" "$1" && grep -qx "input_state_slot_decrease_btn = \"6\"" "$1"' _ "$RC6/retroarch/retroarch.cfg"
expect "retroarch.cfg: L3 fast-forward, no hold, no frame advance" bash -c 'grep -qx "input_toggle_fast_forward_btn = \"14\"" "$1" && grep -qx "input_hold_fast_forward_btn = \"nul\"" "$1" && grep -qx "input_frame_advance_btn = \"nul\"" "$1"' _ "$RC6/retroarch/retroarch.cfg"
expect "retroarch.cfg: B reset, A screenshot, Y pause, LEFT rewind" bash -c 'grep -qx "input_reset_btn = \"0\"" "$1" && grep -qx "input_screenshot_btn = \"1\"" "$1" && grep -qx "input_pause_toggle_btn = \"3\"" "$1" && grep -qx "input_rewind_btn = \"10\"" "$1"' _ "$RC6/retroarch/retroarch.cfg"
expect "retroarch.cfg: hotkey, quit and the other lines untouched" bash -c 'grep -qx "input_enable_hotkey_btn = \"12\"" "$1" && grep -qx "input_exit_emulator_btn = \"13\"" "$1" && grep -qx "input_quit_gamepad_combo = \"4\"" "$1" && grep -qx "input_player1_a_btn = \"1\"" "$1" && test "$(wc -l < "$1")" = 18' _ "$RC6/retroarch/retroarch.cfg"
expect "retroarch32 gets the same lines"       bash -c 'diff <(grep -v remapping "$1") <(grep -v remapping "$2") >/dev/null && grep -q "retroarch32/config/remaps" "$2"' _ "$RC6/retroarch/retroarch.cfg" "$RC6/retroarch32/retroarch.cfg"
expect "mupen64plus.cfg: R1/L1 states, R2 slot, L3 fast-forward, Y/B/A" bash -c 'grep -qx "Joy Mapping Save State = \"J0B12/B5\"" "$1" && grep -qx "Joy Mapping Load State = \"J0B12/B4\"" "$1" && grep -qx "Joy Mapping Increment Slot = \"J0B12/B7\"" "$1" && grep -qx "Joy Mapping Fast Forward = \"J0B12/B14\"" "$1" && grep -qx "Joy Mapping Pause = \"J0B12/B3\"" "$1" && grep -qx "Joy Mapping Reset = \"J0B12/B0\"" "$1" && grep -qx "Joy Mapping Screenshot = \"J0B12/B1\"" "$1"' _ "$RC6/mupen64plus/mupen64plus.cfg"
expect "mupen64plus.cfg: stop and the rest untouched" bash -c 'grep -qx "Joy Mapping Stop = \"J0B12/B13\"" "$1" && grep -qx "version = 2.000000" "$1" && test "$(wc -l < "$1")" = 24' _ "$RC6/mupen64plus/mupen64plus.cfg"
DS6="$R6/home/ark/.local/share/duckstation/settings.ini"
expect "DuckStation: R1/L1 states, L2/R2 slots, L3 fast-forward" bash -c 'grep -qx "LoadSelectedSaveState = SDL-0/Back & SDL-0/LeftShoulder" "$1" && grep -qx "SaveSelectedSaveState = SDL-0/Back & SDL-0/RightShoulder" "$1" && grep -qx "SelectPreviousSaveStateSlot = SDL-0/Back & SDL-0/+LeftTrigger" "$1" && grep -qx "SelectNextSaveStateSlot = SDL-0/Back & SDL-0/+RightTrigger" "$1" && grep -qx "ToggleFastForward = SDL-0/Back & SDL-0/LeftStick" "$1"' _ "$DS6"
expect "DuckStation: menu on FN (Guide) and still on SELECT + X, in place" bash -c 'test "$(grep -n "^OpenPauseMenu" "$1" | tr "\n" "|")" = "7:OpenPauseMenu = SDL-0/Guide|8:OpenPauseMenu = SDL-0/Back & SDL-0/X|"' _ "$DS6"
expect "DuckStation: reset, screenshot, rewind, widescreen, power off and the other sections kept" bash -c 'grep -qx "Reset = SDL-0/Back & SDL-0/B" "$1" && grep -qx "Screenshot = SDL-0/Back & SDL-0/A" "$1" && grep -qx "Rewind = SDL-0/Back & SDL-0/DPadLeft" "$1" && grep -qx "ToggleWidescreen = SDL-0/Back & SDL-0/Y" "$1" && grep -qx "PowerOff = SDL-0/Back & SDL-0/Start" "$1" && grep -qx "PauseOnMenu = true" "$1" && grep -qx "LogLevel = Info" "$1" && test "$(wc -l < "$1")" = 20' _ "$DS6"
for p in "$R6/opt/ppsspp/backupforromsfolder/ppsspp" "$R6/roms/psp/ppsspp"; do
expect "PPSSPP ${p#"$R6"}: combos for states, slots, speed, rewind, screenshot, reset, FN pause" bash -c 'grep -qx "Save State = 10-196:10-192" "$1" && grep -qx "Load State = 10-196:10-193" "$1" && grep -qx "Previous Slot = 10-196:10-4008" "$1" && grep -qx "Next Slot = 10-196:10-4010" "$1" && grep -qx "SpeedToggle = 1-68,10-196:10-106" "$1" && grep -qx "Rewind = 1-67,10-196:10-21" "$1" && grep -qx "Screenshot = 10-196:10-189" "$1" && grep -qx "Reset = 10-196:10-190" "$1" && grep -qx "Pause = 1-111,10-4" "$1" && grep -qx "Select = 10-196" "$1" && test "$(wc -l < "$1")" = 14 && test "$(head -c 3 "$1" | od -An -tx1 | tr -d " ")" = "efbbbf" && test "$(head -1 "$1" | tail -c +4)" = "[ControlMapping]" && test "$(grep -c "ControlMapping" "$1")" = 1' _ "$p/PSP/SYSTEM/controls.ini"
done
FC6="$R6/home/ark/.config/flycast/mappings/SDL_GO-Super Gamepad.cfg"
expect "Flycast: FN = menu and L3 = fast-forward added inside [digital]" bash -c 'test "$(sed -n "/^\[digital\]/,/^\[emulator\]/p" "$1" | tr "\n" "|")" = "[digital]|bind0 = 0:btn_a|bind1 = 1:btn_b|bind10 = 10:btn_dpad1_left|bind11 = 11:btn_dpad1_right|bind12 = 12:btn_menu|bind13 = 13:btn_start|bind2 = 2:btn_y|bind3 = 3:btn_x|bind16 = 16:btn_menu|bind14 = 14:btn_fforward||[emulator]|"' _ "$FC6"
DR6="$R6/opt/drastic/config/drastic.cfg"
expect "DraStic: FN = menu, L3 = swap screens, keyboard lines untouched" bash -c 'grep -qx "controls_b\[CONTROL_INDEX_MENU\] = 1040" "$1" && grep -qx "controls_b\[CONTROL_INDEX_SWAP_SCREENS\] = 1038" "$1" && grep -qx "controls_a\[CONTROL_INDEX_MENU\] = 1038" "$1" && test "$(wc -l < "$1")" = 7' _ "$DR6"
GC6="$R6/opt/inttools/gamecontrollerdb.txt"
expect "gamecontrollerdb: FN declared as Guide on the GO-Super line, nothing else" bash -c 'grep -q "^190000004b4800000011000000010000,GO-Super Gamepad,x:b2,.*righty:a3,guide:b16,platform:Linux,$" "$1" && test "$(grep -c guide "$1")" = 1 && test "$(wc -l < "$1")" = 3' _ "$GC6"
expect "ogage wrappers installed in /usr/local/sbin (755), calling upstream's scripts" bash -c 'test "$(stat -c %a "$1/toggle_wifi.sh")" = 755 && test "$(stat -c %a "$1/toggle_bt.sh")" = 755 && grep -q "^\[ -e /tmp/game-running \] && exit 0$" "$1/toggle_wifi.sh" && grep -q "^exec /usr/local/bin/toggle_bt.sh \"\$@\"$" "$1/toggle_bt.sh" && bash -n "$1/toggle_wifi.sh"' _ "$R6/usr/local/sbin"
expect "--layout-status: universal"           test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --layout-status)" = "universal"
expect "--layout-report: every file universal, retrorun missing (dArkOSen's own build)" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --layout-report | awk '$1 != "retrorun" {print $2}' | sort -u | tr '\n' ' ')" = "universal " -a "$(SHORTCUTS_ROOT="$R6" bash "$SC" --layout-report | awk '$1 == "retrorun" {print $2}')" = "missing"
expect "--layout darkosen exits 0"            bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout darkosen | grep -q "applied to 10 file"' _ "$SC" "$R6"
for f in home/ark/.config/retroarch/retroarch.cfg home/ark/.config/retroarch32/retroarch.cfg home/ark/.config/mupen64plus/mupen64plus.cfg \
         home/ark/.local/share/duckstation/settings.ini opt/ppsspp/backupforromsfolder/ppsspp/PSP/SYSTEM/controls.ini roms/psp/ppsspp/PSP/SYSTEM/controls.ini \
         "home/ark/.config/flycast/mappings/SDL_GO-Super Gamepad.cfg" opt/drastic/config/drastic.cfg opt/inttools/gamecontrollerdb.txt home/ark/.config/retrorun.cfg; do
expect "back to dArkOSen's, byte for byte: $(basename "$f")" cmp -s "$R6/$f" "$RL/$f"
done
expect "ogage wrappers removed"               test ! -e "$R6/usr/local/sbin/toggle_wifi.sh" -a ! -e "$R6/usr/local/sbin/toggle_bt.sh"
expect "--layout-status: darkosen"            test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --layout-status)" = "darkosen"
expect "settings follow (reminder and delay kept)" test "$(tr '\n' ' ' < "$R6/home/ark/.config/shortcuts.conf")" = "REMINDER=0 DELAY=4 LAYOUT=darkosen "
expect "pages follow: retroarch.darkosen.txt (the exported copy)" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --page retroarch)" = "$R6/roms/shortcuts/retroarch.darkosen.txt"
rm -f "$R6/roms/shortcuts/retroarch.darkosen.txt"
expect "pages follow: without it, your retroarch.txt wins over the built-in variant" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --page retroarch)" = "$R6/roms/shortcuts/retroarch.txt"
rm -f "$R6/roms/shortcuts/retroarch.txt"
expect "pages follow: the built-in variant when both are gone" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --page retroarch)" = "$R6/usr/share/dArkOSen-Extended/shortcuts/retroarch.darkosen.txt"
rm -f "$R6/roms/shortcuts/n64.darkosen.txt"
expect "pages follow: n64 edited by the user wins over the built-in variant" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --page n64)" = "$R6/roms/shortcuts/n64.txt"
expect "pages follow: retrorun.darkosen.txt (the exported copy)" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --page retrorun)" = "$R6/roms/shortcuts/retrorun.darkosen.txt"
sed -i 's/^input_reset_btn = .*/input_reset_btn = "5"/' "$RC6/retroarch32/retroarch.cfg"      # changed by hand in RetroArch
expect "--layout-status: mixed after a manual change" test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --layout-status)" = "mixed"
expect "--layout universal again exits 0"      env SHORTCUTS_ROOT="$R6" bash "$SC" --layout universal
expect "--layout-status: universal again"      test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --layout-status)" = "universal"
expect "pages follow: retroarch.txt"           test "$(SHORTCUTS_ROOT="$R6" bash "$SC" --page retroarch)" = "$R6/usr/share/dArkOSen-Extended/shortcuts/retroarch.txt"
expect "unknown layout refused"                bash -c '! SHORTCUTS_ROOT="$2" bash "$1" --layout foo 2>/dev/null' _ "$SC" "$R6"
RE="$T/layout-empty"; mkdir -p "$RE/home/ark/.config"; printf 'REMINDER=1\nDELAY=10\nLAYOUT=universal\n' > "$RE/home/ark/.config/shortcuts.conf"
expect "no configuration file at all: nothing applied, exits 0" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout darkosen | grep -q "not applied"' _ "$SC" "$RE"
expect "--layout-status: missing"              test "$(SHORTCUTS_ROOT="$RE" bash "$SC" --layout-status)" = "missing"
expect "settings unchanged then"               grep -qx 'LAYOUT=universal' "$RE/home/ark/.config/shortcuts.conf"
RX="$T/layout-x"; make_root "$RX"; ppsspp_roms "$RX"
expect "a key missing from a file is added, once" bash -c 'sed -i "/^input_pause_toggle_btn/d" "$2/home/ark/.config/retroarch/retroarch.cfg" && sed -i "/^Pause = /d" "$2/roms/psp/ppsspp/PSP/SYSTEM/controls.ini" && SHORTCUTS_ROOT="$2" bash "$1" --layout universal >/dev/null && test "$(grep -c "^input_pause_toggle_btn = \"3\"" "$2/home/ark/.config/retroarch/retroarch.cfg")" = 1 && test "$(grep -c "^Pause = 1-111,10-4" "$2/roms/psp/ppsspp/PSP/SYSTEM/controls.ini")" = 1' _ "$SC" "$RX"
# --repair (self-repair service, at boot): files put back to dArkOSen's exact values by an
# update or a first boot get the universal layout again; files changed by hand are left alone
RM="$T/layout-m"; make_root "$RM"; ppsspp_roms "$RM"
expect "fresh root, layout darkosen: --repair changes nothing" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --repair >/dev/null && test "$(SHORTCUTS_ROOT="$2" bash "$1" --layout-status)" = darkosen' _ "$SC" "$RM"
env SHORTCUTS_ROOT="$RM" bash "$SC" --layout universal >/dev/null
cp "$RL/roms/psp/ppsspp/PSP/SYSTEM/controls.ini" "$RM/roms/psp/ppsspp/PSP/SYSTEM/controls.ini"       # the first boot extracted the user's old copy
cp "$RL/opt/inttools/gamecontrollerdb.txt" "$RM/opt/inttools/gamecontrollerdb.txt"                       # an OTA update replaced the database
sed -i 's/^input_reset_btn = .*/input_reset_btn = "5"/' "$RM/home/ark/.config/retroarch32/retroarch.cfg"   # changed by hand in RetroArch
expect "--repair re-applies the layout to the two pristine files" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --repair | grep -q "re-applied to 2 file"' _ "$SC" "$RM"
expect "PPSSPP copy next to the roms: universal again" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout-report | grep -q "^ppsspp-roms  universal"' _ "$SC" "$RM"
expect "controller database: universal again"  bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout-report | grep -q "^gcdb         universal"' _ "$SC" "$RM"
expect "the hand-changed retroarch32 file is left alone (mixed)" bash -c 'grep -qx "input_reset_btn = \"5\"" "$2/home/ark/.config/retroarch32/retroarch.cfg" && SHORTCUTS_ROOT="$2" bash "$1" --layout-report | grep -q "^ra32         mixed"' _ "$SC" "$RM"
expect "a second --repair changes nothing"     bash -c '! SHORTCUTS_ROOT="$2" bash "$1" --repair | grep -q "re-applied"' _ "$SC" "$RM"
# retrorun: dArkOSen's own build ignores retrorun_hotkey_*; the hotkeys build (components/retrorun_hotkeys,
# installed by its device-install.sh) is recognised by that string, then the layout and the page follow
RR="$T/layout-rr"; make_root "$RR"; RRC="$RR/home/ark/.config/retrorun.cfg"; RRT="$RR/usr/share/dArkOSen-Extended/shortcuts"
mkdir -p "$RRT"; cp "$STX"/*.txt "$RRT/"
expect "dArkOSen's retrorun: component missing, nothing written, dArkOSen's page even in the universal layout" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout universal | grep -q "retrorun: hotkeys build not installed, skipped" && SHORTCUTS_ROOT="$2" bash "$1" --layout-report | grep -q "^retrorun     missing" && cmp -s "$3" "$4" && test "$(SHORTCUTS_ROOT="$2" bash "$1" --page retrorun)" = "$5/retrorun.darkosen.txt"' _ "$SC" "$RR" "$RRC" "$RL/home/ark/.config/retrorun.cfg" "$RRT"
printf 'stub\nretrorun_hotkey_menu\n' > "$RR/usr/local/bin/retrorun"; cp "$RR/usr/local/bin/retrorun" "$RR/usr/local/bin/retrorun32"
expect "hotkeys build installed: --repair appends the four lines (FN menu, R2/L2 slots, L3 fast-forward)" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --repair | grep -q "re-applied to 1 file" && test "$(grep "^retrorun_hotkey" "$3" | tr "\n" "|")" = "retrorun_hotkey_menu = F5|retrorun_hotkey_slot_next = TriggerRight|retrorun_hotkey_slot_prev = TriggerLeft|retrorun_hotkey_fast_forward = F3|" && test "$(head -6 "$3")" = "$(head -6 "$4")" && test "$(wc -l < "$3")" = 10' _ "$SC" "$RR" "$RRC" "$RL/home/ark/.config/retrorun.cfg"
expect "--layout-report: retrorun universal, page = the universal keys" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout-report | grep -q "^retrorun     universal" && test "$(SHORTCUTS_ROOT="$2" bash "$1" --page retrorun)" = "$3/retrorun.txt"' _ "$SC" "$RR" "$RRT"
expect "--layout darkosen: 10 files (no PPSSPP copy next to the roms here), retrorun.cfg back byte for byte" bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout darkosen | grep -q "applied to 10 file" && cmp -s "$3" "$4"' _ "$SC" "$RR" "$RRC" "$RL/home/ark/.config/retrorun.cfg"
expect "--layout universal: 10 files, lines back"  bash -c 'SHORTCUTS_ROOT="$2" bash "$1" --layout universal | grep -q "applied to 10 file" && test "$(grep -c "^retrorun_hotkey" "$3")" = 4' _ "$SC" "$RR" "$RRC"
# inject.sh --retrorun-hotkeys (local builds): the binaries go in at build time, the layout step then writes the lines
RI="$T/inject-rr"; make_root "$RI"; RIB="$T/rrbin"; mkdir -p "$RIB" "$RIB-bad"
printf 'hotkeys retrorun\nretrorun_hotkey_menu\n' > "$RIB/retrorun"; printf 'hotkeys retrorun32\nretrorun_hotkey_menu\n' > "$RIB/retrorun32"
printf 'stock\n' > "$RIB-bad/retrorun"; cp "$RIB/retrorun32" "$RIB-bad/"
chown 1000:1000 "$RI/usr/local/bin/retrorun" "$RI/usr/local/bin/retrorun32" 2>/dev/null || true
expect "inject.sh refuses a binary without the hotkeys string" bash -c '! bash "$1" "$2" "" 10152026 "" "$3" >/dev/null 2>&1' _ "$INJECT" "$RI" "$RIB-bad"
expect "inject.sh with the hotkeys build exits 0"  bash "$INJECT" "$RI" "" 10152026 "" "$RIB"
expect "binaries installed (755, owner kept), dArkOSen's kept as .darkosen" bash -c 'grep -q retrorun_hotkey_menu "$1/retrorun" && grep -q retrorun_hotkey_menu "$1/retrorun32" && test "$(stat -c %a "$1/retrorun")" = 755 && test "$(stat -c %u "$1/retrorun")" = "$(stat -c %u "$1/retrorun.darkosen")" && grep -q "stock retrorun 3.0.0" "$1/retrorun.darkosen" && grep -q "stock retrorun32" "$1/retrorun32.darkosen"' _ "$RI/usr/local/bin"
expect "default config path linked to retrorun.cfg" test "$(readlink "$RI/storage/.config/distribution/configs/retrorun.cfg")" = "/home/ark/.config/retrorun.cfg"
expect "retrorun.cfg got the four lines, layout universal everywhere (no PPSSPP copy next to the roms)" bash -c 'test "$(grep -c "^retrorun_hotkey" "$2/home/ark/.config/retrorun.cfg")" = 4 && SHORTCUTS_ROOT="$2" bash "$1" --layout-report | grep -q "^retrorun     universal" && test "$(SHORTCUTS_ROOT="$2" bash "$1" --layout-status)" = universal' _ "$SC" "$RI"
expect "build stamp counts the binaries"       grep -qx 'DARKOSEN_EXTENDED_RETRORUN_HOTKEYS=2' "$RI/etc/dArkOSen-Extended.release"
expect "a second inject keeps the .darkosen copies" bash -c 'bash "$1" "$2" "" 10152026 "" "$3" >/dev/null && grep -q "stock retrorun 3.0.0" "$2/usr/local/bin/retrorun.darkosen"' _ "$INJECT" "$RI" "$RIB"
expect "without the option nothing of this happens" bash -c '! test -e "$1/storage" && grep -qx "DARKOSEN_EXTENDED_RETRORUN_HOTKEYS=0" "$1/etc/dArkOSen-Extended.release"' _ "$R6"
# which page for which launch (the command line EmulationStation runs is given instead of read from /proc)
SD="$T/sc"; mkdir -p "$SD/user" "$SD/bin" "$SD/real"
echo 'echo "VAR=PPSSPPSDL" > /home/ark/.config/KILLIT' > "$SD/bin/ppsspp.sh"; echo ': no exit daemon' > "$SD/bin/n64.sh"
echo 'echo "VAR=scummvm" > /home/ark/.config/KILLIT' > "$SD/bin/scummvm.sh"
printf 'REMINDER=1\nDELAY=0\nLAYOUT=universal\n' > "$SD/uni.conf"       # as on a built image
W() { LAUNCH_CMD="$1" SHORTCUTS_DIRS="$SD/user $STX" SHORTCUTS_BIN="$SD/bin" SHORTCUTS_CONF="$SD/uni.conf" bash "$LR" --which | sed 's/.* -> //; s|.*/||'; }
expect "RetroArch launched directly"          test "$(W 'sudo perfmax ondemand /roms/snes/a.sfc; nice -n -19 /usr/local/bin/retroarch -L /home/ark/.config/retroarch/cores/snes9x_libretro.so /roms/snes/a.sfc; sudo perfnorm')" = "retroarch.txt"
expect "retroarch32 through n64.sh"           test "$(W 'sudo perfmax ondemand /roms/n64/a.n64; nice -n -19 /usr/local/bin/n64.sh retroarch32 parallel_n64 /roms/n64/a.n64; sudo perfnorm')" = "retroarch.txt"
DC_CMD='sudo perfmax ondemand /roms/dreamcast/a.cdi; nice -n -19 /usr/local/bin/dreamcast.sh retrorun32 flycast32_rumble /roms/dreamcast/a.cdi; sudo perfnorm'
expect "retrorun32 through dreamcast.sh, dArkOSen's build: its own keys even in the universal layout" test "$(W "$DC_CMD")" = "retrorun.darkosen.txt"
printf 'stub\nretrorun_hotkey_menu\n' > "$SD/bin/retrorun32"
expect "retrorun32, the hotkeys build installed: the universal page" test "$(W "$DC_CMD")" = "retrorun.txt"
expect "standalone-Rice through n64.sh"       test "$(W 'sudo perfmax ondemand /roms/n64/a.n64; nice -n -19 /usr/local/bin/n64.sh standalone-Rice Default_Aspect /roms/n64/a.n64; sudo perfnorm')" = "n64.txt"
expect "rom name with spaces and brackets"    test "$(W 'sudo perfmax ondemand /roms/n64/Super\ Mario\ 64\ \(Europe\).n64; nice -n -19 /usr/local/bin/n64.sh standalone-Glide64mk2 Default_Aspect /roms/n64/Super\ Mario\ 64\ \(Europe\).n64; sudo perfnorm')" = "n64.txt"
expect "retrorun32 through dreamcast.sh"      test "$(W 'sudo perfmax ondemand /roms/dreamcast/a.chd; nice -n -19 /usr/local/bin/dreamcast.sh retrorun32 flycast /roms/dreamcast/a.chd; sudo perfnorm')" = "retrorun.txt"
expect "PPSSPP standalone: its own page"      test "$(W 'sudo perfmax ondemand /roms/psp/a.iso; nice -n -19 /usr/local/bin/ppsspp.sh standalone /roms/psp/a.iso; sudo perfnorm')" = "ppsspp.txt"
expect "PPSSPP 2021: the page of that build"  test "$(W 'sudo perfmax ondemand /roms/psp/a.iso; nice -n -19 /usr/local/bin/ppsspp.sh standalone-2021 /roms/psp/a.iso; sudo perfnorm')" = "ppsspp.standalone-2021.txt"
expect "ScummVM standalone (exit daemon): generic page" test "$(W 'sudo perfmax ondemand /roms/scummvm/a.svm; nice -n -19 /usr/local/bin/scummvm.sh /roms/scummvm/a.svm; sudo perfnorm')" = "standalone.txt"
expect "Flycast standalone through dreamcast.sh" test "$(W 'sudo perfmax ondemand /roms/dreamcast/a.chd; nice -n -19 /usr/local/bin/dreamcast.sh standalone-Flycast /roms/dreamcast/a.chd; sudo perfnorm')" = "dreamcast.standalone-Flycast.txt"
expect "DraStic through drastic.sh"           test "$(W 'sudo perfmax ondemand /roms/nds/a.nds; nice -n -19 /usr/local/bin/drastic.sh drastic /roms/nds/a.nds; sudo perfnorm')" = "drastic.drastic.txt"
expect "Yabasanshiro through saturn.sh"       test "$(W 'sudo perfmax ondemand /roms/saturn/a.chd; nice -n -19 /usr/local/bin/saturn.sh yabasanshiro-pirry-nobios x /roms/saturn/a.chd; sudo perfnorm')" = "saturn.txt"
expect "a port: no page, no reminder"         test "$(W 'sudo perfmax ondemand /roms/ports/Game.sh; /roms/ports/Game.sh; sudo perfnorm')" = "none"
printf 'MY RICE PAGE\n' > "$SD/user/n64.standalone-Rice.txt"
expect "your own page for one emulator wins"  test "$(W 'sudo perfmax ondemand /roms/n64/a.n64; nice -n -19 /usr/local/bin/n64.sh standalone-Rice Default_Aspect /roms/n64/a.n64; sudo perfnorm')" = "n64.standalone-Rice.txt"
# the real thing: no hint, the helper finds the launching shell among its ancestors
printf '#!/bin/bash\nSHORTCUTS_DIRS="%s" SHORTCUTS_BIN="%s" SHORTCUTS_CONF=/nonexistent bash "%s" --which\n' "$STX" "$SD/bin" "$LR" > "$SD/real/perfmax"
printf '#!/bin/bash\nexit 0\n' > "$SD/real/n64.sh"; chmod 755 "$SD/real/perfmax" "$SD/real/n64.sh"
expect "emulator read from the launching shell (no settings file: dArkOSen's page)" bash -c 'test "$(sh -c "$1/perfmax ondemand /roms/n64/a.n64; nice -n -19 $1/n64.sh standalone-Rice Default_Aspect /roms/n64/a.n64; true" | sed "s/.* -> //; s|.*/||")" = "n64.darkosen.txt"' _ "$SD/real"
# what gets printed (stdin is not a terminal there either: over SSH, on a pts, the helper stays quiet)
RA_CMD='sudo perfmax ondemand /roms/snes/a.sfc; nice -n -19 /usr/local/bin/retroarch -L x /roms/snes/a.sfc; sudo perfnorm'
printf 'REMINDER=1\nDELAY=0\n' > "$SD/on.conf"; printf 'REMINDER=0\nDELAY=0\n' > "$SD/off.conf"; : > "$SD/tty"
expect "reminder printed on the console"      bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null && grep -q "RETROARCH" "$5" && grep -q "START ........ quit the game" "$5"' _ "$LR" "$RA_CMD" "$STX" "$SD/on.conf" "$SD/tty"
expect "notes (# lines) are not printed"      bash -c '! grep -q "retroarch.cfg" "$1"' _ "$SD/tty"
expect "no LAYOUT in the settings: dArkOSen's page (its files are untouched)" grep -q "dArkOSen keys" "$SD/tty"
expect "A, B, X, Y in the colours of the R36S" bash -c 'grep -q "$(printf " \033\[1;33mB\033\[0m / \033\[1;31mA\033\[0m ........ save / load state")" "$1" && grep -q "$(printf " \033\[1;34mX\033\[0m / \033\[1;32mY\033\[0m ........ next / previous slot")" "$1" && grep -q " R2 / L3 ...... reset / screenshot" "$1"' _ "$SD/tty"
expect "UP, DOWN, LEFT, RIGHT as arrows, columns kept" bash -c 'grep -q "$(printf " \342\206\221  ........... frame advance")" "$1" && grep -q "$(printf " \342\206\223    ......... fast-forward (hold)")" "$1" && grep -q "$(printf " \342\206\220    ......... rewind")" "$1" && grep -q "$(printf " \342\206\222     ........ fast-forward on/off")" "$1"' _ "$SD/tty"
expect "the title keeps its own colour, no word changed inside" bash -c 'grep -q "$(printf "\033\[1;33mRETROARCH (dArkOSen keys)\033\[0m")" "$1" && grep -q "Menu: FN, or hold SELECT 2 seconds" "$1"' _ "$SD/tty"
: > "$SD/tty"
expect "universal layout: the universal page"  bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null && grep -q "$(printf "\033\[1;33mRETROARCH\033\[0m")" "$5" && ! grep -q "dArkOSen keys" "$5" && grep -q "FN ............ menu" "$5" && grep -q " R1 / L1 ...... save / load state" "$5"' _ "$LR" "$RA_CMD" "$STX" "$SD/uni.conf" "$SD/tty"
printf 'A TITLE\nA/B/X/Y and A/B, SELECT + A.\nGAME over, X-Y, UPDOWN, no UP.\n' > "$SD/user/n64.txt"
expect "--which: the .darkosen variant only in that layout" bash -c 'test "$(LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" bash "$1" --which | sed "s/.* -> //; s|.*/||")" = "retroarch.darkosen.txt" && test "$(LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$5" bash "$1" --which | sed "s/.* -> //; s|.*/||")" = "retroarch.txt"' _ "$LR" "$RA_CMD" "$STX" "$SD/on.conf" "$SD/uni.conf"
: > "$SD/tty"
expect "whole words only: A/B/X/Y all coloured, GAME, X-Y, UPDOWN untouched" bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null && grep -q "$(printf " \033\[1;31mA\033\[0m/\033\[1;33mB\033\[0m/\033\[1;34mX\033\[0m/\033\[1;32mY\033\[0m and \033\[1;31mA\033\[0m/\033\[1;33mB\033\[0m, SELECT + \033\[1;31mA\033\[0m.")" "$5" && grep -q "$(printf " GAME over, \033\[1;34mX\033\[0m-\033\[1;32mY\033\[0m, UPDOWN, no \342\206\221 .")" "$5"' _ "$LR" 'sudo perfmax ondemand /roms/n64/a.n64; nice -n -19 /usr/local/bin/n64.sh standalone-Glide64mk2 Default_Aspect /roms/n64/a.n64; sudo perfnorm' "$SD/user $STX" "$SD/on.conf" "$SD/tty"
rm -f "$SD/user/n64.txt"
printf '\xef\xbb\xbfMY TITLE\r\n# note\r\nSELECT + B ... quit\r\n' > "$SD/user/retroarch.txt"; : > "$SD/tty"   # saved by Windows Notepad
expect "a page edited on Windows prints cleanly" bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null && grep -q "MY TITLE" "$5" && grep -q "$(printf "SELECT + \033\[1;33mB\033\[0m ... quit")" "$5" && ! grep -q "note" "$5" && ! grep -q "$(printf "\r")" "$5" && ! grep -q "$(printf "\357\273\277")" "$5"' _ "$LR" "$RA_CMD" "$SD/user $STX" "$SD/on.conf" "$SD/tty"
: > "$SD/tty"
expect "nothing printed when the reminder is off" bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null && test ! -s "$5"' _ "$LR" "$RA_CMD" "$STX" "$SD/off.conf" "$SD/tty"
: > "$SD/tty"
expect "no prompt when the time is 0"         bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null && grep -q RETROARCH "$5" && ! grep -q "Press A" "$5"' _ "$LR" "$RA_CMD" "$STX" "$SD/on.conf" "$SD/tty"
expect "10 s and dArkOSen's pages by default"  grep -qx 'REMINDER=1; DELAY=10; LAYOUT=darkosen' "$LR"
printf 'REMINDER=1\nDELAY=1\n' > "$SD/wait.conf"; mkdir -p "$SD/long"; : > "$SD/tty"
{ echo "LONG PAGE"; for i in $(seq 1 20); do echo "line $i"; done; } > "$SD/long/retroarch.txt"
t0=$(date +%s%N)
expect "the prompt is printed when it waits"  bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" SHORTCUTS_PYTHON=/nonexistent/python3 bash "$1" < /dev/null && grep -q "$(printf "Press \033\[1;31mA\033\[1;36m to continue")" "$5"' _ "$LR" "$RA_CMD" "$SD/long" "$SD/wait.conf" "$SD/tty"
expect "without python it waits the whole time" test $(( ($(date +%s%N) - t0) / 1000000 )) -ge 1000
expect "the title and 11 lines, then the prompt" bash -c 'grep -q "line 11" "$1" && ! grep -q "line 12" "$1"' _ "$SD/tty"
if command -v python3 >/dev/null; then       # no game pad here: the button wait must fall back to the full time
    t0=$(date +%s%N)
    bash -c 'LAUNCH_CMD="$2" SHORTCUTS_DIRS="$3" SHORTCUTS_CONF="$4" SHORTCUTS_TTY="$5" bash "$1" < /dev/null' _ "$LR" "$RA_CMD" "$SD/long" "$SD/wait.conf" "$SD/tty"
    expect "with python but no pad it waits the whole time" test $(( ($(date +%s%N) - t0) / 1000000 )) -ge 1000
fi

echo "== which videos play: all / none / list / playlist"
RP="$T/rootpl"; make_root "$RP"; bash "$TOOL" --install-root "$RP" >/dev/null
BV="$RP/roms/bootvideos"
for v in "Sega Logo.mp4" "PS1.MP4" "Intro & co.mkv"; do echo x > "$BV/$v"; done
echo x > "$BV/disabled/Old one.webm"
on()  { (cd "$BV" && find . -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.gif' \) -printf '%f\n' | sort -f | tr '\n' '|'); }
off() { (cd "$BV/disabled" && find . -maxdepth 1 -type f -printf '%f\n' | sort -f | tr '\n' '|'); }
OUTP=$(env BOOTVIDEO_ROOT="$RP" bash "$TOOL" --select none 2>&1)
expect "--select none: no video plays"        test -z "$(on)" -a "$(off)" = "Intro & co.mkv|Old one.webm|PS1.MP4|Sega Logo.mp4|"
expect "and says so"                          grep -q '^0 video(s) play at boot (3 moved)' <<<"$OUTP"
expect "--select all: every video plays"      bash -c 'env BOOTVIDEO_ROOT="$2" bash "$1" --select all >/dev/null' _ "$TOOL" "$RP"
expect "all four at the top, disabled/ empty" test "$(on)" = "Intro & co.mkv|Old one.webm|PS1.MP4|Sega Logo.mp4|" -a -z "$(off)"
printf 'Sega Logo.mp4\r\nps1.mp4\r\n# a note\r\n\r\nGone.mp4\r\n' > "$T/list.txt"            # saved by Windows Notepad
sed -i 's/^MODE=.*/MODE=single/; s/^FILE=.*/FILE="Intro \& co.mkv"/' "$RP/home/ark/.config/bootvideo.conf"
OUTP=$(env BOOTVIDEO_ROOT="$RP" bash "$TOOL" --select-list "$T/list.txt" 2>&1)
expect "--select-list: exactly the listed videos play" test "$(on)" = "PS1.MP4|Sega Logo.mp4|" -a "$(off)" = "Intro & co.mkv|Old one.webm|"
expect "names match without case, notes skipped" grep -q '^2 video(s) play at boot' <<<"$OUTP"
expect "a listed video that is gone is reported" grep -q '^1 listed video(s) not found' <<<"$OUTP"
expect "fixed video no longer ticked: back to random" grep -qx 'MODE=random' "$RP/home/ark/.config/bootvideo.conf"
mkdir -p "$BV/.playlists"; printf 'Old one.webm\n' > "$BV/.playlists/Retro.txt"
expect "--playlist NAME applies a saved playlist" bash -c 'env BOOTVIDEO_ROOT="$2" bash "$1" --playlist Retro >/dev/null' _ "$TOOL" "$RP"
expect "only that playlist's video plays"     test "$(on)" = "Old one.webm|"
expect "an unknown playlist fails"            bash -c '! env BOOTVIDEO_ROOT="$2" bash "$1" --playlist Nope 2>/dev/null' _ "$TOOL" "$RP"
echo x > "$BV/Old one.webm.dup"; echo x > "$BV/disabled/PS1.MP4.keep"
expect "files that are not videos are left alone" test -f "$BV/Old one.webm.dup" -a -f "$BV/disabled/PS1.MP4.keep"
echo x > "$BV/disabled/Old one.webm"                                  # same name in both folders
OUTP=$(env BOOTVIDEO_ROOT="$RP" bash "$TOOL" --select none 2>&1)
expect "a name in both folders is not overwritten" grep -q 'left alone: same name in both folders' <<<"$OUTP"
expect "both copies still there"              test -f "$BV/Old one.webm" -a -f "$BV/disabled/Old one.webm"
expect "X ticks in the menus (mapped to Space)" grep -q "sed -i 's/^x = .\*/x = space/' \"\$TMP_KEYS\"" "$TOOL"

echo "== helper --rebuild (gamelist + thumbnails)"
if command -v ffmpeg >/dev/null; then
    V="$T/vdir"; mkdir -p "$V/disabled"
    cp "$T/vids/Intro & Logo.mp4" "$V/"; cp "$T/vids/second.mp4" "$V/"
    cp "$T/vids/second.mp4" "$V/disabled/old one.mp4"
    printf 'ENABLED=1\nDIR="%s"\n' "$V" > "$T/test.conf"
    expect "--rebuild exits 0" env BOOTVIDEO_CONF="$T/test.conf" bash "$HELPER" --rebuild
    GL="$V/gamelist.xml"
    expect "gamelist.xml is valid XML"        xml_ok "$GL"
    expect "3 games listed"                   test "$(python3 -I -c 'import sys,xml.etree.ElementTree as E; print(len(E.parse(sys.argv[1]).getroot().findall("game")))' "$GL")" = "3"
    expect "ampersand escaped in name"        grep -q '<name>Intro &amp; Logo</name>' "$GL"
    expect "disabled video marked [OFF]"      grep -q '<name>old one \[OFF\]</name>' "$GL"
    expect "disabled folder entry present"    grep -q '<path>./disabled</path>' "$GL"
    expect "3 thumbnails generated"           test "$(ls "$V/.media/"*.png | wc -l)" = "3"
    expect "video preview paths relative"     grep -q '<video>./second.mp4</video>' "$GL"
else
    echo "  skip (ffmpeg not installed)"
fi

echo "== skip watcher (python) compiles"
sed -n "/<<'PY' &/,/^PY$/p" "$HELPER" | sed '1d;$d' > "$T/watcher.py"
expect "watcher extracted"                    test -s "$T/watcher.py"
expect "python3 compiles the watcher"         python3 -I -m py_compile "$T/watcher.py"

echo "== uninstall"
expect "--uninstall-root exits 0" bash "$TOOL" --uninstall-root "$R"
expect "hook removed"                         test "$(grep -c '# bootvideo-hook' "$ES")" = "0"
expect "ES script byte-identical to original" cmp -s "$T/es.orig" "$ES"
expect "ES entry removed"                     test "$(count_systems "$CFG" bootvideos)" = "0"
expect "es_systems.cfg byte-identical"        cmp -s "$T/cfg.orig" "$CFG"
expect "helper removed"                       test ! -e "$HELPER"
expect "config removed"                       test ! -e "$CONF"
expect "service unit removed"                 test ! -e "$UNIT"
expect "wants symlink removed"                test ! -e "$WANTS"
expect "repair wrapper removed"               test ! -e "$R/usr/local/bin/bootvideo-repair"
expect "backups removed"                      test ! -e "$ES.pre-bootvideo" -a ! -e "$CFG.pre-bootvideo"
expect "videos folder kept"                   test -d "$R/roms/bootvideos"

echo
echo "passed: $PASS  failed: $FAILED"
[ "$FAILED" -eq 0 ]
