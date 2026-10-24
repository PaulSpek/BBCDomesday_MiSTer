# Domesday RTL integration

This directory is the boundary between the working BeebFpga MiSTer core and
the LaserDisc implementation.

## Phase 1: native PVF mounted-media bridge

`domesday_bridge.sv` owns MiSTer virtual disk slot 3 (`.PVF`). After a mount it
reads sector zero through the standard `hps_io` block interface and validates
the 64-byte Pi1MHz PVF1 header. The optional OSD status-LED setting lights only
after that validation succeeds. Video records are not streamed or decoded yet,
so BBC video and audio remain unchanged.

## Planned phases

1. Read PVF index and record headers and expose independently seekable H.264
   access units plus their per-frame PCM slices.
2. Benchmark native H.264 decoding on the MiSTer HPS and connect decoded RGB565
   frames to the DDR3 triple-buffer path. If the benchmark misses 25 fps, retain
   PVF as the canonical archive and generate a transparent playback cache.
3. Align the decoded PAL frame to the BBC beam and implement colour-keyed
   foreground composition.
4. Connect the Pi1MHz player protocol to the BBC 1 MHz bus.
5. Add LaserDisc PCM mixing and end-to-end media tests.

The source material under `references/` is research input only. Code moved
into this directory must retain its upstream licence and attribution.
