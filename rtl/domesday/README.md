# Domesday RTL integration

This directory is the boundary between the working BeebFpga MiSTer core and
the LaserDisc implementation.

## Phase 1: mounted-media bridge

`domesday_bridge.sv` owns MiSTer virtual disk slot 3 (`.DLV`). It records the
mounted image size and exposes a `disc_present` state, but intentionally makes
no block requests. The optional OSD status-LED setting shows the latched mount
state without changing BBC video or audio.

## Planned phases

1. Replace the idle slot outputs with Picmatic's `dlv_streamer` block reads.
2. Add `jpeg_frame_decoder`, `fb_writer`, and the DDR3 triple-buffer path.
3. Align the decoded PAL frame to the BBC beam and implement colour-keyed
   foreground composition.
4. Connect the Pi1MHz player protocol to the BBC 1 MHz bus.
5. Add LaserDisc PCM mixing and end-to-end media tests.

The source material under `references/` is research input only. Code moved
into this directory must retain its upstream licence and attribution.
