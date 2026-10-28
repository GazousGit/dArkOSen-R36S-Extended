# retrorun hotkeys build

retrorun's key combinations are compiled in: `retrorun.cfg` cannot move them. This
component is navy1978's RetroRun 3.0.0, the exact version dArkOSen ships (its
`retrorun` and `retrorun32` of 2026-09-30 print `3.0.0`), plus one change that makes
the combinations settings, so that retrorun can follow the universal hotkey layout of
*Options > Shortcuts* (FN menu, SELECT + R2 / L2 slots, SELECT + L3 fast-forward; save /
load on SELECT + R1 / L1 and SELECT + START quit were already retrorun's).

| Piece | Where |
| --- | --- |
| Source | fork [GazousGit/retrorun](https://github.com/GazousGit/retrorun), branch `ext/hotkeys-3.0.0` = tag `3.0.0` + one commit |
| The same change as a patch | `retrorun-hotkeys-3.0.0.patch` (reference copy, `git am`-able on tag 3.0.0) |
| Build | `build.sh` (WSL, Debian trixie cross chroot) → `out/retrorun`, `out/retrorun32`, `out/BUILD-INFO.txt`; `out/` is not tracked |
| Install / remove on the console | `device-install.sh [host]`, `device-remove.sh [host]` (SSH, ark / ark) |
| Layout integration | `extended/overlay/opt/system/Shortcuts.sh`, component `retrorun` (`RETRORUN_LAYOUT`), pages `retrorun.txt` / `retrorun.darkosen.txt` |

## The change (`retrorun_hotkey_*` settings)

Six settings in `retrorun.cfg`, values = the button names of `retrorun_mapping_button_*`
(`A`, `B`, `X`, `Y`, `DPadUp`, `TopLeft`, `TriggerRight`, `F1`..`F12`, `START`,
`SELECT`, `THUMBL`...) or `none`. Without a setting the historical combination is kept,
so the binary behaves exactly like dArkOSen's until the lines exist.

| Setting | Meaning | Universal layout on the R36S |
| --- | --- | --- |
| `retrorun_hotkey_menu` | a button that opens and closes the menu on its own | `F5` (FN) |
| `retrorun_hotkey_slot_next` / `_slot_prev` | with the hotkey modifier (SELECT): state slot | `TriggerRight` / `TriggerLeft` (R2 / L2) |
| `retrorun_hotkey_fast_forward` | with SELECT: fast-forward on / off | `F3` (L3) |
| `retrorun_hotkey_save_state` / `_load_state` | with SELECT: save / load | not written (R1 / L1 already) |

The ArkOS-style alternative input mode (`retrorun_alternative_input_mode = true`, what
dArkOSen uses) had no fast-forward key at all in 3.0.0; it gets the same toggle as the
AmberELEC mode. Everything else (SELECT + X menu, L3 + R3 menu, SELECT + START quit, A
pause, Y FPS, B screenshot) is untouched.

Button names on the R36S: the pad is "GO-Super Gamepad" and `/home/ark/.config/.DEVICE`
says `RG351MP`, so retrorun takes its gpio-joypad layout: SELECT = `F1`
(`BTN_TRIGGER_HAPPY1`), START = `F2`, L3 / R3 = `F3` / `F4`, FN = `F5` (unused by
retrorun until now), L2 / R2 = `TriggerLeft` / `TriggerRight`, L1 / R1 = `TopLeft` /
`TopRight`. `retrorun_swap_l1r1_with_l2r2` only swaps the game's buttons, not the hotkeys.

## Building

`build.sh` compiles inside the Debian trixie chroot of the Flycast component
(`/root/flycast-build/trixie` in WSL) with Debian's cross compilers (`crossbuild-essential-arm64`,
the armhf one was already there) and the arm64 / armhf development packages of libdrm,
libevdev, ALSA, OpenAL, libpng and GBM. Two things are not in Debian and were taken from
elsewhere, once, into the chroot:

- `/build/rr-include/rga/*.h`: the Rockchip RGA headers (`include/` of
  [airockchip/librga](https://github.com/airockchip/librga));
- `/build/rr-sysroot/<triplet>/`: `libMali.so` (the RK3326 blob), `librga.so.2` and
  `libgo2.so` copied from the dArkOSen 10152026 image for each architecture, with
  `libEGL.so`, `libGLESv2.so` and `libgbm.so` as links to `libMali.so`, so that the binary
  records the same unversioned `libEGL.so` dependency as dArkOSen's (a build against Mesa
  would record `libEGL.so.1` and fail on the console; see upstream's
  `tools/build-rk3326-mali.sh`).

The result links against exactly the libraries of the shipped binaries (`libEGL.so
librga.so.2 libevdev.so.2 libdrm.so.2 libpng16.so.16 libasound.so.2 libopenal.so.1`),
needs glibc 2.38 (the image has 2.41) and is within 300 bytes of their size.

```sh
# WSL, as root; the source clone is /root/retrorun-build/src (fork, branch ext/hotkeys-3.0.0)
SRC=/root/retrorun-build/src bash components/retrorun_hotkeys/build.sh
```

## Installing

```sh
bash components/retrorun_hotkeys/device-install.sh          # 192.168.1.159
```

keeps dArkOSen's binaries as `/usr/local/bin/retrorun.darkosen` and `retrorun32.darkosen`,
installs the two builds, links the default config path
(`/storage/.config/distribution/configs/retrorun.cfg`, which Saturn's launcher uses because
it runs retrorun without `-c`) to `/home/ark/.config/retrorun.cfg`, and runs
`Shortcuts.sh --repair`: with the universal layout on, the four `retrorun_hotkey_*` lines
are appended to `retrorun.cfg` and the reminder page switches to `retrorun.txt`. The
Shortcuts tool recognises the build by the string `retrorun_hotkey_menu` in the binary;
with dArkOSen's own build the component reports `missing`, nothing is written and the
page `retrorun.darkosen.txt` is shown. `device-remove.sh` puts everything back.

An OTA update that replaces `retrorun` brings dArkOSen's build back: the component then
reads `missing` again and the page follows; run `device-install.sh` again.

## Status

Built on 2026-10-27 (see `out/BUILD-INFO.txt`), **not yet run on the console**. To check
there: FN opens and closes the retrorun menu in a Dreamcast game (retrorun32 and retrorun),
SELECT + R2 / L2 change the slot (message on screen), SELECT + L3 toggles fast-forward,
SELECT + R1 / L1 still save / load, SELECT + START still quits, the game's own L2 / R2 /
L3 keep working, and Saturn through retrorun (if used) still starts. `retrorun_log_level =
DEBUG` in `retrorun.cfg` prints `retrorun_hotkey_menu: 'F5'` at start.

Upstream: the change is written against tag 3.0.0; navy1978's master has moved on (3.2.4,
and since 2026-10-23 a `retrorun_mapping_button_hotkey` setting that only chooses the
modifier). A pull request upstream means porting the same six settings onto master once
the build has been tried on the console.
