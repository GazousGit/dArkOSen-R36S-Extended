# dArkOSen-R36S-Extended — hand-off context

Last updated 2026-10-11. Read this first when continuing the work in a new conversation. It records what exists, what state the repo and the device are in, the facts learned about dArkOSen that are not written anywhere else, and the plan for the next step (private repo, files baked into the image).

## 1. What this project is

- Fork of [djparentx/dArkOSen-R36S](https://github.com/djparentx/dArkOSen-R36S) at `GazousGit/dArkOSen-R36S-Extended` (a real GitHub fork). Owner: Nathan (GitHub `GazousGit`, device user `ark`).
- Goal: a random **boot video** on the R36S, plus automation: daily upstream-sync PR, automatic rebuild of every upstream release image with our additions, self-repair after OTA updates. Since then: extra tools (A/B swap, Dreamcast/N64 tuning, PPSSPP sync).
- Everything of ours is under `extended/` and `.github/workflows/`. Upstream files are untouched except `.gitattributes` (binary rules) and a 2-line banner at the top of `README.md`. `extended/README.md` is the user-facing documentation.
- Upstream has **zero pull requests and Issues disabled**; djparentx uploads files directly. Nothing was cherry-picked from forks or from dArkOSRE (decided: keep a pure mirror + our folder).

## 2. Repo state

| Where | State |
| --- | --- |
| `main` | PR #1 merged (boot video + build/sync automation). Release **`09302026-ext`** is public, built from commit 870a3bc by run 37931471516 (16 min). |
| branch `ext/tools`, **PR #2 open** | Boot video volume option; `extended/overlay/` with 4 tools; N64 preset baked into images; PPSSPP sync; confirm/back buttons follow ES; build rebuilds an existing release when `extended/` changes on `main` (tree hash in the release notes). 168 offline checks pass. **Merging PR #2 rebuilds `09302026-ext` automatically** (~16 min). |

Files: `extended/bootvideo/Boot Video Manager.sh` (v3, single source of truth, also contains the helper, the repair service and the ES menu), `extended/overlay/opt/system/Advanced/*.sh` (4 tools), `extended/build/build-image.sh` + `inject.sh`, `extended/tests/run-tests.sh`, `extended/bootvideos/` (videos to ship; empty), `.github/workflows/upstream-sync.yml`, `.github/workflows/build-image.yml`.

## 3. Device state (R36S, LAN 192.168.1.159, SSH `ark` / password `ark`, root Samba share)

- Running the `09302026-ext` image. Boot video works (7 videos in `/roms/bootvideos`), repair service enabled and healthy.
- Installed over SSH on 2026-10-11: Manager with the volume option, the 4 tools in `/opt/system/Advanced/`, N64 fast preset (38 `mupen64plus-*` lines in `retroarch-core-options.cfg`), Dreamcast fast preset in `retrorun.cfg`, PPSSPP per-game configs copied standalone → 2021 (301 files), and **OTA update 09302026b applied manually** (unzip over `/` + its script): custom 32-bit `libasound` 1.2.8, new `retrorun32`/`retroarch32`, marker `.dArkOSen-update09302026b`, `.VERSION` = `09302026b`.
- **Not yet on the device:** the confirm/back button fix (commit 3a8d85c). A WSL background job polls the device and installs the 5 files when it answers; otherwise copy `extended/bootvideo/Boot Video Manager.sh` → `/opt/system/System/` and the 4 tools → `/opt/system/Advanced/` (mode 755) and run `sudo "/opt/system/System/Boot Video Manager.sh" --repair`.
- User choices still open: boot video volume (Manager option 4), N64 core selection in ES (N64 > Advanced System Options > Emulator `retroarch`, Core `mupen64plus_next`), test of the presets in games.
- ES A/B: the user used dArkOSen's "Switch A/B buttons globally" (ES Advanced Settings, US/JP); `es_settings.cfg` currently has no `InvertButtons` line. Our ES-only tool is therefore unused.
- The SD card's EASYROMS partition shows as `G:\` on the PC when inserted (device offline then). Card: 109 GB, 32 GB used.

## 4. Facts about dArkOSen (from the real 09302026 image and the device)

- Image: p1 BOOT vfat 100 MiB, p2 ROOTFS **btrfs** 8 GiB (~300 MB free), p3 EASYROMS exFAT 100 MiB. First boot (`/boot/expandtoexfat.sh`) grows the root fs, **reformats EASYROMS**, extracts `/roms.tar`, installs fstab with `/roms`, reboots twice. Anything for `/roms` must be seeded from the root fs at boot (that is how shipped boot videos work: `/usr/share/dArkOSen-Extended/bootvideos` → `/roms/bootvideos`, once, marker `.seeded`).
- OTA: `/usr/local/bin/Update.sh` (launched from the ES menu "DOWNLOADS AND UPDATES", which the user could not find) downloads `dArkOSen-Update.sh` from `djparentx/dArkOSen-updates`; each update is a zip unzipped over `/` plus `/tmp/<date>.sh`. Updates can replace `emulationstation.sh` and `es_systems.cfg` (our repair service re-adds the hook/ES entry).
- **09302026 image has no sound in 32-bit emulators** (retrorun32, retroarch32: Dreamcast, Naomi, 32-bit cores) until 09302026b is applied.
- Dialog tools: `/opt/inttools/keys.gptk` maps SDL "a" = Esc, "b" = Enter; `/opt/inttools/gamecontrollerdb.txt` maps SDL "a" to physical A (`a:b1`). So in dArkOSen's own tools **B confirms, A quits**. Our tools follow ES's `InvertButtons` instead.
- ES A/B global switch = `/usr/local/bin/b_swap.sh` (flag `/var/cache/Switch_AB`); the ES part is one `InvertButtons` line in `/home/ark/.emulationstation/es_settings.cfg`; ES writes its settings on exit (edit only while ES is stopped).
- retrorun/retrorun32 read flycast core options from `/home/ark/.config/retrorun.cfg` (`reicast_*`); the shipped retrorun binary knows only the older `retrorun_*` keys (no `retrorun_frameskip`). dArkOS ships two conflicting `reicast_anisotropic_filtering` lines.
- RetroArch core `mupen64plus_next` ships with **no** core options (defaults: 640x480, FB emulation on, depth compare on). ES default N64 emulator is `retroarch32`/`parallel_n64`.
- PPSSPP: `/usr/local/bin/ppsspp.sh` re-points `/home/ark/.config/ppsspp` to `/roms/psp/ppsspp` (standalone) or `/roms/psp/ppsspp-2021`; per-game settings are `PSP/SYSTEM/<GAMEID>_ppsspp.ini` / `_controls.ini`.
- Saturn: `saturn.sh` runs `/opt/yabasanshiro/yabasanshiro -r 3 -i game` (`-r 3` = "Original", the lowest resolution mode; auto frame skip on by default; `-b saturn_bios.bin` for `standalone-bios`). No other performance switches exist. Alternative to compare: `retrorun32` + `yabasanshiro` core.
- ES themes live in `/roms/themes`; none of the bundled themes has a `videos` system folder except es-theme-switch (the Boot Videos system falls back to text).
- Console with the 22x11 font: 58x21 characters; `dialog` clamps oversized boxes (verified), no sizing bug.

## 5. BIOS audit of the user's card (G:\bios, 2026-10-11)

Checked against the firmware lists of every installed core and the standalone launchers; key hashes verified. Correct and complete for the systems with games on the card: Saturn (`saturn_bios.bin`, `sega_101.bin`, `mpr-17933.bin`), Dreamcast/Naomi/Atomiswave (`dc/dc_boot.bin`, `dc/dc_flash.bin`, `dc/naomi.zip`, `dc/awbios.zip`), GB/GBC/GBA, SNES coprocessors, Mega Drive/Mega-CD/SMS/GG, FDS, PCE-CD, Atari ST (`tos.img`), Lynx, 3DO, PC-FX, Intellivision, Odyssey2.

Gaps and oddities: `scph5501.bin` missing (needed only by DuckStation/Beetle PSX; PCSX-ReARMed works); `scph5502.bin` does not match the documented EU hash; `ecwolf.pk3` missing (required by ECWolf, one Wolf game on the card); DS BIOS files are named `.rom` and sit in `/roms/bios` while DraStic wants `nds_bios_arm7.bin`/`nds_bios_arm9.bin`/`nds_firmware.bin` in `/opt/drastic/system/`; `coleco.rom` should be `colecovision.rom` for Gearcoleco; `neogeo.zip` must sit next to the games or in `bios/fbneo/` for FBNeo; `update118.exe` is junk; `dc/DC - BIOS (All).bin` and `dc/DC - Flash (All).bin` are stray duplicates. Missing but irrelevant (no games): Amiga Kickstarts, Channel F, X68000, Palm, CD-i, SCV, 64DD IPL, `freej2me-plus-lr.jar`.

Sizes: `bios/` 87 MB total, of which PPSSPP 14 + scummvm 4 + mame 5 + mame2003-plus 1 are already shipped by dArkOS in `roms.tar`; the rest is ~63 MB (root files 28, dc 21, neocd 6, Machines 10, Databases 2). `bootvideos/` 4 MB, PPSSPP per-game configs 6 MB.

## 6. Next step (planned): private repo, files baked into the image

Intent: make the GitHub repo private, then ship the user's BIOS files (and possibly videos and PPSSPP per-game configs) inside the built image so a fresh card is complete after first boot.

Design that fits the existing mechanisms:
1. **Private repo**: Settings → General → Danger zone → Change visibility. Consequences: releases (including the existing `09302026-ext`) become visible only to the owner/collaborators; GitHub Actions minutes are metered on private repos (free plan: 2,000 min/month; a build is ~16 min, the daily check ~1 min); the public API reads used so far (workflow runs, check-run annotations) need the stored git credential token; workflows themselves need no change (`GITHUB_TOKEN`).
2. **Seed tree**: add `extended/seed/` laid out like `/roms` (e.g. `extended/seed/bios/...`, `extended/seed/psp/ppsspp/PSP/SYSTEM/...`). `inject.sh` copies it to `/usr/share/dArkOSen-Extended/seed/` on the root fs (budget: ~300 MB free; the BIOS pack minus the folders dArkOS already ships is ~63 MB). The Manager's repair service (`Seed_Videos`/`Seed_Overlay` pattern) copies files that do not exist yet into `/roms/...` once `/roms` is mounted, never overwriting, with a `.seeded` marker per top folder. Before adding the BIOS pack: add `scph5501.bin` and `ecwolf.pk3`, drop `update118.exe` and the two stray `dc/*(All).bin`, and do not include `PPSSPP/`, `scummvm/`, `mame*/` (shipped by dArkOS).
3. **Videos**: already supported via `extended/bootvideos/`; just add the 7 videos there (4 MB).
4. Keep the tests: a seed test like the existing shipped-videos test (roms not ready → nothing written; after `--repair` with roms mounted → files present, marker, no overwrite).
5. Note for the release notes: images containing BIOS files must never be published publicly; the private repo takes care of that.

## 7. How to work on this (practical)

- Windows file tools write CRLF; before running anything in WSL convert: `wsl -d Ubuntu -u root -e bash -c 'cd /mnt/d/ClaudeFolder/R36S-dArkOS-Fork/dArkOSen-R36S-Extended && sed -i "s/\r$//" <files>'`. Git normalizes on commit (`.gitattributes` `text=auto eol=lf`). Never `git add -A`; add paths.
- Tests: `wsl -d Ubuntu -u root -e bash -c 'cd /mnt/d/.../dArkOSen-R36S-Extended && bash extended/tests/run-tests.sh'` (168 checks; shellcheck, ffmpeg, btrfs-progs, 7z, jq, sshpass, dialog are installed in WSL).
- WSL scratch: `/root/darkosen-ext/` (`dl/` upstream 7z parts, `orig/` extracted 8.2 GB image, `work/` build scratch, `ota/` the 09302026b zip, `tools/actionlint`, `mnt-ro/` read-only mounts of the image for inspection).
- Local full build: `sudo bash extended/build/build-image.sh --img /root/darkosen-ext/orig/dArkOSen_R36_09302026.img --tag 09302026 --workdir /root/darkosen-ext/work --videos extended/bootvideos [--no-pack]` (copy the image first; the script renames it).
- Device: `sshpass -p ark ssh ark@192.168.1.159`; `ark` has passwordless sudo. Only reachable when the card is in the device and it is on.
- GitHub: the GitHub connector token reads but cannot create PRs; PRs are created with the token from Git Credential Manager (`git credential fill`), not printed. No `gh` CLI locally. Workflow runs/annotations: `api.github.com/repos/GazousGit/dArkOSen-R36S-Extended/actions/runs` and `.../check-runs/<job id>/annotations` (public today; need the token once private).
- Workflow behaviour: push to `main` or `ext/**` touching `extended/` runs the check; branch runs publish drafts or skip; `main` promotes drafts and rebuilds when the `extended/` tree hash changed; `workflow_dispatch` has `tag`, `force`, `draft`, `level`.
