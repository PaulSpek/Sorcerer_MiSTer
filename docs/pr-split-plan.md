# Pull Request Split Plan

This document describes the intended upstream PR split for the current Sorcerer MiSTer work. It is a preparation aid, not a replacement for focused commit history.

## Baseline

Use `upstream/master` from `JasonA-dev/Sorcerer_MiSTer` as the base branch.

The merged upstream baseline already includes PR #3, `Drive full-scale monochrome video output`. Do not duplicate that work in new PRs.

## Recommended PRs

### 1. 48K RAM and Memory Map

Scope:

- Select 48K RAM in the top-level core.
- Define the top of general RAM as `BC00`.
- Reserve `BC00-BFFF` for the DiskBoot window when DiskBoot is loaded.

Documentation:

- README should mention 48K RAM.
- README should mention that `BC00-BFFF` is reserved for DiskBoot.

Notes:

- This can be its own small PR.
- If reviewers prefer fewer PRs, it can be the first commit in the DiskBoot/Micropolis PR because DiskBoot depends on the reserved window.

### 2. Timing and PAL/NTSC Defaults

Scope:

- Use the updated PLL clocks.
- Run the CPU at standard speed by default.
- Wire the OSD TV mode to the core PAL input.
- Bump the OSD config version for the incompatible menu default change.

Documentation:

- README should mention the PAL/NTSC option and PAL default.

Notes:

- Keep this PR independent from disk and quickload work.
- Include Quartus timing result in the PR description.

### 3. Sound Output

Scope:

- Wire the core audio output to MiSTer left/right audio channels.
- Keep mono audio mixed to both channels.

Documentation:

- README can cover this with a short note.

Notes:

- This should be a separate small PR unless it turns out to depend on a larger I/O decode change.

### 4. BIN and PAC Quickload

Scope:

- Support MAME-style software BIN quickload.
- Keep PAC/cartridge loading separate from software BIN loading.
- Reset after PAC load when required.
- Preserve the T80 direct-register path only if needed for autorun behavior.

Documentation:

- README should document `Load BIN` and `Load PAC`.
- PR description should state what BIN format is supported and what is intentionally not supported.

Notes:

- This likely updates or replaces the existing draft quickload PR.
- Keep WAV/cassette work out of this PR.

### 5. DiskBoot and Micropolis Disk Read Support

Scope:

- Add OSD `Load DiskBoot`.
- Keep DiskBoot as an external `DiskBoot.dat` file, not a compiled-in ROM.
- Disable disk mount options until DiskBoot has been loaded.
- Add Micropolis controller decode at `BE00-BE03`.
- Add disk image read path and second-block sector buffering.
- Support the tested CP/M boot path through `GO BC00`.

Documentation:

- README should document the CP/M boot sequence.
- README should state that `DiskBoot.dat` is external and loaded from the OSD.
- PR description should explicitly say write-sector support is not complete if that remains true.

Notes:

- This is the highest-risk PR and should come after memory-map and timing changes.
- Do not reintroduce old diagnostic writes or the rejected compiled-in DiskBoot approach.

### 6. Development Tooling and Investigation Notes

Scope:

- Optional simulator scripts.
- Optional remote build/transfer scripts.
- Optional investigation docs.

Documentation:

- Keep end-user documentation in README.
- Keep long debugging history out of upstream unless the maintainer asks for it.

Notes:

- Exclude local artifacts such as temporary MAME source extracts, ROM images, handoff folders, and rollback patches.

## Separate Future Work

### WAV Cassette Loading

WAV loading should remain separate from the current PR set. It needs its own implementation, test files, format assumptions, and user documentation.

## Files to Avoid Including

The following are local/debug artifacts unless intentionally promoted:

- `.tmp-*`
- `.tmp_*`
- `codex_faster_pc_handoff/`
- `forum_extract.txt`
- `roms/`
- `sorcerer_disk_wip_rollback_20260625.patch`

`Sorcerer.qsf` should be reviewed carefully before inclusion because local Quartus version metadata changes are usually noise.
