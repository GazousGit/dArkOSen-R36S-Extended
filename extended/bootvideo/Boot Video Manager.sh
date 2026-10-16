#!/bin/bash

# =======================================================
# Boot Video Manager for dArkOSen  (v3)
# part of dArkOSen-R36S-Extended
# https://github.com/GazousGit/dArkOSen-R36S-Extended
#
# - Plays a video from <roms>/bootvideos right before
#   EmulationStation starts (random or a chosen one).
# - A / B / X / Y / Start skips it. Volume keys and Fn
#   combos keep working (handled by ogage) and never skip.
# - Adds a "Boot Videos" system to EmulationStation:
#   video previews in the list (like scraped videos), and
#   pressing A on a video opens Preview / Enable / Disable.
#   Disabled videos live in the "disabled" sub-folder.
# - Installs a tiny boot-time service that re-attaches
#   everything after an OTA update (self-repair).
#
# Install on a device: copy to /opt/system/System/ and run
# it once from Options > System.
#
# Command line:
#   (none)                interactive menu
#   --repair              non-interactive repair; used by the
#                         bootvideo-repair service at every boot
#   --install-root DIR    offline install into a mounted image
#                         root (used by the image build)
#   --uninstall-root DIR  offline uninstall (tests)
#   --select all|none     every video plays / none does
#   --select-list FILE    exactly the videos named in FILE
#                         (one file name per line) play
#   --playlist NAME       same, from a saved playlist
#
# Which videos play: the ones directly in <roms>/bootvideos;
# disabled/ holds the others. "Videos that play" in the menu
# ticks them (all, none, search, from the list) and saves
# playlists in bootvideos/.playlists/<name>.txt (one file
# name per line, editable on a PC); applying one moves the
# files so that exactly those videos play.
# Volume: option 4 sets the mixer level for every boot video;
# a single video can be louder or quieter than the others
# (A on it in EmulationStation, or option 4 > Per video),
# stored in bootvideos/.volumes.txt as "file name=percent"
# (10..300, applied as a software gain by ffplay).
# =======================================================
# MIT License - same terms as dArkOSen.

VERSION=3

Usage() {
    cat <<EOF
Boot Video Manager v$VERSION (dArkOSen Extended)
  $(basename "$0")                      interactive menu (run from EmulationStation)
  $(basename "$0") --repair             re-attach hook / ES entry / helper, no UI
  $(basename "$0") --install-root DIR   offline install into a mounted image root
  $(basename "$0") --uninstall-root DIR offline uninstall
  $(basename "$0") --select all|none    every video plays / no video plays
  $(basename "$0") --select-list FILE   exactly the videos named in FILE play
  $(basename "$0") --playlist NAME      exactly the videos of a saved playlist play
EOF
}

CLI=""
ROOT="${BOOTVIDEO_ROOT:-}"
case "${1:-}" in
    --repair)         CLI=repair ;;
    --install-root)   CLI=install;   ROOT="${2:?usage: --install-root DIR}" ;;
    --uninstall-root) CLI=uninstall; ROOT="${2:?usage: --uninstall-root DIR}" ;;
    --select)         CLI=select;     SEL_ARG="${2:?usage: --select all|none}" ;;
    --select-list)    CLI=selectlist; SEL_ARG="${2:?usage: --select-list FILE}" ;;
    --playlist)       CLI=playlist;   SEL_ARG="${2:?usage: --playlist NAME}" ;;
    --version)        echo "Boot Video Manager v$VERSION"; exit 0 ;;
    -h|--help)        Usage; exit 0 ;;
    "") ;;
    *)  echo "Unknown option: $1" >&2; Usage >&2; exit 1 ;;
esac
ROOT="${ROOT%/}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi
export TERM=linux

# ---- paths on the device (as the R36S sees them) ----
D_PLAYER="/usr/local/bin/bootvideo.sh"
D_REPAIR="/usr/local/bin/bootvideo-repair"
D_UNIT="/etc/systemd/system/bootvideo-repair.service"
D_WANTS="/etc/systemd/system/multi-user.target.wants/bootvideo-repair.service"
D_CONF="/home/ark/.config/bootvideo.conf"
D_ES_SH="/usr/bin/emulationstation/emulationstation.sh"
D_ES_CFG="/etc/emulationstation/es_systems.cfg"
D_TOOL="/opt/system/System/Boot Video Manager.sh"
D_SEED="/usr/share/dArkOSen-Extended/bootvideos"   # videos shipped inside a built image
D_OVERLAY="/usr/share/dArkOSen-Extended/overlay"   # extra tools shipped inside a built image
D_SHORTCUTS="/opt/system/Shortcuts.sh"             # one of them: owns a hook in perfmax
# ---- the same paths on this machine ($ROOT is empty on the device) ----
SEED="$ROOT$D_SEED"
PLAYER="$ROOT$D_PLAYER"
REPAIR="$ROOT$D_REPAIR"
UNIT="$ROOT$D_UNIT"
WANTS="$ROOT$D_WANTS"
CONF="$ROOT$D_CONF"
ES_SH="$ROOT$D_ES_SH"
ES_CFG="$ROOT$D_ES_CFG"
TOOL="$ROOT$D_TOOL"

HOOK_TAG="# bootvideo-hook"
HOOK_LINE="    [ -x $D_PLAYER ] && $D_PLAYER  $HOOK_TAG"
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
GPTOKEYB_PID=""
BACKTITLE="Boot Video Manager v$VERSION - dArkOSen Extended"

# Roms root: follow SD2 setups (Storage Settings rewrites the paths to /roms2)
if grep -q "<path>/roms2/" "$ES_CFG" 2>/dev/null && ! grep -q "<path>/roms/" "$ES_CFG"; then
    D_ROMS="/roms2"
else
    D_ROMS="/roms"
fi
D_VID_DIR="$D_ROMS/bootvideos"
VID_DIR="$ROOT$D_VID_DIR"

# user "ark", by number so this also works on a build machine
ARK_UID=$(awk -F: '$1=="ark"{print $3}' "$ROOT/etc/passwd" 2>/dev/null); ARK_UID=${ARK_UID:-1000}
ARK_GID=$(awk -F: '$1=="ark"{print $4}' "$ROOT/etc/passwd" 2>/dev/null); ARK_GID=${ARK_GID:-1000}
Own()  { chown    "$ARK_UID:$ARK_GID" "$@" 2>/dev/null; }
OwnR() { chown -R "$ARK_UID:$ARK_GID" "$@" 2>/dev/null; }
Log()  { echo "bootvideo: $*"; }

# =======================================================
# Helper script: boot playback, ES menu, preview, gamelist
# =======================================================
Write_Player() {
mkdir -p "$(dirname "$PLAYER")"
cat > "$PLAYER" <<'PLAYER_EOF'
#!/bin/bash
# dArkOSen boot video helper (written by Boot Video Manager)
#   bootvideo.sh              -> boot playback (once per boot)
#   bootvideo.sh --menu FILE  -> EmulationStation launch menu
#   bootvideo.sh --preview F  -> play one file now
#   bootvideo.sh --rebuild    -> thumbnails + gamelist.xml
#   bootvideo.sh --volume FILE [PERCENT] -> show / set the level of one video
CONF="${BOOTVIDEO_CONF:-/home/ark/.config/bootvideo.conf}"
DONE="/dev/shm/.bootvideo_done"
ENABLED=0; SOUND=1; VOLUME=0; MAXLEN=15; MODE=random; FILE=""; DIR=""
[ -f "$CONF" ] && . "$CONF"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  DIR=""
  for d in /roms/bootvideos /roms2/bootvideos; do [ -d "$d" ] && DIR="$d" && break; done
fi
EXTS=(mp4 mkv webm gif)
VOLS="$DIR/.volumes.txt"   # per-video level: one "file name=percent" per line, 100 = as is
VOL_LEVELS=(25 50 75 100 125 150 200 300)

video_volume() {   # $1 = file or name; prints its level in percent (100 when not set)
  local n line v=100
  n=$(basename "$1")
  [ -f "$VOLS" ] && while IFS= read -r line; do
    [ "${line%=*}" = "$n" ] && v="${line##*=}"
  done < "$VOLS"
  [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -ge 10 ] && [ "$v" -le 300 ] || v=100
  echo "$v"
}
set_video_volume() {   # $1 = file or name, $2 = percent (10..300; 100 removes the entry)
  local n line
  n=$(basename "$1")
  [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 10 ] && [ "$2" -le 300 ] || { echo "level must be 10..300" >&2; return 1; }
  { [ -f "$VOLS" ] && while IFS= read -r line; do
      [ -n "$line" ] && [ "${line%=*}" != "$n" ] && echo "$line"
    done < "$VOLS"
    [ "$2" = 100 ] || echo "$n=$2"
  } > "$VOLS.tmp" && mv "$VOLS.tmp" "$VOLS"
  chown ark:ark "$VOLS" 2>/dev/null || chown 1000:1000 "$VOLS" 2>/dev/null
}
gain_filter() {   # $1 = file; prints the ffplay -af value for its level, nothing at 100 %
  local v; v=$(video_volume "$1")
  [ "$v" = 100 ] || printf 'volume=%d.%02d' $(( v / 100 )) $(( v % 100 ))
}

list_videos() {   # $1 = folder, prints one path per line (top level only)
  local e f
  shopt -s nullglob nocaseglob
  for e in "${EXTS[@]}"; do for f in "$1"/*."$e"; do echo "$f"; done; done
  shopt -u nullglob nocaseglob
}

ensure_volume_keys() {
  # Volume keys are handled by ogage; make sure it is up before playback
  if ! pgrep -x ogage >/dev/null; then
    sudo systemctl start --no-block ogage 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x ogage >/dev/null && break; sleep 0.2; done
  fi
  # Apply "R36 Boot Volume" now, so the volume does not jump mid-video
  [ -f /usr/local/bin/boot_volume.sh ] && grep '^amixer' /usr/local/bin/boot_volume.sh | sudo bash 2>/dev/null
}

start_skip_watcher() {
  # Only A/B/X/Y/Start skip. Volume, Fn/hotkey, L/R, D-pad are ignored
  # so ogage combos (Fn+L/R volume, brightness...) do not stop the video.
  local joy
  joy=$(ls /dev/input/by-path/*joypad*event-joystick 2>/dev/null | head -1)
  [ -z "$joy" ] && return
  command -v python3 >/dev/null || return
  sudo python3 - "$joy" <<'PY' &
import os, sys, struct, select, time, subprocess
SKIP = {304, 305, 307, 308, 315, 705}  # B A X Y START(std) START(odroid joypad)
fmt = 'llHHi'; sz = struct.calcsize(fmt)
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK)
t0 = time.time()
while True:
    r, _, _ = select.select([fd], [], [], 1)
    if not r:
        if time.time() - t0 > 5 and subprocess.run(['pgrep', '-x', 'ffplay'], capture_output=True).returncode:
            break
        continue
    data = os.read(fd, sz * 64)
    for i in range(0, len(data) - sz + 1, sz):
        _, _, etype, code, val = struct.unpack(fmt, data[i:i + sz])
        if etype == 1 and val == 1 and code in SKIP and time.time() - t0 > 0.7:
            subprocess.run(['pkill', '-x', 'ffplay'])
            sys.exit(0)
PY
  WATCH=$!
}

PREV_VOL=""; VOL_CARD=0
set_volume() {   # $1 = percent; remembers the current mixer level so it can be restored
  VOL_CARD=$(aplay -l 2>/dev/null | grep -m1 -oP 'card \K[0-9]+(?=.*rk817)'); VOL_CARD=${VOL_CARD:-0}
  PREV_VOL=$(sudo amixer -c "$VOL_CARD" sget Playback 2>/dev/null | grep -m1 -oP '\[\K[0-9]+(?=%\])')
  sudo amixer -c "$VOL_CARD" -q sset Playback "$1%" 2>/dev/null
}
restore_volume() {
  [ -n "$PREV_VOL" ] && sudo amixer -c "$VOL_CARD" -q sset Playback "$PREV_VOL%" 2>/dev/null
  PREV_VOL=""
}

play() {   # $1 file, $2 max seconds, $3 sound 1/0
  local args=(-x 1280 -y 720 -loglevel quiet -autoexit -nostats -t "$2") gain
  [ "$3" = "1" ] || args+=(-an)
  # per-video level (bootvideos/.volumes.txt): software gain, so a quiet clip can go above 100 %
  gain=$(gain_filter "$1"); [ "$3" = "1" ] && [ -n "$gain" ] && args+=(-af "$gain")
  printf "\033c" > /dev/tty1 2>/dev/null
  ensure_volume_keys
  # Boot video volume (VOLUME=0 keeps the system level); the previous level comes back afterwards
  if [ "$3" = "1" ] && [ "${VOLUME:-0}" -gt 0 ] 2>/dev/null; then set_volume "$VOLUME"; fi
  WATCH=""; start_skip_watcher
  timeout $(( $2 + 5 )) ffplay "${args[@]}" "$1" >/dev/null 2>&1
  [ -n "$WATCH" ] && sudo kill "$WATCH" 2>/dev/null
  restore_volume
  printf "\033c" > /dev/tty1 2>/dev/null
}

xml() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

rebuild() {
  [ -n "$DIR" ] || exit 0
  mkdir -p "$DIR/disabled" "$DIR/.media"
  local out="$DIR/gamelist.xml" f rel name thumb sub lvl
  {
    echo '<?xml version="1.0"?>'
    echo '<gameList>'
    echo "  <folder><path>./disabled</path><name>$(echo "Disabled videos" | xml)</name><desc>Videos here are NOT played at boot. Open one and choose Enable.</desc></folder>"
    for sub in "" "disabled"; do
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="./${sub:+$sub/}$(basename "$f")"
        name=$(basename "${f%.*}"); name="${name%.r36}"
        thumb="$DIR/.media/${sub:+${sub}_}$(basename "${f%.*}").png"
        if [ ! -f "$thumb" ] && command -v ffmpeg >/dev/null; then
          ffmpeg -nostdin -hide_banner -loglevel error -y -ss 1 -i "$f" -frames:v 1 -vf scale=320:-2 "$thumb" 2>/dev/null
          # clips shorter than 1 s: ffmpeg exits 0 without writing a frame, so take the first frame instead
          [ -s "$thumb" ] || ffmpeg -nostdin -hide_banner -loglevel error -y -i "$f" -frames:v 1 -vf scale=320:-2 "$thumb" 2>/dev/null
        fi
        lvl=$(video_volume "$f"); [ "$lvl" = 100 ] && lvl="" || lvl=" Volume $lvl %."
        echo "  <game>"
        echo "    <path>$(echo "$rel" | xml)</path>"
        if [ -z "$sub" ]; then
          echo "    <name>$(echo "$name" | xml)</name>"
          echo "    <desc>ENABLED - can play at boot.$lvl Press A to preview, disable or set the volume.</desc>"
        else
          echo "    <name>$(echo "$name [OFF]" | xml)</name>"
          echo "    <desc>DISABLED - never plays at boot.$lvl Press A to preview, enable or set the volume.</desc>"
        fi
        [ -f "$thumb" ] && echo "    <image>$(echo "./.media/$(basename "$thumb")" | xml)</image>"
        echo "    <video>$(echo "$rel" | xml)</video>"
        echo "  </game>"
      done < <(list_videos "$DIR${sub:+/$sub}")
    done
    echo '</gameList>'
  } > "$out.tmp" && mv "$out.tmp" "$out"
  chown -R ark:ark "$DIR" 2>/dev/null
}

restart_es() {
  # Detached from ES: stop ES (lets it save), rebuild list, start again.
  # The boot video will not replay (once-per-boot marker).
  sudo systemd-run --no-block --quiet bash -c \
    "systemctl stop emulationstation; $0 --rebuild; systemctl start emulationstation"
}

es_menu() {
  local f="$1"
  [ -f "$f" ] || exit 0
  [ "$(id -u)" -ne 0 ] && exec sudo -- "$0" --menu "$f"
  local tty=/dev/tty1 keys=/tmp/keys.gptk.bv gp=""
  export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
  chmod 666 /dev/uinput
  cp /opt/inttools/keys.gptk "$keys"
  if grep -q 'name="InvertButtons" value="true"' /home/ark/.emulationstation/es_settings.cfg 2>/dev/null; then
    sed -i 's/^a = .*/a = esc/; s/^b = .*/b = enter/' "$keys"     # B confirms, like ES
  else
    sed -i 's/^a = .*/a = enter/; s/^b = .*/b = esc/' "$keys"     # A confirms, like ES
  fi
  start_gp() { /opt/inttools/gptokeyb -1 "$0" -c "$keys" >/dev/null 2>&1 & gp=$!; }
  stop_gp()  { [ -n "$gp" ] && kill "$gp" 2>/dev/null; gp=""; }
  local font; font=$(setfont -v 2>&1 | grep -o '/.*\.psf.*')
  setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null
  printf "\e[?25l\033[H\033[2J" > "$tty"
  start_gp
  local base state toggle c lvl l items
  while true; do
    base=$(basename "$f")
    if [ "$(basename "$(dirname "$f")")" = "disabled" ]; then state="DISABLED"; toggle="Enable (play at boot)"
    else state="ENABLED"; toggle="Disable (never play at boot)"; fi
    lvl=$(video_volume "$f")
    c=$(dialog --clear --no-collapse --cancel-label "Back" --backtitle "Boot Videos" \
        --title "$base" --menu "Status: $state | Volume: $lvl %" 13 52 3 \
        1 "Preview (with sound)" 2 "$toggle" 3 "Volume of this video ($lvl %)" 2>&1 > "$tty") || break
    case "$c" in
      1) stop_gp; play "$f" 120 1; start_gp ;;
      3) items=()
         for l in "${VOL_LEVELS[@]}"; do
           if [ "$l" = 100 ]; then items+=("$l" "100 % (as recorded)"); else items+=("$l" "$l %"); fi
         done
         l=$(dialog --clear --no-collapse --cancel-label "Back" --backtitle "Boot Videos" \
             --title "$base" --menu "Level of this video only, on top of the boot video volume.\nUse Preview to check it." 18 56 8 \
             "${items[@]}" 2>&1 > "$tty") || continue
         set_video_volume "$f" "$l" ;;
      2) if [ "$state" = "ENABLED" ]; then mkdir -p "$DIR/disabled"; mv "$f" "$DIR/disabled/" && f="$DIR/disabled/$base"
         else mv "$f" "$DIR/" && f="$DIR/$base"; fi
         chown ark:ark "$f"
         # if this was the single chosen video and it got disabled, go back to random
         if [ "$MODE" = "single" ] && [ "$FILE" = "$base" ] && [ "$state" = "ENABLED" ]; then
           sed -i 's/^MODE=.*/MODE=random/; s/^FILE=.*/FILE=""/' "$CONF"
         fi
         if dialog --clear --backtitle "Boot Videos" --yesno "Saved.\n\nRestart EmulationStation now to refresh the list?\n(otherwise it updates at next boot)" 10 52 > "$tty"; then
           stop_gp; printf "\033[H\033[2J" > "$tty"; restart_es; exit 0
         fi ;;
    esac
  done
  stop_gp; rm -f "$keys"
  printf "\033[H\033[2J\e[?25h" > "$tty"
  [ -n "$font" ] && setfont "$font"
  exit 0
}

case "$1" in
  --menu)    es_menu "$2" ;;
  --preview) play "$2" "${3:-120}" 1; exit 0 ;;
  --rebuild) rebuild; exit 0 ;;
  --volume)  [ -n "$DIR" ] && [ -n "$2" ] || { echo "usage: $0 --volume FILE [PERCENT]" >&2; exit 2; }
             if [ -n "$3" ]; then set_video_volume "$2" "$3" || exit 1; fi
             video_volume "$2"; exit 0 ;;
esac

# ---------------- boot playback ----------------
[[ "$(tty 2>/dev/null)" == *pts* ]] && exit 0   # not when ES is started over SSH
[ -e "$DONE" ] && exit 0                         # once per boot (not on ES restarts)
touch "$DONE" 2>/dev/null
[ "$ENABLED" = "1" ] || exit 0
[ -n "$DIR" ] || exit 0
mapfile -t vids < <(list_videos "$DIR")          # top level only = enabled videos
[ ${#vids[@]} -eq 0 ] && exit 0
if [ "$MODE" = "single" ] && [ -n "$FILE" ] && [ -f "$DIR/$FILE" ]; then
  VID="$DIR/$FILE"
else
  VID="${vids[$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % ${#vids[@]} ))]}"
fi
play "$VID" "$MAXLEN" "$SOUND"
exit 0
PLAYER_EOF
chmod 755 "$PLAYER"
}

# =======================================================
# Config
# =======================================================
Load_Conf() {
    ENABLED=0; SOUND=1; VOLUME=0; MAXLEN=15; MODE=random; FILE=""; ES_ENTRY=0
    [ -f "$CONF" ] && . "$CONF"
}
Save_Conf() {
    mkdir -p "$(dirname "$CONF")"
    cat > "$CONF" <<EOF
ENABLED=$ENABLED
SOUND=$SOUND
VOLUME=$VOLUME
MAXLEN=$MAXLEN
MODE=$MODE
FILE="$FILE"
DIR="$D_VID_DIR"
ES_ENTRY=$ES_ENTRY
EOF
    Own "$CONF"
}

# =======================================================
# Hook into emulationstation.sh (idempotent, with backup)
# =======================================================
Hook_Present() { grep -qF "$HOOK_TAG" "$ES_SH" 2>/dev/null; }
Install_Hook() {
    [ -f "$ES_SH" ] || return 1
    Hook_Present && return 0
    cp -p "$ES_SH" "$ES_SH.pre-bootvideo"          # backup of the pristine script
    local tmp="$ES_SH.bv.tmp"
    # anchor 1: right after esdir=... (normal boot branch, after the BaRT check)
    awk -v hook="$HOOK_LINE" '
        !done && index($0, "esdir=\"$(dirname $0)\"") { print; print hook; done=1; next }
        { print }
        END { exit done ? 0 : 3 }' "$ES_SH" > "$tmp" || rm -f "$tmp"
    # anchor 2: the start of the normal boot branch
    if [ ! -s "$tmp" ]; then
        awk -v hook="$HOOK_LINE" '
            !done && index($0, ".BOOT_TO_RETROARCH\" ]; then") { print; print hook; done=1; next }
            { print }
            END { exit done ? 0 : 3 }' "$ES_SH" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    cat "$tmp" > "$ES_SH" && rm -f "$tmp"          # keep inode, mode and owner
    Hook_Present
}
Remove_Hook() {
    Hook_Present || return 0
    local tmp="$ES_SH.bv.tmp"
    grep -vF "$HOOK_TAG" "$ES_SH" > "$tmp" && cat "$tmp" > "$ES_SH"
    rm -f "$tmp"
}

# =======================================================
# EmulationStation "Boot Videos" system
# =======================================================
ES_Entry_Present() { grep -q "<name>bootvideos</name>" "$ES_CFG" 2>/dev/null; }
Add_ES_Entry() {
    [ -f "$ES_CFG" ] || return 1
    ES_Entry_Present && return 0
    cp -p "$ES_CFG" "$ES_CFG.pre-bootvideo"
    local tmp="$ES_CFG.bv.tmp"
    awk -v vid="$D_VID_DIR" -v player="$D_PLAYER" '
        !done && /<\/systemList>/ {
            print "  <system>"
            print "    <name>bootvideos</name>"
            print "    <fullname>Boot Videos</fullname>"
            print "    <path>" vid "/</path>"
            print "    <extension>.mp4 .MP4 .mkv .MKV .webm .WEBM .gif .GIF</extension>"
            print "    <command>" player " --menu %ROM%</command>"
            print "    <platform>bootvideos</platform>"
            print "    <theme>videos</theme>"
            print "  </system>"
            done=1
        }
        { print }
        END { exit done ? 0 : 3 }' "$ES_CFG" > "$tmp" || { rm -f "$tmp"; return 1; }
    cat "$tmp" > "$ES_CFG" && rm -f "$tmp"
    ES_Entry_Present
}
Remove_ES_Entry() {
    ES_Entry_Present || return 0
    local tmp="$ES_CFG.bv.tmp"
    awk '
      /<system>/ { buf=$0; inb=1; next }
      inb { buf = buf "\n" $0
            if (/<\/system>/) { if (buf !~ /<name>bootvideos<\/name>/) print buf; inb=0 }
            next }
      { print }' "$ES_CFG" > "$tmp" && cat "$tmp" > "$ES_CFG"
    rm -f "$tmp"
}
Restart_ES() {
    systemd-run --no-block --quiet bash -c \
      "systemctl stop emulationstation; $PLAYER --rebuild; systemctl start emulationstation"
}

# =======================================================
# Self-repair service: runs before ES at every boot and
# re-attaches everything an OTA update may have replaced
# =======================================================
Service_Present() { [ -f "$UNIT" ] && [ -x "$REPAIR" ] && { [ -L "$WANTS" ] || [ -e "$WANTS" ]; }; }
Install_Service() {
    mkdir -p "$(dirname "$UNIT")" "$(dirname "$REPAIR")" "$(dirname "$WANTS")"
    local tmp changed=0
    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
#!/bin/bash
# dArkOSen Extended: re-attach the boot video after an OTA update (runs before ES)
for f in "/opt/system/System/Boot Video Manager.sh" "/opt/system/Boot Video Manager.sh"; do
  [ -f "$f" ] && exec bash "$f" --repair
done
exit 0
EOF
    if ! cmp -s "$tmp" "$REPAIR"; then cat "$tmp" > "$REPAIR"; fi
    chmod 755 "$REPAIR"
    cat > "$tmp" <<EOF
[Unit]
Description=dArkOSen Extended - boot video self-repair
After=local-fs.target firstboot.service
RequiresMountsFor=/roms
Before=emulationstation.service
ConditionPathExists=$D_CONF

[Service]
Type=oneshot
ExecStart=$D_REPAIR
TimeoutStartSec=90

[Install]
WantedBy=multi-user.target
EOF
    if ! cmp -s "$tmp" "$UNIT"; then cat "$tmp" > "$UNIT"; changed=1; fi
    rm -f "$tmp"
    if [ -n "$ROOT" ]; then
        ln -sfn "$D_UNIT" "$WANTS"
    else
        [ "$changed" = 1 ] && systemctl daemon-reload
        systemctl is-enabled -q bootvideo-repair.service 2>/dev/null || systemctl enable bootvideo-repair.service >/dev/null 2>&1
    fi
    Service_Present
}
Remove_Service() {
    if [ -z "$ROOT" ]; then
        systemctl disable bootvideo-repair.service >/dev/null 2>&1
    fi
    rm -f "$UNIT" "$WANTS" "$REPAIR"
    [ -z "$ROOT" ] && systemctl daemon-reload
    return 0
}

# =======================================================
# Repair / install / uninstall (shared by UI and CLI)
# =======================================================
# The roms partition (EASYROMS) is re-created by dArkOSen's first boot and
# mounted from fstab afterwards; only touch it once it is really there.
Roms_Ready() { mountpoint -q "$ROOT$D_ROMS" 2>/dev/null || [ -d "$ROOT$D_ROMS/launchimages" ]; }
# Videos shipped inside a built image are copied into the roms partition once.
Seed_Videos() {
    [ -d "$SEED" ] || return 0
    [ -e "$VID_DIR/.seeded" ] && return 0
    local v n=0
    shopt -s nullglob nocaseglob
    for v in "$SEED"/*.mp4 "$SEED"/*.mkv "$SEED"/*.webm "$SEED"/*.gif; do
        [ -e "$VID_DIR/$(basename "$v")" ] || { cp -f "$v" "$VID_DIR/" && n=$((n+1)); }
    done
    shopt -u nullglob nocaseglob
    touch "$VID_DIR/.seeded"
    OwnR "$VID_DIR"
    [ "$n" -gt 0 ] && Log "copied $n shipped video(s) into $D_VID_DIR"
    return 0
}
# Extra tools shipped inside a built image: put back any file an OTA update removed.
Seed_Overlay() {
    [ -d "$ROOT$D_OVERLAY" ] || return 0
    local f
    while IFS= read -r f; do
        f=${f#./}
        [ -e "$ROOT/$f" ] && continue
        mkdir -p "$ROOT/$(dirname "$f")"
        cp -f "$ROOT$D_OVERLAY/$f" "$ROOT/$f"
        case "$f" in *.sh|usr/local/bin/*) chmod 755 "$ROOT/$f" ;; esac
        Log "restored /$f"
    done < <(cd "$ROOT$D_OVERLAY" && find . -type f)
}
Do_Repair() {
    local rc=0
    Load_Conf
    if Roms_Ready; then
        mkdir -p "$VID_DIR/disabled"; OwnR "$VID_DIR"
        Seed_Videos
    fi
    Seed_Overlay
    Save_Conf
    Write_Player
    if Install_Hook; then Log "boot hook: OK"; else Log "boot hook: FAILED ($D_ES_SH changed?)"; rc=1; fi
    # ES entry: tracked in the config; v2 only left a backup file behind
    if [ "$ES_ENTRY" = 1 ] || [ -f "$ES_CFG.pre-bootvideo" ]; then
        if Add_ES_Entry; then Log "ES entry: OK"; else Log "ES entry: FAILED ($D_ES_CFG missing?)"; rc=1; fi
    fi
    if Install_Service; then Log "self-repair service: OK"; else Log "self-repair service: FAILED"; rc=1; fi
    # Shortcuts tool: its launch-reminder hook, which an OTA update removes when it replaces perfmax
    if [ -f "$ROOT$D_SHORTCUTS" ]; then SHORTCUTS_ROOT="$ROOT" bash "$ROOT$D_SHORTCUTS" --repair || rc=1; fi
    if [ -z "$ROOT" ] && [ -d "$VID_DIR" ]; then "$PLAYER" --rebuild; fi
    return $rc
}
Do_Install_Offline() {
    if [ ! -f "$ES_SH" ]; then
        echo "bootvideo: $ES_SH not found - is $ROOT a dArkOSen root filesystem?" >&2
        return 1
    fi
    Log "offline install into $ROOT (ark uid $ARK_UID gid $ARK_GID, roms at $D_ROMS)"
    mkdir -p "$(dirname "$TOOL")"
    if [ "$(readlink -f "$0")" != "$(readlink -f "$TOOL")" ]; then cat "$0" > "$TOOL"; fi
    chmod 755 "$TOOL"
    if [ ! -f "$CONF" ]; then
        ENABLED=1; SOUND=1; VOLUME=0; MAXLEN=15; MODE=random; FILE=""; ES_ENTRY=1
        Save_Conf
    else
        Load_Conf; ES_ENTRY=1; Save_Conf
    fi
    Do_Repair
}
Do_Uninstall() {
    Remove_Hook
    Remove_ES_Entry
    Remove_Service
    rm -f "$PLAYER" "$CONF" "$VID_DIR/gamelist.xml" "$ES_SH.pre-bootvideo" "$ES_CFG.pre-bootvideo"
    Log "uninstalled (videos in $D_VID_DIR kept; delete '$D_TOOL' to remove the tool itself)"
}

# =======================================================
# Which videos play: all / none / a list / a saved playlist
# (they play when directly in bootvideos/, not in disabled/)
# =======================================================
PLAYLISTS="$VID_DIR/.playlists"
declare -A SEL=()
MISSING=0
Video_Names() {   # $1 = on | off | all: file names, one per line, sorted
    local d e f
    shopt -s nullglob nocaseglob
    for d in "$VID_DIR" "$VID_DIR/disabled"; do
        if [ "$1" = on ] && [ "$d" != "$VID_DIR" ]; then continue; fi
        if [ "$1" = off ] && [ "$d" = "$VID_DIR" ]; then continue; fi
        for e in mp4 mkv webm gif; do for f in "$d"/*."$e"; do basename "$f"; done; done
    done | sort -fu
    shopt -u nullglob nocaseglob
}
Select_All()     { local n; SEL=(); while IFS= read -r n; do SEL["$n"]=1; done < <(Video_Names all); }
Select_None()    { SEL=(); }
Select_Current() { local n; SEL=(); while IFS= read -r n; do SEL["$n"]=1; done < <(Video_Names on); }
Select_From_File() {   # $1 = list: one file name per line (# notes and blank lines skipped); sets MISSING
    local n have
    SEL=(); MISSING=0
    have=$(Video_Names all)
    while IFS= read -r n || [ -n "$n" ]; do
        n=${n%$'\r'}; n=${n#$'\xef\xbb\xbf'}
        case "$n" in ""|\#*) continue ;; esac
        if grep -qixF -- "$n" <<<"$have"; then n=$(grep -ixF -m1 -- "$n" <<<"$have"); SEL["$n"]=1; else MISSING=$((MISSING + 1)); fi
    done < "$1"
}
Playlist_Names() { [ -d "$PLAYLISTS" ] && find "$PLAYLISTS" -maxdepth 1 -type f -name '*.txt' -printf '%f\n' | sed 's/\.txt$//' | sort -f; }
Save_Playlist() {   # $1 = name: writes the ticked videos
    mkdir -p "$PLAYLISTS"
    if [ ${#SEL[@]} -gt 0 ]; then printf '%s\n' "${!SEL[@]}" | sort -f > "$PLAYLISTS/$1.txt"; else : > "$PLAYLISTS/$1.txt"; fi
    OwnR "$PLAYLISTS"
}
Apply_Selection() {   # moves the files so that exactly the ticked videos play; prints a summary
    local n moved=0 on=0 clash=0
    mkdir -p "$VID_DIR/disabled"
    while IFS= read -r n; do
        if [ -n "${SEL[$n]:-}" ]; then
            on=$((on + 1))
            if [ -e "$VID_DIR/disabled/$n" ]; then
                if [ -e "$VID_DIR/$n" ]; then clash=$((clash + 1)); else mv "$VID_DIR/disabled/$n" "$VID_DIR/" && moved=$((moved + 1)); fi
            fi
        elif [ -e "$VID_DIR/$n" ]; then
            if [ -e "$VID_DIR/disabled/$n" ]; then clash=$((clash + 1)); else mv "$VID_DIR/$n" "$VID_DIR/disabled/" && moved=$((moved + 1)); fi
        fi
    done < <(Video_Names all)
    OwnR "$VID_DIR"
    Load_Conf
    # a fixed boot video that is no longer ticked: back to random
    if [ "$MODE" = single ] && { [ -z "$FILE" ] || [ -z "${SEL[$FILE]:-}" ]; }; then MODE=random; FILE=""; Save_Conf; fi
    if [ -z "$ROOT" ] && [ -x "$PLAYER" ]; then "$PLAYER" --rebuild; fi
    echo "$on video(s) play at boot ($moved moved)$([ "$clash" -gt 0 ] && echo ", $clash left alone: same name in both folders")"
}

case "$CLI" in
    select)
        case "$SEL_ARG" in all) Select_All ;; none) Select_None ;; *) echo "--select takes all or none" >&2; exit 1 ;; esac
        Apply_Selection; exit 0 ;;
    selectlist|playlist)
        if [ "$CLI" = playlist ]; then L="$PLAYLISTS/$SEL_ARG.txt"; else L="$SEL_ARG"; fi
        [ -f "$L" ] || { echo "bootvideo: $L not found" >&2; exit 1; }
        Select_From_File "$L"; Apply_Selection
        [ "$MISSING" -gt 0 ] && echo "$MISSING listed video(s) not found in $D_VID_DIR"
        exit 0 ;;
    repair)    Do_Repair; exit $? ;;
    install)   Do_Install_Offline; exit $? ;;
    uninstall) Do_Uninstall; exit 0 ;;
esac

# =======================================================
# Convert videos for the R36 (640x480 H.264 baseline + AAC)
# =======================================================
Convert_Videos() {
    mkdir -p "$VID_DIR/.originals"
    shopt -s nullglob nocaseglob
    local src=("$VID_DIR"/*.mp4 "$VID_DIR"/*.mkv "$VID_DIR"/*.mov "$VID_DIR"/*.webm "$VID_DIR"/*.avi "$VID_DIR"/*.gif)
    shopt -u nullglob nocaseglob
    printf "\033[H\033[2J" > "$CURR_TTY"
    [ ${#src[@]} -eq 0 ] && { echo "No videos found in $VID_DIR" > "$CURR_TTY"; sleep 3; return; }
    local f base out
    for f in "${src[@]}"; do
        base=$(basename "${f%.*}")
        [[ "$base" == *.r36 ]] && continue
        out="$VID_DIR/$base.r36.mp4"
        echo "Converting: $(basename "$f")" > "$CURR_TTY"
        if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$f" -t 60 \
            -vf "scale=640:480:force_original_aspect_ratio=decrease:flags=lanczos,pad=640:480:(ow-iw)/2:(oh-ih)/2,fps=30" \
            -c:v libx264 -profile:v baseline -level 3.0 -pix_fmt yuv420p \
            -x264-params "cabac=0:bframes=0:keyint=30:min-keyint=30:scenecut=0" \
            -c:a aac -b:a 128k -ac 2 -ar 44100 -movflags +faststart \
            "$out" > "$CURR_TTY" 2>&1; then
            mv "$f" "$VID_DIR/.originals/"; echo "  -> OK" > "$CURR_TTY"
        else
            rm -f "$out"; echo "  -> FAILED (original kept)" > "$CURR_TTY"
        fi
    done
    "$PLAYER" --rebuild
    sync; echo "Done." > "$CURR_TTY"; sleep 2
}

Pick_Video() {
    shopt -s nullglob nocaseglob
    local vids=("$VID_DIR"/*.mp4 "$VID_DIR"/*.mkv "$VID_DIR"/*.webm "$VID_DIR"/*.gif)
    shopt -u nullglob nocaseglob
    local items=("R" "Random (all enabled videos)") i=1 c v
    for v in "${vids[@]}"; do items+=("$i" "$(basename "$v")"); i=$((i+1)); done
    c=$(dialog --clear --backtitle "$BACKTITLE" --title "Choose boot video" \
        --menu "Enabled videos in $VID_DIR" 16 60 8 "${items[@]}" 2>&1 > "$CURR_TTY") || return
    if [ "$c" = "R" ]; then MODE=random; FILE=""
    else MODE=single; FILE=$(basename "${vids[$((c-1))]}"); fi
    Save_Conf
}

# "Videos that play": tick videos (all, none, search, list), save/load playlists
Tick() {   # $1 = text to search for (empty = every video): checklist, updates SEL for the videos shown
    local q="${1,,}" n i=0 out items=() names=()
    while IFS= read -r n; do
        [ -z "$q" ] || [[ "${n,,}" == *"$q"* ]] || continue
        names+=("$n"); i=$((i + 1))
        if [ -n "${SEL[$n]:-}" ]; then items+=("$i" "${n%.*}" on); else items+=("$i" "${n%.*}" off); fi
    done < <(Video_Names all)
    [ ${#names[@]} -gt 0 ] || { Msg "No video matches \"$1\"."; return; }
    out=$(dialog --clear --backtitle "$BACKTITLE" --title "Tick the videos that play" --separate-output \
          --checklist "${#names[@]} video(s)${1:+ matching \"$1\"}. X ticks / unticks." 20 64 12 "${items[@]}" 2>&1 > "$CURR_TTY") || return
    for n in "${names[@]}"; do unset "SEL[$n]"; done
    while IFS= read -r i; do [ -n "$i" ] && SEL["${names[$((i - 1))]}"]=1; done <<<"$out"
}
Type_Text() {   # $1 = prompt: dArkOSen's on-screen keyboard; prints what was typed
    local t
    t=$(osk "$1" | tail -n 1)
    setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null
    printf "\e[?25l\033[H\033[2J" > "$CURR_TTY"
    echo "$t"
}
Pick_Playlist() {   # $1 = title: prints the chosen playlist name
    local p out items=()
    while IFS= read -r p; do items+=("$p" ""); done < <(Playlist_Names)
    [ ${#items[@]} -gt 0 ] || return 1
    out=$(dialog --clear --backtitle "$BACKTITLE" --title "$1" --menu "Playlists in $D_VID_DIR/.playlists" 16 56 8 "${items[@]}" 2>&1 > "$CURR_TTY") || return 1
    echo "$out"
}
Video_Volume() {
    # Level of one video (enabled or disabled), stored by the helper in bootvideos/.volumes.txt
    shopt -s nullglob nocaseglob
    local vids=("$VID_DIR"/*.mp4 "$VID_DIR"/*.mkv "$VID_DIR"/*.webm "$VID_DIR"/*.gif
                "$VID_DIR"/disabled/*.mp4 "$VID_DIR"/disabled/*.mkv "$VID_DIR"/disabled/*.webm "$VID_DIR"/disabled/*.gif)
    shopt -u nullglob nocaseglob
    [ ${#vids[@]} -gt 0 ] || { Msg "No videos in $VID_DIR"; return; }
    local items=() i=1 c v f lvl l tag
    for v in "${vids[@]}"; do
        lvl=$("$PLAYER" --volume "$v"); tag=""
        [ "$(basename "$(dirname "$v")")" = disabled ] && tag=" [OFF]"
        items+=("$i" "$(basename "$v")$tag - $lvl %"); i=$((i+1))
    done
    c=$(dialog --clear --no-collapse --backtitle "$BACKTITLE" --title "Per-video volume" \
        --menu "Level of one video on top of the boot video volume\n(software gain, so a quiet clip can go above 100 %)" 18 64 8 \
        "${items[@]}" 2>&1 > "$CURR_TTY") || return
    f="${vids[$((c-1))]}"; lvl=$("$PLAYER" --volume "$f")
    items=()
    for l in 25 50 75 100 125 150 200 300; do
        if [ "$l" = 100 ]; then items+=("$l" "100 % (as recorded)"); else items+=("$l" "$l %"); fi
    done
    l=$(dialog --clear --no-collapse --backtitle "$BACKTITLE" --title "$(basename "$f")" \
        --menu "Current: $lvl %. Use the preview afterwards to check it." 18 56 8 \
        "${items[@]}" 2>&1 > "$CURR_TTY") || return
    "$PLAYER" --volume "$f" "$l" > /dev/null
    if dialog --clear --backtitle "$BACKTITLE" --yesno "Saved: $l %.\n\nPreview it now?" 8 44 > "$CURR_TTY"; then
        Stop_GPTKeyb; sudo -u ark "$PLAYER" --preview "$f" "$MAXLEN"; Start_GPTKeyb
    fi
}

Select_Videos() {
    local c p r nm total np items
    Select_Current
    while true; do
        total=$(Video_Names all | grep -c .)
        np=$(Playlist_Names | grep -c .)
        items=(S "Search, then tick videos" T "Tick from the whole list" A "Select all" N "Unselect all")
        [ "$np" -gt 0 ] && items+=(L "Load a playlist ($np saved)")
        items+=(W "Save the ticked videos as a playlist")
        [ "$np" -gt 0 ] && items+=(D "Delete a playlist")
        items+=(K "Done: these videos play at boot")
        c=$(dialog --clear --no-collapse --cancel-label "Back" --backtitle "$BACKTITLE" --title "Videos that play at boot" \
            --menu "Ticked: ${#SEL[@]} of $total. Nothing changes until Done or Save.\nBack leaves the current videos as they are." \
            18 60 9 "${items[@]}" 2>&1 > "$CURR_TTY") || return
        case "$c" in
            S) Tick "$(Type_Text "Search boot videos (part of a name)")" ;;
            T) Tick "" ;;
            A) Select_All ;;
            N) Select_None ;;
            L) if p=$(Pick_Playlist "Load a playlist"); then
                   Select_From_File "$PLAYLISTS/$p.txt"
                   [ "$MISSING" -gt 0 ] && Msg "$MISSING video(s) of \"$p\" are no longer in $D_VID_DIR."
               fi ;;
            W) nm=$(Type_Text "Playlist name" | tr -cd 'A-Za-z0-9 _-' | cut -c1-30)
               nm=$(echo "$nm" | sed 's/^ *//; s/ *$//')
               if [ -n "$nm" ]; then
                   Save_Playlist "$nm"; r=$(Apply_Selection)
                   Ask_Restart "Saved as \"$nm\".\n$r\n\nThe Boot Videos list in ES updates after a restart."
                   return
               fi ;;
            D) if p=$(Pick_Playlist "Delete a playlist") && dialog --clear --backtitle "$BACKTITLE" --yesno "Delete the playlist \"$p\"?\n(The videos stay.)" 9 50 > "$CURR_TTY"; then
                   rm -f "$PLAYLISTS/$p.txt"
               fi ;;
            K) r=$(Apply_Selection)
               Ask_Restart "$r\n\nThe Boot Videos list in ES updates after a restart."
               return ;;
        esac
    done
}

# =======================================================
# Gamepad / display
# =======================================================
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
Ask_Restart() {
    dialog --clear --backtitle "$BACKTITLE" --yesno "$1\n\nRestart EmulationStation now?" 10 52 > "$CURR_TTY" \
      && { Stop_GPTKeyb; printf "\033[H\033[2J" > "$CURR_TTY"; Restart_ES; trap - EXIT; exit 0; }
}
Msg() { dialog --clear --backtitle "$BACKTITLE" --msgbox "$1" "${2:-8}" "${3:-56}" > "$CURR_TTY"; }

ORIGINAL_FONT=$(setfont -v 2>&1 | grep -o '/.*\.psf.*')
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null
printf "\e[?25l\033[H\033[2J" > "$CURR_TTY"
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
chmod 666 /dev/uinput
# Confirm/back follow EmulationStation: dArkOSen's keys.gptk makes B confirm and A
# go back; when ES is set so that A confirms (no InvertButtons), do the same here.
cp /opt/inttools/keys.gptk "$TMP_KEYS"
if grep -q 'name="InvertButtons" value="true"' /home/ark/.emulationstation/es_settings.cfg 2>/dev/null; then
    sed -i 's/^a = .*/a = esc/; s/^b = .*/b = enter/' "$TMP_KEYS"
else
    sed -i 's/^a = .*/a = enter/; s/^b = .*/b = esc/' "$TMP_KEYS"
fi
sed -i 's/^x = .*/x = space/' "$TMP_KEYS"      # X ticks / unticks in checklists
Start_GPTKeyb
trap 'Exit_Menu' EXIT

# First run / every run: make sure everything is in place
Do_Repair > /dev/null

# =======================================================
# Main menu
# =======================================================
while true; do
    Load_Conf
    shopt -s nullglob nocaseglob
    nv=("$VID_DIR"/*.mp4 "$VID_DIR"/*.mkv "$VID_DIR"/*.webm "$VID_DIR"/*.gif); n=${#nv[@]}
    dv=("$VID_DIR"/disabled/*.mp4 "$VID_DIR"/disabled/*.mkv "$VID_DIR"/disabled/*.webm "$VID_DIR"/disabled/*.gif); d=${#dv[@]}
    shopt -u nullglob nocaseglob
    Hook_Present && hk="OK" || hk="MISSING"
    ES_Entry_Present && es="yes" || es="no"
    Service_Present && sr="OK" || sr="MISSING"
    [ "$ENABLED" = 1 ] && st="ON" || st="OFF"
    [ "$SOUND" = 1 ] && snd="ON" || snd="OFF"
    [ "${VOLUME:-0}" -gt 0 ] 2>/dev/null && vol="${VOLUME}%" || vol="system"
    pv=$(grep -c '=' "$VID_DIR/.volumes.txt" 2>/dev/null); [ "${pv:-0}" -gt 0 ] && vol="$vol (+$pv per video)"
    [ "$MODE" = single ] && sel="$FILE" || sel="Random"

    CHOICE=$(dialog --clear --no-collapse --cancel-label "Exit" \
        --backtitle "$BACKTITLE" --title "Boot Video" \
        --menu "Boot video: $st | Enabled: $n | Disabled: $d\nPlays: $sel | Sound: $snd | Volume: $vol | Max: ${MAXLEN}s\nHook: $hk | ES entry: $es | Self-repair: $sr" \
        20 64 10 \
        1 "Turn boot video ON / OFF" \
        2 "Choose video (or random)" \
        P "Videos that play: all, none, search, playlists" \
        3 "Toggle sound" \
        4 "Boot video volume" \
        5 "Max length" \
        6 "Convert videos for the R36" \
        7 "Preview a random video now" \
        8 "'Boot Videos' in EmulationStation" \
        9 "Repair (after OTA update)" \
        10 "Uninstall" \
        2>&1 > "$CURR_TTY") || Exit_Menu

    case "$CHOICE" in
        1) [ "$ENABLED" = 1 ] && ENABLED=0 || ENABLED=1; Save_Conf ;;
        2) Pick_Video ;;
        P) Select_Videos ;;
        3) [ "$SOUND" = 1 ] && SOUND=0 || SOUND=1; Save_Conf ;;
        4) m=$(dialog --clear --backtitle "$BACKTITLE" --title "Boot video volume" \
               --menu "Mixer level used only while the video plays;\nthe previous level comes back afterwards." 19 56 11 \
               0 "System volume (unchanged)" 30 "30 %" 40 "40 %" 50 "50 %" 60 "60 %" 70 "70 %" 80 "80 %" 90 "90 %" 100 "100 %" \
               V "Per video: one louder or quieter than the others" \
               2>&1 > "$CURR_TTY") || continue
           if [ "$m" = V ]; then Video_Volume; else VOLUME=$m; Save_Conf; fi ;;
        5) m=$(dialog --clear --backtitle "$BACKTITLE" --menu "Max length" 14 40 6 \
               5 "5 s" 10 "10 s" 15 "15 s" 30 "30 s" 60 "60 s" 2>&1 > "$CURR_TTY") && { MAXLEN=$m; Save_Conf; } ;;
        6) Convert_Videos ;;
        7) Stop_GPTKeyb
           shopt -s nullglob nocaseglob
           v=("$VID_DIR"/*.mp4 "$VID_DIR"/*.mkv "$VID_DIR"/*.webm "$VID_DIR"/*.gif)
           shopt -u nullglob nocaseglob
           if [ ${#v[@]} -gt 0 ]; then sudo -u ark "$PLAYER" --preview "${v[$((RANDOM % ${#v[@]}))]}" "$MAXLEN"
           else Msg "No videos in $VID_DIR"; fi
           Start_GPTKeyb ;;
        8) if ES_Entry_Present; then
               a=$(dialog --clear --backtitle "$BACKTITLE" --title "Boot Videos in ES" --menu "" 10 50 2 \
                   1 "Refresh list and thumbnails" 2 "Remove from EmulationStation" 2>&1 > "$CURR_TTY") || continue
               if [ "$a" = 2 ]; then
                   Remove_ES_Entry; ES_ENTRY=0; Save_Conf; rm -f "$ES_CFG.pre-bootvideo"
                   Ask_Restart "'Boot Videos' was removed from EmulationStation."
               else
                   "$PLAYER" --rebuild; Ask_Restart "List refreshed."
               fi
           else
               "$PLAYER" --rebuild
               if Add_ES_Entry; then ES_ENTRY=1; Save_Conf; Ask_Restart "'Boot Videos' is in EmulationStation."
               else Msg "Could not edit\n$ES_CFG"; fi
           fi ;;
        9) r=$(Do_Repair 2>&1); Msg "$r" 10 60 ;;
        10) if dialog --clear --backtitle "$BACKTITLE" --yesno "Remove the boot video, the ES entry, the helper and the self-repair service?\n\nYour videos in $VID_DIR are kept." 11 56 > "$CURR_TTY"; then
               Do_Uninstall > /dev/null
               Msg "Removed. Your videos in $VID_DIR were kept.\nDelete '$(basename "$D_TOOL")' from Options > System to remove this tool." 10 60
               Ask_Restart "Removed from EmulationStation."
               Exit_Menu
           fi ;;
    esac
done
