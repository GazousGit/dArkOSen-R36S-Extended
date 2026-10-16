#!/bin/bash
# Build the 32-bit (armhf) legacy flycast libretro core for dArkOSen.
#
# Runs in WSL as root. Compiles inside a Debian trixie chroot whose armhf cross
# toolchain matches the dArkOSen image (glibc 2.41, GCC 14), the way ArkOS builds
# it natively: platform=classic_armv8_a35, FORCE_GLES=1, ngen_arm.S through gcc.
# GCC 14 rejects the implicit declarations in the bundled libzip that the older
# GCC of the ArkOS build machine only warned about, hence -fpermissive for C.
#
# usage: build.sh <git ref in flycast32_rumble/> <output name> [extra make args...]
#   build.sh origin/dev metallic-dev
#   build.sh gazous gazous-v1
# Result: out/<output name>/<target>_libretro.so (stripped) + build.log + commit.txt

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC_REPO="$HERE/flycast32_rumble"
CHROOT=${CHROOT:-/root/flycast-build/trixie}

[ $# -ge 2 ] || { echo "usage: $0 <git-ref> <output-name> [make args...]" >&2; exit 2; }
REF=$1
NAME=$2
shift 2

[ -x "$CHROOT/usr/bin/arm-linux-gnueabihf-g++" ] || { echo "missing build chroot $CHROOT" >&2; exit 1; }
COMMIT=$(git -C "$SRC_REPO" rev-parse --verify "$REF^{commit}")

WORK="$CHROOT/build/$NAME"
OUT="$HERE/out/$NAME"
rm -rf "$WORK" "$OUT"
mkdir -p "$CHROOT/build" "$OUT"

# A real clone (not an archive) so the Makefile's GIT_VERSION ends up in the core.
git clone -q --no-checkout "$SRC_REPO" "$WORK"
git -C "$WORK" -c advice.detachedHead=false checkout -q "$COMMIT"

JOBS=$(nproc)
echo "building $NAME from $COMMIT ($REF) with $JOBS jobs"
if ! chroot "$CHROOT" /bin/bash -c "cd /build/$NAME && make \
        platform=classic_armv8_a35 FORCE_GLES=1 ARCH=arm \
        CC='arm-linux-gnueabihf-gcc -fpermissive' CXX=arm-linux-gnueabihf-g++ \
        -j$JOBS $*" > "$OUT/build.log" 2>&1; then
    tail -30 "$OUT/build.log" >&2
    echo "build failed, full log: $OUT/build.log" >&2
    exit 1
fi

SO=$(cd "$WORK" && ls -1 ./*_libretro.so | head -1)
[ -n "$SO" ] || { echo "no *_libretro.so produced" >&2; exit 1; }
chroot "$CHROOT" arm-linux-gnueabihf-strip -o "/build/$NAME/stripped.so" "/build/$NAME/$SO"
cp "$WORK/stripped.so" "$OUT/$(basename "$SO")"
{
    echo "ref:    $REF"
    echo "commit: $COMMIT"
    echo "make:   platform=classic_armv8_a35 FORCE_GLES=1 ARCH=arm $*"
    echo "gcc:    $(chroot "$CHROOT" arm-linux-gnueabihf-g++ --version | head -1)"
    echo "built:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/commit.txt"
ls -l "$OUT"
