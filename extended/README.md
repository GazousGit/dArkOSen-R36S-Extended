# dArkOSen-R36S-Extended

This repository is a fork of [djparentx/dArkOSen-R36S](https://github.com/djparentx/dArkOSen-R36S) that adds **one feature: a boot video**. Everything of ours lives in this `extended/` folder and in `.github/workflows/`; the rest of the tree is upstream, kept in sync by a daily pull request.

- **Releases** of this fork are the official dArkOSen images with the boot video tool pre-installed, rebuilt automatically for every upstream release and tagged `<upstream tag>-ext` (for example `09302026-ext`). The device keeps receiving djparentx's OTA updates.
- **Already on dArkOSen?** You only need one file: copy `extended/bootvideo/Boot Video Manager.sh` to `/opt/system/System/` on the device and run it once from *Options > System*. It installs everything else.

dArkOSen, dArkOS and ArkOS are the work of their respective authors (MIT). Please report emulator or system problems upstream; boot video problems [here](../../../issues).

## The boot video

| What | How |
| --- | --- |
| Playback | Before EmulationStation starts, a random video from `/roms/bootvideos` (or `/roms2/bootvideos` when roms are on SD2) plays full screen with `ffplay`, the same player dArkOSen uses for the game loading video. Once per boot, not when ES restarts, not over SSH, not in the BaRT recovery menu. |
| Skip | A, B, X, Y or Start. Volume keys and Fn combinations are left to `ogage`, so volume and brightness keep working during the video and never skip it. |
| Manage | *Options > System > Boot Video Manager*: on/off, random or one fixed video, which videos play (select all, unselect all, search with the on-screen keyboard, tick from the list, playlists saved in `bootvideos/.playlists/<name>.txt` that replace the list when applied; X ticks), sound, volume (mixer level used only during the video, the previous level comes back afterwards), max length (5 to 60 s), converter (640x480 H.264 baseline + AAC), preview, repair, uninstall. |
| EmulationStation | A **Boot Videos** system lists the videos with thumbnails and video previews. Press A on one to preview it or to enable/disable it (disabled videos move to `bootvideos/disabled`). |
| Self-repair | `bootvideo-repair.service` runs before ES at every boot (after `/roms` is mounted) and re-attaches the hook and the ES entry if an OTA update replaced `emulationstation.sh` or `es_systems.cfg`. It also creates `/roms/bootvideos` and copies videos shipped with a built image into it, once. |

Files on the device:

| Path | Role |
| --- | --- |
| `/opt/system/System/Boot Video Manager.sh` | The tool. The only file you need to copy by hand. |
| `/usr/local/bin/bootvideo.sh` | Helper written by the tool: boot playback, ES menu, preview, gamelist rebuild. |
| `/usr/local/bin/bootvideo-repair`, `/etc/systemd/system/bootvideo-repair.service` | Self-repair at boot (`Before=emulationstation.service`, `RequiresMountsFor=/roms`). |
| `/home/ark/.config/bootvideo.conf` | Settings: `ENABLED SOUND MAXLEN MODE FILE DIR ES_ENTRY`. |
| `/usr/bin/emulationstation/emulationstation.sh` | One added line tagged `# bootvideo-hook`; backup `.pre-bootvideo`. |
| `/etc/emulationstation/es_systems.cfg` | Added `bootvideos` system; backup `.pre-bootvideo`. |
| `/roms/bootvideos/` | Your videos (mp4, mkv, webm, gif), directly in the folder (other subfolders are not played). `disabled/` for videos that must not play, `.playlists/` saved playlists (one file name per line), `.media/` thumbnails, `.originals/` kept by the converter, `gamelist.xml`. |
| `/usr/share/dArkOSen-Extended/bootvideos/` | Videos shipped with a built image (seeded into `/roms/bootvideos` at boot). Built images only. |
| `/etc/dArkOSen-Extended.release` | Build stamp. Built images only. |

Command line (as root): `--repair` re-attaches everything without the UI, `--install-root DIR` installs into a mounted image root, `--uninstall-root DIR` removes it again.

## Extra tools (overlay)

`extended/overlay/` mirrors the device tree; the build copies it into the image, keeps a copy in `/usr/share/dArkOSen-Extended/overlay/`, and the self-repair service puts back any file an OTA update removed. On an existing device, copy the scripts by hand to the same paths.

In dArkOSen's own dialog tools (Boot Splash Manager, R36 Boot Volume) **B confirms and A goes back**, because `/opt/inttools/keys.gptk` maps SDL "a" to Esc and the SDL mapping makes "a" the physical A button. Our menus instead follow EmulationStation: A confirms unless ES has `InvertButtons` set (dArkOSen's "Switch A/B globally" in JP mode), in which case B confirms, as in ES.

| Tool (Options > Advanced) | What it does |
| --- | --- |
| **Swap A-B in EmulationStation only** | Flips ES's `InvertButtons` setting and restarts ES. dArkOSen's own "Switch A/B Globally" changes RetroArch, PortMaster, Kodi and 351Files at the same time; this one leaves the emulators alone. |
| **Dreamcast Tuning (retrorun)** | Edits the `reicast_*` core options in `/home/ark/.config/retrorun.cfg` that retrorun and retrorun32 read (backup `retrorun.cfg.pre-ext`, restore option). The fast preset adds what RetroArch32 already uses on this hardware and dArkOS's retrorun config lacks: internal resolution 320x240, synchronous rendering off, VGA cable, single `anisotropic_filtering = off` line (dArkOS ships two conflicting ones), fog and DSP off. Toggles for resolution, sync, frame skip, fog, DSP and the FPS counter. |
| **N64 Tuning (mupen64plus-next)** | The menu edits RetroArch core options only; it never changes which emulator a game uses (that stays the ES system default and the per-game emulator/core in `gamelist.xml`). **Built images make `retroarch` / `mupen64plus_next` the N64 default in ES** (two lines in `es_settings.cfg`, written by the tool's `--es-default`) instead of dArkOSen's `retroarch32` / `parallel_n64`: the per-game list of [R36S-Game-Compatibility-Lists](https://github.com/GazousGit/R36S-Game-Compatibility-Lists) tags only the games that run better elsewhere. On an existing device set it in ES (N64 > Advanced System Options). dArkOS ships no options for the RetroArch core `mupen64plus_next`, so it runs at 640x480 with a single-threaded renderer. The preset writes the GLideN64 settings of the [ArkOS wiki](https://github.com/christianhaitian/arkos/wiki/ArkOS-Emulators-and-Ports-information#nintendo-64) into `/home/ark/.config/retroarch/retroarch-core-options.cfg`: 320x240, threaded renderer, hybrid filter off, color buffer to RDRAM off, overscan off, and the rest as the core ships it (framebuffer and LOD emulation on, depth buffer to RDRAM "Software"). The older `mupen64plus` core reads the same option names for resolution, framebuffer emulation and buffer copies, so it follows these settings too. Toggles for resolution, framebuffer emulation, threaded renderer, frame duping, depth compare, LOD and the RDP plugin; restore puts back exactly the previous `mupen64plus-*` lines. **Built images ship this preset** (the build runs the tool's `--wiki`). *Per-game fixes* writes RetroArch per-game option files (`config/<core name>/<rom name>.opt`, used instead of the global options) for the games listed in the script's `PER_GAME` table; for now Pokemon Stadium on the 32-bit ParaLLEl core (glide64 plugin, medium accuracy, 640x480). |
| **PPSSPP Sync standalone and 2021** | dArkOS keeps `standalone` (`/roms/psp/ppsspp/`) and `standalone-2021` (`/roms/psp/ppsspp-2021/`) apart, so per-game settings (`PSP/SYSTEM/<GAMEID>_ppsspp.ini`, `_controls.ini`) made for one build are invisible to the other. Copies them in either direction (targets kept as `.bak`), and can optionally point the 2021 build at the standalone memory stick (`MemStickDirectory`) so saves, states and per-game settings are shared; reversible. |

### Shortcuts and the reminder before a game

Every emulator has its own way to quit or to open its menu. *Options > Shortcuts* lists the key combinations, one page each: system keys (brightness, volume, shutdown), RetroArch, retrorun, the standalone N64 emulator, and the standalone emulators dArkOSen closes with Select + Start.

The same pages feed a **reminder shown before each game**: `perfmax`, the script dArkOSen runs before every launch, gets one added line (tagged `# shortcuts-hook`, re-added by the self-repair service after an OTA update) that calls `/usr/local/bin/launch-reminder`. It reads which emulator is about to start from the launch command and prints that emulator's page in a large font, with "Press A to continue" at the bottom: the game starts after 10 seconds, or as soon as A (or B, or Start) is pressed. The Shortcuts tool turns the reminder on or off and sets the time (3 to 30 s); settings are in `/home/ark/.config/shortcuts.conf`. A device that already has that file keeps its previous time until it is changed in the tool.

The pages are plain text files in `/usr/share/dArkOSen-Extended/shortcuts/`. A file of the same name in `/roms/shortcuts/` replaces the built-in one, so they can be corrected from a PC; the tool's *Copy the texts* option puts editable copies there, with a `README.txt` on the naming rules (`<launcher>.<emulator>.txt`, `retroarch.txt`, `retrorun.txt`, `<launcher>.txt`, `standalone.txt`). No matching page, no reminder. The built-in texts were taken from the configuration files of the 09302026 image and from retrorun's documentation, not measured on a device: check them against yours.

### Model selector: two broken entries, and how to pick yours

The model selector (`SELECT MODEL.exe` on the BOOT partition) copies one folder of `BOOT/dtb/` (a `boot.ini` and the device trees) to the root of the partition. In the 09302026 image two folders name a kernel device tree they do not contain: **`r36s/R36S-V12 2023-08-18 Panel 4`** loads `rk3326-r36h-linux.dtb` and `r36s/HL-R46H-V22 2026-03-12` loads `rk3326-r45h-linux.dtb`. The bootloader then starts the kernel with its own minimal device tree, which has the screen but no controller: the picture and sound are fine, EmulationStation asks to configure a controller and only the power button answers. Built images repair this (`extended/build/fix-boot.sh`: when a folder's `boot.ini` names a missing device tree and the folder holds exactly one `*-linux.dtb`, `boot.ini` is pointed at it). On a card flashed with the official image, open `boot.ini` on the BOOT partition after selecting Panel 4 and replace `rk3326-r36h-linux.dtb` with `rk3326-r36s-linux.dtb`.

To find the right entry for a unit, compare the device tree of its factory card (`rk3326-rg351mp-linux.dtb` on the stock BOOT partition) with the selector's: the screen is the `panel@0` node (init sequence and timings), the controls the `odroidgo3-joypad` node. Examples from the factory cards checked so far: "R36S-V12 2023-08-18" boards with the factory model string "Game Console R35S/R36S fix by lxc" and a 29 MHz panel match **`R36S-V21 2024-12-18 2547`** exactly (screen and controls); an "R36S-V21 2024-12-18" board with the 58 MHz panel matches **`R36S-V21 2024-12-18 2544`** (identical to `R36S-V22 2024-12-18 2545` and `2548`).

### Known upstream issue: no sound in 32-bit emulators on the 09302026 image

The 09302026 image ships Debian's 32-bit ALSA library, which produces no audio on this kernel, so retrorun32 and retroarch32 (Dreamcast, Naomi, N64 32-bit cores and others) are silent. djparentx fixed it in the **09302026b** OTA update (custom 32-bit `libasound` 1.2.8 plus new retrorun/retrorun32/retroarch32 binaries), which the image does not include. Run *Options > System > Update-dArkOSen* once (Wi-Fi) after flashing; the Dreamcast tool's audio check tells you whether it is installed. The offline package is on the [dArkOSen-updates 09302026b release](https://github.com/djparentx/dArkOSen-updates/releases/tag/09302026b).

## Personal files in your own image (local builds)

`extended/roms/` is laid out like `/roms` on the device (`bios/`, `bootvideos/`, `psp/...`). A local build run with `--roms extended/roms` appends its files to the image's `/roms.tar`, the archive that dArkOSen's first boot extracts into the freshly formatted EASYROMS partition, so a newly flashed card comes up with your BIOS files, videos and settings already in place. Nothing in that folder is committed (it is git-ignored and the build workflow refuses to run if a file from it is ever tracked), and the release images of this repository never contain such files. Details and the build command are in [roms/README.md](roms/README.md).

## Layout of this folder

```
extended/
  bootvideo/Boot Video Manager.sh   the tool (v3), single source of truth
  bootvideos/                       videos placed here are shipped inside the built images
  roms/                             personal files for local builds, laid out like /roms (never committed)
  overlay/                          extra tools, laid out like the device tree (copied into the image)
  build/build-image.sh              download upstream release -> mount -> inject -> repack .7z
  build/inject.sh                   applies our additions to a mounted root filesystem
  build/fix-boot.sh                 repairs model selector entries on the BOOT partition
  tests/run-tests.sh                offline tests (Linux, root)
```

## Automation

**Upstream sync** (`.github/workflows/upstream-sync.yml`, daily 04:17 UTC and on demand). Fetches upstream `main`; when it moved, pushes the `upstream-sync` branch (our `main` with upstream merged in, or an exact copy of upstream when the merge conflicts) and opens or refreshes a pull request. Nothing merges on its own. Needs *Settings > Actions > General > Allow GitHub Actions to create and approve pull requests*.

**Build image** (`.github/workflows/build-image.yml`, daily 05:23 UTC, on pushes that touch `extended/`, and on demand).

1. Looks up the latest upstream release tag (or the one given) and checks whether a `<tag>-ext` release exists here.
2. If not, downloads the upstream `.7z` parts, extracts the `.img` (about 8.2 GB), attaches it with `losetup`, mounts the root partition (btrfs), runs `inject.sh`, verifies the filesystem with `btrfs check`, repacks the image as a split `.7z` (parts under 2 GB) and publishes a release with SHA-256 sums and release notes. The EASYROMS (exFAT) partition is not touched. On the boot (FAT) partition only broken model selector entries are repaired (see below), then the partition is checked with `fsck.vfat`. Roughly 30 to 60 minutes.
3. Builds started from any branch other than `main` are published as **drafts**. When the branch is merged, the push to `main` promotes the draft to a published release instead of rebuilding.

Manual run options: `tag`, `force` (delete and rebuild), `draft`, `level` (7z compression level).

GitHub disables scheduled workflows after 60 days without repository activity; a merged sync PR counts as activity.

## What the image looks like

Release 09302026: partition 1 `BOOT` (FAT, 100 MiB, kernel, dtbs, `firstboot.sh`), partition 2 `ROOTFS` (btrfs, 8 GiB, about 300 MB free), partition 3 `EASYROMS` (exFAT, 100 MiB). On first boot `/boot/expandtoexfat.sh` grows the root filesystem, re-creates EASYROMS with `mkfs.exfat`, extracts `/roms.tar` and the bundled themes into it, installs an fstab with `/roms` and reboots. Themes live in `/roms/themes` (`/etc/emulationstation/themes` is a symlink).

## Local build (WSL or any Linux, as root)

```bash
sudo apt-get install -y p7zip-full jq btrfs-progs
sudo bash extended/build/build-image.sh --tag 09302026 --workdir /tmp/darkosen --videos extended/bootvideos
# or, with an already extracted image (the script moves it, so give it a copy):
sudo bash extended/build/build-image.sh --img /path/dArkOSen_R36_09302026.img --tag 09302026 --no-pack
# add --roms extended/roms to include your personal files (see roms/README.md)
```

Tests: `sudo bash extended/tests/run-tests.sh` (needs bash, awk, python3; ffmpeg and shellcheck optional).

## Working on this fork from Windows

The upstream `.gitattributes` marked every file as text, so a Windows clone showed dozens of binaries as modified and would have corrupted them on commit. This fork's `.gitattributes` uses `text=auto` and marks the binary types explicitly. Never run `git add -A` on a checkout that still shows those files as modified; add paths explicitly. Scripts must keep LF line endings (the Windows file tools write CRLF; `git` normalizes on commit, but tests run from the working tree in WSL do not).
