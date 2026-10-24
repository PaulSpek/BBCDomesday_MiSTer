# Domesday RTL integration

This directory is the boundary between the working BeebFpga MiSTer core and
the LaserDisc implementation.

## Phase 1: mounted-media bridge

`domesday_bridge.sv` owns MiSTer virtual disk slot 3. It reads sector zero
through the standard `hps_io` block interface and validates either a 64-byte
Pi1MHz PVF1 header or the complete 512-byte DDV1 JPEG/PCM-cache header. The
OSD mounts `.DDV` playback-cache media; the optional status LED lights only
after a valid PVF1 or DDV1 header has been read. Video records are not streamed
or decoded yet, so BBC video and audio remain unchanged.

## Planned phases

1. Read the DDV 64-bit index and fetch individually addressed baseline-JPEG
   frames plus their matching PCM slices.
2. Connect the JPEG decoder to the DDR3 triple-buffer path and measure 25 fps
   headroom. Retain PVF as the canonical archive and DDV as the playback cache.
3. Align the decoded PAL frame to the BBC beam and implement colour-keyed
   foreground composition.
4. Connect the Pi1MHz player protocol to the BBC 1 MHz bus.
5. Add LaserDisc PCM mixing and end-to-end media tests.

The source material under `references/` is research input only. Code moved
into this directory must retain its upstream licence and attribution.
