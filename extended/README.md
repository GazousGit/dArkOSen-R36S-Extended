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
| Manage | *Options > System > Boot Video Manager*: on/off, random or one fixed video, sound, max length (5 to 60 s), converter (640x480 H.264 baseline + AAC), preview, repair, uninstall. |
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
| `/roms/bootvideos/` | Your videos (mp4, mkv, webm, gif). `disabled/` for videos that must not play, `.media/` thumbnails, `.originals/` kept by the converter, `gamelist.xml`. |
| `/usr/share/dArkOSen-Extended/bootvideos/` | Videos shipped with a built image (seeded into `/roms/bootvideos` at boot). Built images only. |
| `/etc/dArkOSen-Extended.release` | Build stamp. Built images only. |

Command line (as root): `--repair` re-attaches everything without the UI, `--install-root DIR` installs into a mounted image root, `--uninstall-root DIR` removes it again.

## Layout of this folder

```
extended/
  bootvideo/Boot Video Manager.sh   the tool (v3), single source of truth
  bootvideos/                       videos placed here are shipped inside the built images
  build/build-image.sh              download upstream release -> mount -> inject -> repack .7z
  build/inject.sh                   applies our additions to a mounted root filesystem
  tests/run-tests.sh                offline tests (Linux, root)
```

## Automation

**Upstream sync** (`.github/workflows/upstream-sync.yml`, daily 04:17 UTC and on demand). Fetches upstream `main`; when it moved, pushes the `upstream-sync` branch (our `main` with upstream merged in, or an exact copy of upstream when the merge conflicts) and opens or refreshes a pull request. Nothing merges on its own. Needs *Settings > Actions > General > Allow GitHub Actions to create and approve pull requests*.

**Build image** (`.github/workflows/build-image.yml`, daily 05:23 UTC, on pushes that touch `extended/`, and on demand).

1. Looks up the latest upstream release tag (or the one given) and checks whether a `<tag>-ext` release exists here.
2. If not, downloads the upstream `.7z` parts, extracts the `.img` (about 8.2 GB), attaches it with `losetup`, mounts the root partition (btrfs), runs `inject.sh`, verifies the filesystem with `btrfs check`, repacks the image as a split `.7z` (parts under 2 GB) and publishes a release with SHA-256 sums and release notes. The boot (FAT) and EASYROMS (exFAT) partitions are not touched. Roughly 30 to 60 minutes.
3. Builds started from any branch other than `main` are published as **drafts**. When the branch is merged, the push to `main` promotes the draft to a published release instead of rebuilding.

Manual run options: `tag`, `force` (delete and rebuild), `draft`, `level` (7z compression level).

GitHub disables scheduled workflows after 60 days without repository activity; a merged sync PR counts as activity.

## What the image looks like

Release 09302026: partition 1 `BOOT` (FAT, 100 MiB, kernel, dtbs, `firstboot.sh`), partition 2 `ROOTFS` (btrfs, 8 GiB, about 300 MB free), partition 3 `EASYROMS` (exFAT, 100 MiB). On first boot `/boot/expandtoexfat.sh` grows the root filesystem, re-creates EASYROMS with `mkfs.exfat`, extracts `/roms.tar` and the bundled themes into it, installs an fstab with `/roms` and reboots. Themes live in `/roms/themes` (`/etc/emulationstation/themes` is a symlink).

## Local build (WSL or any Linux, as root)

```bash
sudo apt-get install -y p7zip-full jq btrfs-progs
sudo bash extended/build/build-image.sh --tag 09302026 --workdir /tmp/darkosen --videos extended/bootvideos
# or, with an already extracted image:
sudo bash extended/build/build-image.sh --img /path/dArkOSen_R36_09302026.img --tag 09302026 --no-pack
```

Tests: `sudo bash extended/tests/run-tests.sh` (needs bash, awk, python3; ffmpeg and shellcheck optional).

## Working on this fork from Windows

The upstream `.gitattributes` marked every file as text, so a Windows clone showed dozens of binaries as modified and would have corrupted them on commit. This fork's `.gitattributes` uses `text=auto` and marks the binary types explicitly. Never run `git add -A` on a checkout that still shows those files as modified; add paths explicitly. Scripts must keep LF line endings (the Windows file tools write CRLF; `git` normalizes on commit, but tests run from the working tree in WSL do not).
