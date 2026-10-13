Shortcut pages (dArkOSen Extended)

Each .txt file here is one page. The first line is the title; lines starting with # are
notes and are not shown. Keep the other lines under 38 characters: the reminder before a
game uses a large font, 40 columns wide.

Where the pages are read from
  /roms/shortcuts/                           yours, on the EASYROMS partition
  /usr/share/dArkOSen-Extended/shortcuts/    built-in
A file in /roms/shortcuts replaces the built-in one of the same name.

Which page is shown before a game (first one found)
  <launcher>.<emulator>.txt       n64.standalone-Rice.txt
  retroarch.txt, retrorun.txt     every system run by RetroArch or retrorun
  <launcher>.txt                  n64.txt, ppsspp.txt, drastic.txt, saturn.txt, dreamcast.txt
  standalone.txt                  emulators that dArkOSen closes with SELECT + START
The launcher is the script in the system's launch command: /usr/local/bin/n64.sh is "n64".
No matching file: nothing is shown. system.txt only appears in Options > Shortcuts.

Options > Shortcuts turns the reminder on or off and sets how long it stays on screen.
