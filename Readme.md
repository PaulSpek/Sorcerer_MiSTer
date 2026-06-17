# Exidy Sorcerer core for MiSTer

This is the MiSTer core of the Exidy Sorcerer computer.

- Thanks to gyurco for the original MiST core, on which this was ported

## Usage
This core is currently in development.

The core needs the Exidy Sorcerer boot ROM files to be available in the
`/media/fat/sorcerer` folder. If the core starts to a blank screen, check that
the ROM files were copied there by the downloader or copy them from the
`/media/fat/games/sorcerer` folder if they were installed there instead.

Extended BASIC can be loaded with the `BIN` option in the OSD. Reset the core
after loading the BASIC ROM to boot into BASIC mode.

## Loading Software

Tape, ADC, and UART loading are still under investigation. UART should be wired
correctly, but tape loading through UART is untested.

Forum testing has reported that 300 baud WAV loading through the audio/ADC path
does not currently appear to work. Known attempted monitor commands include:

- `SE T=1`
- `LOG`
- `LO`
- `LO <filename>`

## Known Issues

- 300 baud tape loading through ADC/audio input has not been confirmed working.
- UART tape loading has not been confirmed working.
- Some users have reported unstable HDMI character/font rendering after reset.
- Some 15 kHz CRT users have reported a dim or vertically shifted image.

