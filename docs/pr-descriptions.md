# Pull Request Description Templates

These are draft descriptions for splitting the current local work into reviewable upstream PRs.

## 48K RAM and Memory Map

### Summary

- Configure the core for 48K RAM.
- Reserve `BC00-BFFF` for the optional DiskBoot loader window.
- Keep normal RAM below `BC00` when the 48K map is selected.

### Test Notes

- Core boots to the monitor.
- BASIC/software BIN loading still works.
- DiskBoot can execute from `BC00` when loaded by a later disk-support PR.

### Documentation

- README documents the 48K RAM default and the `BC00-BFFF` reserved window.

## Timing and PAL/NTSC Defaults

### Summary

- Update PLL clocks to the tested timing build values.
- Run the CPU at standard speed by default.
- Wire OSD `TV Mode` to the core PAL/NTSC timing input.
- Bump the OSD config version because the menu default changed.

### Test Notes

- Quartus compile has no errors.
- Worst setup slack is non-negative.
- PAL mode is the default after OSD config reset.
- Previously timing-sensitive games and screen-refresh cases behave better than before.

### Documentation

- README documents the PAL/NTSC OSD option and PAL default.

## Sound Output

### Summary

- Drive mono core audio to both MiSTer audio channels.
- Enable MiSTer audio mixing for the core output.

### Test Notes

- Core still boots.
- Audio output is present on software that writes the Sorcerer audio/output latch.
- No regression to video or keyboard input.

### Documentation

- README notes mono audio output.

## BIN and PAC Quickload

### Summary

- Add MAME-style software BIN quickload support.
- Keep software BIN and PAC/cartridge loading as separate OSD entries.
- Reset after PAC load where required.
- Preserve autorun support for compatible BIN files.

### Test Notes

- BASIC BIN loading still works.
- Machine-code BIN loading still works.
- PAC/cartridge loading still works.
- Invalid or out-of-range BIN files fail without corrupting RAM outside the supported range.

### Documentation

- README documents `Load BIN` and `Load PAC`.
- PR notes should state that WAV cassette loading is not included.

## DiskBoot and Micropolis Disk Read Support

### Summary

- Add external `DiskBoot.dat` loading through the OSD.
- Keep DiskBoot out of the FPGA compile.
- Disable disk mount OSD options until DiskBoot has been loaded.
- Map DiskBoot at `BC00-BFFF`.
- Map the Micropolis controller at `BE00-BE03`.
- Add disk-image read support, including sectors crossing a 512-byte block boundary.

### Test Notes

- Load `DiskBoot.dat`.
- Mount `CPM disk1.dsk` as disk A.
- Run `GO BC00`.
- CP/M reaches the prompt.
- Disk mount OSD entries are disabled before DiskBoot load and enabled after DiskBoot load.

### Documentation

- README documents the DiskBoot load sequence.
- PR notes should explicitly say whether write-sector support is implemented. If not, call it read-only/boot-focused support.

## Development Tooling

### Summary

- Add simulator or helper scripts that are useful for maintaining the disk/quickload work.
- Keep local handoff files, ROM images, temporary source extracts, and rollback patches out of the PR.

### Test Notes

- Script usage is documented.
- Scripts run from the repository root.
- No private local paths are required unless clearly marked as examples.

### Documentation

- Add focused tool documentation only for scripts that are intended to remain in the repository.

## Future WAV Cassette Loading

WAV cassette loading should be a later dedicated PR with its own implementation, test files, and documentation. It should not be bundled with BIN/PAC quickload or DiskBoot support.
