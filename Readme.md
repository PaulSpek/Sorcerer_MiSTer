# Exidy Sorcerer core for MiSTer

This is the MiSTer core of the Exidy Sorcerer computer.

- Thanks to gyurco for the original MiST core, on which this was ported

## Usage

The core starts with the DreamDisk controller enabled and a 56K memory map. The OSD `Hardware` page can select:

- `FDC`: `DreamDisk`, `Micropolis`, or `None`
- `Memory`: `56K`, `48K`, or `32K`

DreamDisk is the default disk controller. Select `None` for cassette/PAC software that expects no disk hardware, or a smaller memory map for software that depends on the original memory layout.

### Video Timing

The OSD `TV Mode` option selects PAL or NTSC timing. PAL is the default.

### Software Loading

The OSD exposes these software loading options:

- `Load BIN` loads MAME-style Sorcerer software `.bin` files.
- `Load WAV` loads cassette WAV files by replaying decoded tape bytes through the Sorcerer UART.
- `Load PAC` loads cartridge/PAC ROM images.
- `Load Monitor` loads a replacement monitor ROM.

BASIC .bin programs need a BASIC PAC loaded first.

For WAV loading, use the normal Sorcerer tape commands first, then select `Load WAV` from the OSD. Use `LOG` for monitor/machine-code tapes and `CLOAD` from BASIC for BASIC tapes. The loader auto-detects 300 and 1200 baud where possible. Some marginal 300 baud recordings may still fail to decode.

### DreamDisk

DreamDisk is available by default. Mount disk images with:

- `Mount disk A`
- `Mount disk B`
- `Mount disk C`
- `Mount disk D`

The DreamDisk controller uses WD2793-compatible ports at `44h-47h` plus the DreamDisk control latch at `48h-4Bh`. DreamDisk images use 1024-byte sectors and support read and write sector operations.

### Micropolis CP/M Disk Boot

CP/M boot support uses the external `DiskBoot.dat` file. It is intentionally loaded from the OSD and is not built into the FPGA bitstream.

To boot a Micropolis CP/M disk:

1. Select `Micropolis` as the FDC hardware.
2. Select `Load DiskBoot` and load `DiskBoot.dat`.
3. Mount a disk image as disk A.
4. Run `GO BC00` from the Sorcerer monitor.

The Micropolis controller is mapped at `BE00-BE03`. `Load DiskBoot` is only available when Micropolis is selected.

Disk image mount options are disabled when FDC hardware is set to `None`. Micropolis exposes only disk A and disk B; DreamDisk exposes disks A through D.

### Audio

The core drives mono audio to both left and right MiSTer audio channels.

### Tape Loading

The cassette input path is wired through the Sorcerer UART for OSD WAV loading.
