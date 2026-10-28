#!/bin/bash
# Builds retrorun (64-bit) and retrorun32 (32-bit) from the GazousGit/retrorun fork,
# branch ext/hotkeys-3.0.0 (navy1978/retrorun tag 3.0.0 + configurable hotkeys),
# for the R36S running dArkOSen (Debian trixie, glibc 2.41, RK3326 Mali blob).
#
# Runs in WSL as root. Compiles inside the Debian trixie chroot that also builds the
# Flycast cores (CHROOT), with the Debian cross compilers for arm64 and armhf, the
# Debian development packages of libdrm, libevdev, ALSA, OpenAL and libpng for both
# targets, the Rockchip RGA headers (airockchip/librga, include/) and, taken from the
# dArkOSen image, libMali.so (linked as libEGL / libGLESv2 / libgbm, unversioned names
# like the shipped binaries) and librga.so.2:
#   $CHROOT/build/rr-include/rga/*.h
#   $CHROOT/build/rr-sysroot/<triplet>/{libMali.so,libEGL.so,libGLESv2.so,libgbm.so,librga.so*}
#
#   SRC=/root/retrorun-build/src CHROOT=/root/flycast-build/trixie bash build.sh
#
# Output: out/retrorun, out/retrorun32, out/BUILD-INFO.txt. Nothing touches the console.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-/root/retrorun-build/src}
CHROOT=${CHROOT:-/root/flycast-build/trixie}
OUT=${OUT:-$HERE/out}
JOBS=${JOBS:-$(nproc)}

[ -d "$SRC/src" ] || { echo "missing retrorun source $SRC" >&2; exit 1; }
[ -x "$CHROOT/usr/bin/aarch64-linux-gnu-g++" ] || { echo "missing arm64 cross compiler in $CHROOT" >&2; exit 1; }
[ -x "$CHROOT/usr/bin/arm-linux-gnueabihf-g++" ] || { echo "missing armhf cross compiler in $CHROOT" >&2; exit 1; }
[ -f "$CHROOT/build/rr-include/rga/RgaApi.h" ] || { echo "missing RGA headers in $CHROOT/build/rr-include" >&2; exit 1; }

mkdir -p "$OUT" "$CHROOT/build"
rsync -a --delete --exclude '/.git/' "$SRC/" "$CHROOT/build/retrorun-src/"
COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
{
    echo "retrorun hotkeys build $(date -u +%Y-%m-%dT%H:%MZ)"
    echo "source: GazousGit/retrorun $COMMIT ($(git -C "$SRC" describe --tags --always 2>/dev/null))"
    echo "gcc:    $(chroot "$CHROOT" aarch64-linux-gnu-g++ --version | head -1)"
} > "$OUT/BUILD-INFO.txt"

build_one() {      # triplet output-name
    local T=$1 NAME=$2
    [ -f "$CHROOT/build/rr-sysroot/$T/libEGL.so" ] || { echo "missing Mali/RGA libraries for $T" >&2; exit 1; }
    echo "== $NAME ($T)"
    chroot "$CHROOT" /bin/bash -c "cd /build/retrorun-src && \
        make PLATFORM=linux-go2 config=release clean >/dev/null 2>&1; \
        make PLATFORM=linux-go2 config=release -j$JOBS verbose=1 \
            CC=$T-gcc CXX=$T-g++ AR=$T-ar \
            ARCH='-I/build/rr-include -L/build/rr-sysroot/$T'" > "$OUT/$NAME.log" 2>&1 \
        || { tail -30 "$OUT/$NAME.log" >&2; echo "build failed: see $OUT/$NAME.log" >&2; exit 1; }
    cp "$CHROOT/build/retrorun-src/retrorun" "$OUT/$NAME"
    chmod 755 "$OUT/$NAME"
    {
        echo
        echo "== $NAME"
        file -b "$OUT/$NAME" | cut -d, -f1-3
        echo "md5:    $(md5sum "$OUT/$NAME" | cut -d' ' -f1)"
        echo "size:   $(stat -c %s "$OUT/$NAME")"
        echo "needed: $(readelf -d "$OUT/$NAME" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' | tr '\n' ' ')"
        echo "glibc:  $(readelf --version-info "$OUT/$NAME" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)"
        echo "marker: $(strings "$OUT/$NAME" | grep -c '^retrorun_hotkey_menu$') (retrorun_hotkey_menu string)"
    } >> "$OUT/BUILD-INFO.txt"
}

build_one aarch64-linux-gnu retrorun
build_one arm-linux-gnueabihf retrorun32
cat "$OUT/BUILD-INFO.txt"
