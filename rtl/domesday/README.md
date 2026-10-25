# Domesday RTL integration

This directory is the boundary between the working BeebFpga MiSTer core and
the LaserDisc implementation.

## Phase 1: mounted-media bridge

`domesday_bridge.sv` owns MiSTer virtual disk slot 3. It reads sector zero
through the standard `hps_io` block interface and validates either a 64-byte
Pi1MHz PVF1 header or the complete 512-byte DDV1 JPEG/PCM-cache header. For a
valid DDV it then reads sector one, decodes the first 16-byte 64-bit index
entry, and bounds-checks its JPEG address and byte count against the mounted
file. The OSD mounts `.DDV` playback-cache media; the optional status LED
lights after the header passes validation. Video records are not streamed or
decoded yet, so BBC video and audio remain unchanged.

`domesday_vfs_media.sv` owns slot 4, reserved for a separate read-only
`scsi0.dat` LV-ROM volume. It provides a one-sector (512-byte) cache to the
AIV target, which presents the volume as 256-byte SCSI blocks. The target at
`&FC40-&FC43` implements discovery plus read-only `INQUIRY`, `TEST UNIT
READY`, `REQUEST SENSE`, `MODE SENSE(6)`, `START/STOP`, `READ CAPACITY(10)`,
`READ(6)` and `READ(10)` phases. `READ CAPACITY` reports 256-byte logical
blocks, matching the VFS/LV-ROM protocol. Its AIV bus front end also models
the per-byte REQ/ACK edge (including a brief REQ release) required by VFS.
The BBC core supplies an explicit 1 MHz transaction strobe, so the target
handles each held 6502 bus access once rather than once per FPGA clock.
A VFS volume must never be mounted as a floppy.

The third-party Pi1MHz VFS ROM is packed into fixed Master sideways-ROM slot
8 (the otherwise unused slot) in `roms/rom.mif`. Regenerate that image with
`tools/pack_vfs_rom.py` and a locally supplied, 16 KiB `VFS.rom`. The ROM
remains third-party Acorn software; its provenance is documented in the
Pi1MHz credits.

## Planned phases

1. Generalise the verified frame-zero index fetch to individually addressed
   baseline-JPEG frames and their matching PCM slices.
2. Connect the JPEG decoder to the DDR3 triple-buffer path and measure 25 fps
   headroom. Retain PVF as the canonical archive and DDV as the playback cache.
3. Align the decoded PAL frame to the BBC beam and implement colour-keyed
   foreground composition.
4. Connect the Pi1MHz player protocol to the BBC 1 MHz bus.
5. Add LaserDisc PCM mixing and end-to-end media tests.

The source material under `references/` is research input only. Code moved
into this directory must retain its upstream licence and attribution.
