Shortcut pages (dArkOSen Extended)

Each .txt file here is one page. The first line is the title; lines starting with # are
notes and are not shown. Keep the other lines under 38 characters: the reminder before a
game uses a large font, 40 columns wide, and shows the title plus 11 lines at most.

On the reminder screen the words A, B, X and Y (on their own) take the colours of the
R36S buttons, and UP, DOWN, LEFT, RIGHT become arrows. Write the words; the screen does
the rest.

Where the pages are read from
  /roms/shortcuts/                           yours, on the EASYROMS partition
  /usr/share/dArkOSen-Extended/shortcuts/    built-in
A file in /roms/shortcuts replaces the built-in one of the same name.

Which page is shown before a game (first one found)
  <launcher>.<emulator>.txt       n64.standalone-Rice.txt, drastic.drastic.txt,
                                  dreamcast.standalone-Flycast.txt,
                                  ppsspp.standalone-2021.txt
  retroarch.txt, retrorun.txt     every system run by RetroArch or retrorun
  <launcher>.txt                  n64.txt, duckstation-standalone.txt, ppsspp.txt,
                                  saturn.txt
  standalone.txt                  emulators that dArkOSen closes with SELECT + START
The launcher is the script in the system's launch command: /usr/local/bin/n64.sh is "n64".
No matching file: nothing is shown. system.txt and emulationstation.txt only appear in
Options > Shortcuts.

Hotkey layout: Options > Shortcuts switches the emulators between the "universal"
combinations and dArkOSen's own. While dArkOSen's are active, <key>.darkosen.txt is
shown instead of <key>.txt when it exists.

Options > Shortcuts also turns the reminder on or off and sets how long it stays on screen.
