#!/bin/bash
# Build modern flycast (flyinghead, our fork in flycast/) as a 32-bit (armhf)
# libretro core for retroarch32 / retrorun32 on dArkOSen.
#
# Runs in WSL as root, compiles the current checkout of flycast/ (submodules
# included) in the Debian trixie chroot with armhf-toolchain.cmake.
#   GLES3 renderer (Mali-G31), no Vulkan; bundled zlib/libzip, no Lua, so the core
#   only needs libc/libstdc++/libgomp; LOW_END picks the handheld option defaults
#   (DSP off, per-strip sorting, auto skip frame "some", GD-ROM fast loading).
#
# usage: build-modern.sh <output name> [extra cmake args...]
# Result: out/<output name>/flycast32_modern_libretro.so (stripped, installed beside
# the other retroarch32 cores under that name) + build.log + commit.txt

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/flycast"
CHROOT=${CHROOT:-/root/flycast-build/trixie}

[ $# -ge 1 ] || { echo "usage: $0 <output-name> [cmake args...]" >&2; exit 2; }
NAME=$1
shift

[ -x "$CHROOT/usr/bin/cmake" ] || { echo "missing cmake in $CHROOT" >&2; exit 1; }
VERSION=$(git -C "$SRC" describe --tags --always --dirty)
COMMIT=$(git -C "$SRC" rev-parse HEAD)

OUT="$HERE/out/$NAME"
rm -rf "$OUT" "$CHROOT/build/$NAME"
mkdir -p "$OUT" "$CHROOT/build/flycast-src"
# The source tree is synced (with .git, for the version string) and built out of tree.
rsync -a --delete --exclude '/build/' "$SRC/" "$CHROOT/build/flycast-src/"
cp "$HERE/armhf-toolchain.cmake" "$CHROOT/build/"

echo "building $NAME from $VERSION"
if ! chroot "$CHROOT" /bin/bash -c "git config --global --add safe.directory '*' &&
        cmake -S /build/flycast-src -B /build/$NAME -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=/build/armhf-toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DLIBRETRO=ON -DUSE_GLES=ON -DUSE_OPENGL=ON -DUSE_VULKAN=OFF \
        -DUSE_OPENMP=ON -DUSE_HOST_LIBZIP=OFF -DUSE_LUA=OFF -DUSE_BREAKPAD=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON -DCMAKE_DISABLE_FIND_PACKAGE_MiniUPnPc=ON \
        -DCMAKE_C_FLAGS=-DLOW_END -DCMAKE_CXX_FLAGS=-DLOW_END \
        $* && ninja -C /build/$NAME" > "$OUT/build.log" 2>&1; then
    tail -30 "$OUT/build.log" >&2
    echo "build failed, full log: $OUT/build.log" >&2
    exit 1
fi

chroot "$CHROOT" arm-linux-gnueabihf-strip -o "/build/$NAME/stripped.so" "/build/$NAME/flycast_libretro.so"
cp "$CHROOT/build/$NAME/stripped.so" "$OUT/flycast32_modern_libretro.so"
{
    echo "version: $VERSION"
    echo "commit:  $COMMIT"
    echo "cmake:   LIBRETRO GLES3 OpenMP LOW_END $*"
    echo "gcc:     $(chroot "$CHROOT" arm-linux-gnueabihf-g++ --version | head -1)"
    echo "built:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/commit.txt"
ls -l "$OUT"
