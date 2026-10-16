# Personal files for the roms partition (local builds only)

Files placed in this folder end up on the EASYROMS partition of an image you build yourself, so a freshly flashed card already has your BIOS files, boot videos or emulator settings after the first boot.

**Nothing in this folder is committed.** The repository is public and a fork cannot be made private, so the `.gitignore` here ignores everything except this README, and the *Build image* workflow refuses to run if a file from this folder is ever tracked. The images published in the releases of this repository never contain these files. An image built with them is for your own cards: do not publish or share it.

## Layout

Lay the folder out like `/roms` on the device:

```
extended/roms/
  bios/scph1001.bin            ->  /roms/bios/scph1001.bin
  bios/dc/dc_boot.bin          ->  /roms/bios/dc/dc_boot.bin
  bootvideos/Intro.mp4         ->  /roms/bootvideos/Intro.mp4
  psp/ppsspp/PSP/SYSTEM/...    ->  /roms/psp/ppsspp/PSP/SYSTEM/...
  themes/es-theme-nes-box/...  ->  /roms/themes/es-theme-nes-box/...
  es_settings.cfg              ->  EmulationStation settings (see below)
```

Only files inside a top folder are taken; files next to the folders (this README) are not, except `es_settings.cfg`.

- **Themes** (`themes/<name>/`) go to the image's `/tempthemes`, the folder dArkOSen keeps its own themes in: the first boot copies it into `/roms/themes` and deletes it. A theme dArkOSen ships under the same name is kept and yours is skipped. (10152026 dropped `es-simple-theme`, `es-theme-nes-box` and `es-theme-retrooz`, which 09302026 had; copies of those can go here.)
- **`es_settings.cfg`**: lines in EmulationStation's own format, one per setting, for example `<string name="GamelistViewStyle" value="video" />`. Each line replaces the image's setting of the same name or is added; other lines (comments) are ignored. The names are the ones in `/home/ark/.emulationstation/es_settings.cfg` on a device (`GamelistViewStyle`: automatic, basic, detailed, video, grid; `FolderViewMode`: always, never, having multiple games; dArkOSen's EmulationStation has no per-system folder setting).

## How it gets onto the card

dArkOSen's first boot formats EASYROMS and extracts `/roms.tar` from the root filesystem into it. `build-image.sh --roms extended/roms` appends your files to that archive, so the first boot itself puts them in place; nothing of ours runs for it. A file that dArkOSen already ships at the same path is kept and yours is skipped. The 09302026 image ships no BIOS files. The 09302026 first boot deleted `roms.tar` afterwards; since 10152026 it stays on the root filesystem (*Switch to SD2 for Roms* reuses it), which the first boot grows to about 11 GB anyway.

The archive and `/tempthemes` live on the root filesystem, which has 319 MB free in the 09302026 image but only 95 MB in 10152026. The build writes with the compression dArkOSen's own `fstab` uses (zlib), so the files take less room than their size (83 MB of BIOS files, videos and settings take about 55 MB). When they would leave less than 32 MB free, the build first makes the root partition bigger by their size (`extended/build/grow-root.sh`, in steps of 64 MiB; EASYROMS, which the first boot re-creates, moves along), so the image file gets that much bigger. Keep it to BIOS files, videos, themes and settings, not games.

## Build

In WSL or on any Linux, as root, from the repository root (the script moves the image it is given, so work on a copy):

```bash
cp /path/dArkOSen_R36_09302026.img /tmp/work.img
sudo bash extended/build/build-image.sh --img /tmp/work.img --tag 09302026 \
    --workdir /tmp/darkosen --videos extended/bootvideos --roms extended/roms --no-pack
```

The result is `/tmp/darkosen/img/dArkOSen-Extended_R36_09302026.img`, ready to flash. Without `--img` the script downloads the upstream release first.
