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
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
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
}
xml_ok() { python3 -I -c 'import sys,xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$1"; }
count_systems() { python3 -I -c 'import sys,xml.etree.ElementTree as E; print(sum(1 for s in E.parse(sys.argv[1]).getroot() if s.findtext("name")==sys.argv[2]))' "$1" "$2"; }

echo "== syntax"
expect "bash -n Boot Video Manager.sh" bash -n "$TOOL"
expect "bash -n inject.sh"             bash -n "$INJECT"
expect "bash -n build-image.sh"        bash -n "$BUILD"
if command -v shellcheck >/dev/null; then
    expect "shellcheck Boot Video Manager.sh" shellcheck -S warning -e SC1090,SC1091,SC2016,SC2024 "$TOOL"
    expect "shellcheck inject.sh"             shellcheck -S warning "$INJECT"
    expect "shellcheck build-image.sh"        shellcheck -S warning -e SC2016 "$BUILD"
    expect "shellcheck run-tests.sh"          shellcheck -S warning -e SC2016 "$0"
else
    echo "  skip shellcheck (not installed)"
fi

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
expect "config: DIR=/roms/bootvideos"         grep -q '^DIR="/roms/bootvideos"$' "$CONF"
expect "config owned by ark (1000:1000)"      test "$(stat -c %u:%g "$CONF")" = "1000:1000"
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
# first regular boot: roms is mounted and populated, the repair service seeds the videos once
mkdir -p "$R6/roms/launchimages"
expect "--repair exits 0 (first boot with roms)" env BOOTVIDEO_ROOT="$R6" bash "$TOOL" --repair
expect "shipped videos copied to bootvideos"  test "$(ls "$R6/roms/bootvideos/"*.mp4 | wc -l)" = "2"
expect "video with & and spaces copied"       test -f "$R6/roms/bootvideos/Intro & Logo.mp4"
expect "seed marker written"                  test -e "$R6/roms/bootvideos/.seeded"
expect "copied videos owned by ark"           test "$(stat -c %u:%g "$R6/roms/bootvideos/second.mp4")" = "1000:1000"
rm -f "$R6/roms/bootvideos/second.mp4"                                # the user deletes one
expect "--repair exits 0 (later boot)"        env BOOTVIDEO_ROOT="$R6" bash "$TOOL" --repair
expect "deleted video is not copied again"    test ! -e "$R6/roms/bootvideos/second.mp4"
expect "inject.sh without videos exits 0"     bash "$INJECT" "$R6" "" 09302026
expect "seed folder removed when no videos"   test ! -e "$SEED"

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
