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
```

Only files inside a top folder are taken; files next to the folders (this README) are not.

## How it gets onto the card

dArkOSen's first boot formats EASYROMS and extracts `/roms.tar` from the root filesystem into it. `build-image.sh --roms extended/roms` appends your files to that archive, so the first boot itself puts them in place; nothing of ours runs for it and nothing stays behind on the root filesystem (the first boot deletes `roms.tar`). A file that dArkOSen already ships at the same path is kept and yours is skipped. The 09302026 image ships no BIOS files.

The archive lives on the root filesystem, which has 319 MB free in the 09302026 image but only 95 MB in 10152026. The build writes with the compression dArkOSen's own `fstab` uses (zlib), so the files take less room than their size (83 MB of BIOS files, videos and settings take about 55 MB), and it stops if less than 32 MB would remain. That is room for BIOS files, short videos and settings, not for games.

## Build

In WSL or on any Linux, as root, from the repository root (the script moves the image it is given, so work on a copy):

```bash
cp /path/dArkOSen_R36_09302026.img /tmp/work.img
sudo bash extended/build/build-image.sh --img /tmp/work.img --tag 09302026 \
    --workdir /tmp/darkosen --videos extended/bootvideos --roms extended/roms --no-pack
```

The result is `/tmp/darkosen/img/dArkOSen-Extended_R36_09302026.img`, ready to flash. Without `--img` the script downloads the upstream release first.
