# Exidy Sorcerer core for MiSTer

This is the MiSTer core of the Exidy Sorcerer computer.

- Thanks to gyurco for the original MiST core, on which this was ported

## Usage

The core starts with 48K RAM enabled. The `BC00-BFFF` area is reserved for the optional DiskBoot loader when it has been loaded from the OSD.

### Video Timing

The OSD `TV Mode` option selects PAL or NTSC timing. PAL is the default.

### Software Loading

The OSD exposes these software loading options:

- `Load BIN` loads MAME-style Sorcerer software `.bin` files.
- `Load WAV` loads cassette WAV files by replaying decoded tape bytes through the Sorcerer UART.
- `Load PAC` loads cartridge/PAC ROM images.

BASIC .bin programs need a BASIC PAC loaded first.

For WAV loading, use the normal Sorcerer tape commands first, then select `Load WAV` from the OSD. Use `LOG` for monitor/machine-code tapes and `CLOAD` from BASIC for BASIC tapes. The loader auto-detects 300 and 1200 baud where possible. Some marginal 300 baud recordings may still fail to decode.

### CP/M Disk Boot

CP/M boot support uses the external `DiskBoot.dat` file. It is intentionally loaded from the OSD and is not built into the FPGA bitstream.

To boot a Micropolis CP/M disk:

1. Select `Load DiskBoot` and load `DiskBoot.dat`.
2. Mount a disk image as disk A.
3. Run `GO BC00` from the Sorcerer monitor.

Disk image mount options are disabled in the OSD until `DiskBoot.dat` has been loaded.

The DiskBoot loader is mapped at `BC00-BFFF`. The Micropolis controller is mapped at `BE00-BE03`.

### Audio

The core drives mono audio to both left and right MiSTer audio channels.

### Tape Loading

The cassette input path is wired through the Sorcerer UART for OSD WAV loading.

