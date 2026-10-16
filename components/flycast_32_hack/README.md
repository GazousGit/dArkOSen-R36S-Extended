# Dreamcast cores for retroarch32 / retrorun32 (flycast)

Two 32-bit flycast libretro cores for dArkOSen on the R36S, to install beside ArkOS's
`flycast32_rumble` (Dreamcast, Naomi, Atomiswave):

| Core | Source | Why |
| --- | --- | --- |
| `flycast32_rumble_hack` | metallic77's low-end fork of the legacy core + our fixes | Faster on many games (GTA2...), SH4 underclock option |
| `flycast32_modern` | flyinghead's current flycast (v2.7) built for armhf | Its ARM32 dynarec emulates the MMU: Windows CE games (Resident Evil 2...) can boot |

**Status (end of 2026-10-16):** both installed on one console with `device-install.sh`
(`out/gazous-v2`, `out/modern-dArkOSen-5`). `flycast32_rumble_hack` is not yet judged in play.
`flycast32_modern` is **not usable for games**: with the two fixes below it boots the Dreamcast
BIOS and shows Resident Evil 2's Windows CE logo, then hits heap corruption; Code Veronica hangs at
once. It now keeps its options apart from the legacy cores (`flycast_` prefix). The Windows CE goal
was dropped on 2026-10-16: RE2 is out of reach on the R36S even with the 64-bit modern flycast. Even the 64-bit modern standalone (v2.7) runs RE2 at
10-30 fps and freezes after its brightness prompt, so WinCE games look out of reach on the R36S for
now. Hand-off notes: `extended/CONTEXT.md` section 8. Nothing here is part of the image build yet.

## Sources

The clones, build outputs and binaries are ignored (`.gitignore`); recreate the clones with:

```sh
git clone -b gazous https://github.com/GazousGit/flycast32_rumble.git flycast32_rumble
git clone --recurse-submodules -b dArkOSen https://github.com/GazousGit/flycast.git flycast
```

| Fork | Branch | Content |
| --- | --- | --- |
| [GazousGit/flycast32_rumble](https://github.com/GazousGit/flycast32_rumble) (of `metallic77/flycast32_rumble`) | `dev` | metallic77's latest (`5e576b1`, 2025-07-16) |
| | `arkos-stock` | `4c293f3` + the 3 ArkOS patches (makefile, per-pixel, rumble): rebuild of the core dArkOSen ships |
| | `gazous` | `dev` + our fixes, output `flycast32_rumble_hack_libretro.so` |
| [GazousGit/flycast](https://github.com/GazousGit/flycast) (of `flyinghead/flycast`) | `master` | upstream |
| | `dArkOSen` | `master` + R36S motor rumble, library name "Flycast32 Modern", addrspace shift fix (`e0e960683`) |

### Where metallic77's work survives

metallic77 (DariusG) shared their core on Reddit in 2025 and later deleted their messages.

- **`metallic77/flycast32_rumble`, branch `dev`** has the whole history: the January 2025
  low-end work, the June 19 2025 R36S target (shared as release `4c293f-R36s-32bit`) and
  the July 2025 changes.
- `metallic77/flycast` was reset to the stock libretro commit `4c293f3` (April 2022), but
  GitHub still serves its January 2025 tip `603814c` by hash. Knulli, ROCKNIX, ArchR and
  plumOS pin that commit as "flycast2021" / "flycast_xtreme".
- ArkOS's stock core is the same legacy source: `libretro/flycast` at `4c293f3` plus the patches
  in `christianhaitian/rk3326_core_builds/patches/flycast-patch-*`. dArkOSen ships it as
  `~/.config/retroarch32/cores/flycast32_rumble_libretro.so` (`0.1 4c293f30`), the default core
  of the Dreamcast system for retroarch32 and retrorun32.
- The binary shared in 2025 (used here as the "hacked" emulator entry,
  `flycast32_rumble_hack_libretro.so`) reports `0.1 51c45727`: their commit of 2025-06-19, built
  with Debian 10's GCC 8.3.

## What metallic77 changed (diff 4c293f3..dev)

| Change | Effect |
| --- | --- |
| `reicast_sh4clock` option (`d20`..`d6` = 100..333 MHz, default `d12` = 165 MHz); every SH4 block's cycle count is multiplied by it (`decoder.cpp`) | The real speed gain: fewer emulated SH4 instructions per frame. CPU-bound games run their logic slower (in-game slowdown) but the frame rate holds. |
| The x1.5 multiplier for MMU (Windows CE) games is replaced by that option | WinCE games get x1.2 by default instead of x1.5 |
| `unstable_opt = 1` (`nullDC.cpp`) | Store-queue fast path in the ARM dynarec (`rec_arm.cpp`); the code comment warns THPS2 uses cross-area writes |
| Defaults when the frontend gives no value: modifier volumes off, NTSC/USA/English, AF off, HLE BIOS option default "enabled", 640x480 | No effect on retroarch32 in dArkOSen: its `retroarch-core-options.cfg` sets every `reicast_*` key (320x240, modifier volumes on, HLE BIOS off). `retrorun.cfg` already turns modifier volumes off. |
| Post-processing (PowerVR2 filter) code removed, upscaler sizes above 1600x1200 removed | Nothing at the settings dArkOSen uses |
| Dynarec code cache 16 -> 15 MB, NULL-literal check no longer prints | Negligible |
| Bump-map shader constants folded by hand, RPi4 workaround removed | Negligible (the GLSL compiler folds constants, the workaround was not compiled in) |
| `classic_armv8_a35`: `-O3` instead of `-Ofast` (`-ffast-math` stays), no OpenMP, no `LOW_RES` | OpenMP only served the texture upscaler, which is compiled out |
| Output renamed `flycast32_rumble`, library name "Flycast32 Rumble" | Drop-in for ArkOS's file, but **without the ArkOS rumble patch**: why rumble stopped when it replaced the stock core |

## Our fixes (branch `gazous`)

1. **Rumble back**, with the ArkOS patch's sysfs files and values, but written by a helper thread
   instead of `system("echo ... && sleep 0.4 ...")` / `sudo tee` on the emulation thread for every
   vibration command. The motor runs while the game asks for a strength above 0, at least 400 ms
   per pulse, and is switched off when the game unloads. **On the R36S with dArkOSen this path is
   inactive**: the pad driver ("GO-Super Gamepad") offers force feedback (EV_FF, FF_RUMBLE) and owns
   the PWM, so `/sys/class/pwm/pwmchip*/pwm0` never exists there. Rumble then goes through the
   frontend (RetroArch's udev force feedback), as with the stock core; dArkOSen's retroarch32
   options ship `reicast_enable_purupuru = "disabled"`, so the vibration pack must be turned on.
2. **`reicast_sh4clock` fallback**: when the frontend returns no value, the multiplier stayed 0
   (blocks cost no cycles). It now falls back to the option default (x1.2). A plain number is read
   as MHz, so `retrorun.cfg` can say `reicast_sh4clock = 125`, the same format as modern flycast.
3. **Own name**: `flycast32_rumble_hack_libretro.so`, library "Flycast32 Rumble Hack", so it sits
   beside ArkOS's `flycast32_rumble` instead of replacing it.

## Modern flycast as a 32-bit core (`flycast32_modern`)

dArkOSen has no modern flycast as a RetroArch core: its 64-bit `flycast_libretro.so` has the legacy
option set too (its arm64 dynarec handles the MMU, hence WinCE boots there, slowly). The only modern
one is the 64-bit standalone (`/opt/flycastsa/flycast`, v2.7). Modern flycast's ARM32 dynarec
translates MMU addresses (`genMmuLookup`, `mmuAddressLUT` in `core/rec-ARM/rec_arm.cpp`), so a
modern 32-bit core can boot WinCE games; how fast is for the device to tell. It already has
`reicast_sh4clock` (values in MHz) and `reicast_auto_skip_frame`.

The `dArkOSen` branch adds the same motor rumble as above and the library name "Flycast32 Modern",
so RetroArch keeps its per-game options apart from the legacy "Flycast" core. Since `a873b38cf` its
options use the prefix **`flycast_`** (as ROCKNIX does) instead of `reicast_`: the legacy cores and
this one share `retroarch-core-options.cfg`, and RetroArch rewrites that file at every unload with
the values the running core knows, so with a shared prefix the modern core replaced values of the
legacy cores (cable type "VGA (RGB)" became "TV (Composite)"). dArkOSen's `reicast_*` keys therefore
do not apply to it; its own `flycast_*` keys appear in the file after its first run. VMU saves stay
shared (`<saves>/reicast/`).

Checked in the sources and the 10152026 image, for both cores:
- BIOS: `<system dir>/dc/`; retroarch32 has `system_directory = /roms/bios`, retrorun32 gets
  `-d /roms/bios`, so `/roms/bios/dc/dc_boot.bin` and `dc_flash.bin` (also `naomi.zip`, `awbios.zip`).
- Buttons (RetroPad -> Dreamcast): B/A/Y/X -> A/B/X/Y, L2/R2 -> analog L/R triggers (a digital
  press reads as a full pull), L1/R1 -> C/Z, Start, left stick -> analog. Same as the legacy cores.
- Quit: the frontend's, not the core's: retroarch32 Select (hotkey, button 12) + Start (exit,
  button 13); retrorun32 Select + Start.

**The core must be compiled in ARM (A32) mode.** The SH4 and ARM7 dynarecs call C++ functions
with a direct `BL` from A32 code, which cannot reach Thumb functions (odd addresses), and Debian's
armhf compiler defaults to Thumb-2, ARMv7, VFPv3-D16, no NEON. Built that way, the core aborted in
`retro_init` (`aica::arm::init` -> `arm7backend_flush` -> `vixl::aarch32::Assembler::bl` ->
`UnimplementedDelegate`), which sent ES straight back. `build-modern.sh` passes
`-marm -mcpu=cortex-a35 -mfpu=neon-fp-armv8 -mfloat-abi=hard`; `readelf -A` on the result shows
`Tag_CPU_arch: v8` and `NEON for ARMv8`.

**Upstream undefined behaviour in `core/hw/mem/addrspace.cpp`** (fixed on the `dArkOSen` branch,
`e0e960683`): `readConst`/`writeConst`/`readt`/`writet` shifted the address by the whole tagged page
entry (`addr <<= iirf`) instead of its low 5 bits. Inside the `ptr != nullptr` branch that entry is
known to be >= 32, and GCC 14 on armhf folds the shifts to 0: every access through a memory page
read its first word, the BIOS never ran, and the screen stayed black (the SH4 PC slid through
memory with both the dynarec and the interpreter). Shifting by `iirf & HANDLER_MAX` fixes it.

Still open with both fixes: Resident Evil 2 reaches the "SEGA / Powered by Windows CE" screen,
then glibc reports `double free or corruption (!prev)`; Code Veronica hangs at once (RetroArch
must be SIGKILLed); earlier builds also hit a SIGSEGV in a system library when RetroArch unloads
the core. `tools/abort-trace.c` and `extended/CONTEXT.md` 8.5 describe how to test and debug on
the console.

## Build

In WSL, as root. One-time build chroot (Debian trixie, whose armhf glibc 2.41 and GCC 14 match
the dArkOSen image):

```sh
apt-get install -y debootstrap rsync
debootstrap --variant=minbase --include=ca-certificates trixie /root/flycast-build/trixie http://deb.debian.org/debian
chroot /root/flycast-build/trixie bash -c 'dpkg --add-architecture armhf && apt-get update &&
  apt-get install -y --no-install-recommends crossbuild-essential-armhf libgles-dev:armhf \
  libegl-dev:armhf zlib1g-dev:armhf make git file cmake ninja-build pkg-config python3'
```

- `./build.sh <ref> <name>`: legacy core from a ref of `flycast32_rumble/` (about 1 minute), with
  ArkOS's flags (`platform=classic_armv8_a35 FORCE_GLES=1`, `ngen_arm.S` through gcc). GCC 14
  needs `-fpermissive` for the bundled libzip's implicit declarations.
- `./build-modern.sh <name>`: modern core from the current checkout of `flycast/`, with CMake and
  `armhf-toolchain.cmake` (GLES3, OpenMP, no Vulkan, bundled zlib/libzip, no Lua), in ARM mode for
  the Cortex-A35 with NEON (see above). `LOW_END` picks handheld defaults: DSP off, per-strip
  sorting, auto skip frame "some", GD-ROM fast loading. The core needs only libc, libstdc++ and
  libgomp.

Output: `out/<name>/` with the stripped core, `build.log` and `commit.txt`.

## Install on a device

`./device-install.sh [host]` (default `192.168.1.159`, user `ark`) copies `out/gazous-v2` and
`out/modern-dArkOSen` to `~/.config/retroarch32/cores/` with `.info` files, backs up
`es_systems.cfg` once (`es_systems.cfg.before-flycast32`), lists both cores after every
`<core>flycast32_rumble</core>` (Dreamcast, Naomi, Atomiswave for retroarch32 and retrorun32: 6
lists; checked offline on the 10152026 file: valid XML, a second run changes nothing) and restarts ES.
An OTA update that replaces `es_systems.cfg` removes the entries again.

SH4 clock: RetroArch Quick Menu > Options > "SH4 CPU under/overclock"; retrorun: add
`reicast_sh4clock = 125` to `~/.config/retrorun.cfg`. Compare cores with the same settings.

## Not done yet

- Device test of `flycast32_rumble_hack` against the stock core (GTA2, heavy games, SH4 clock).
- Windows CE on the legacy core: its ARM32 dynarec has no MMU address translation (only the store
  queue checks the MMU), so games that turn the MMU on hang at the WinCE logo. Not worth porting:
  modern flycast has MMU support, and even it is too slow on this hardware (see Status).
- `flycast32_modern`: the RE2 heap corruption and the Code Veronica hang, or drop it.
- Offer the addrspace fix upstream (flyinghead/flycast).
- Profile-guided build of the legacy core (`PGO_MAKE=1` / `PGO_USE=1` exist in its Makefile):
  needs profiling runs on the device.
- Shipping the cores in built images (built in the workflow from the forks).
