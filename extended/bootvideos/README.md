# Shipped boot videos

Any `.mp4`, `.mkv`, `.webm` or `.gif` placed in this folder is shipped inside the images built by the *Build image* workflow. The build stores them in `/usr/share/dArkOSen-Extended/bootvideos/` on the root filesystem, and the self-repair service copies them into `/roms/bootvideos/` on the first regular boot (dArkOSen's first boot re-creates the EASYROMS partition, so they cannot be placed there directly). They are copied once; deleting one on the device does not bring it back.

Nothing here by default: the built images ship the tool enabled with an empty `bootvideos` folder, and the first video copied to `/roms/bootvideos/` on the SD card plays at the next boot.

Keep files small: the root filesystem of the image has about 300 MB free, and a 15 s clip at 640x480 is 2 to 5 MB. Only add videos you have the right to redistribute; this repository and its releases are public.
