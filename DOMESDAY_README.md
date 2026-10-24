# Domesday for MiSTer

Feasibility and prototype work for running the BBC Domesday system on a MiSTer FPGA, using:

- [BeebFpga_MiSTer](https://github.com/sharpie7/BeebFpga_MiSTer) as the BBC Master starting point;
- [Pi1MHz](https://github.com/dp111/Pi1MHz) as the behavioural reference for BeebSCSI, VP415 F-codes, jukebox selection, media layout, and video playback;
- [Arcade-Picmatic_MiSTer](https://github.com/jsmolina/Arcade-Picmatic_MiSTer) as the proven FPGA LaserDisc media, JPEG decode, DDR, audio, and genlock reference;
- the current MiSTer framework and ARM-side `Main_MiSTer` implementation; and
- the local Arc project as the model for remote Quartus builds and RBF deployment.

## Initial result

**Feasible, with a significant FPGA integration project.** Picmatic materially strengthens the result: it already demonstrates mounted `.dlv` media, FPGA MJPEG decoding, DDR3 triple buffering, PCM audio, and beam-synchronous genlock on a physical MiSTer. The main risk is now fitting that path alongside the BBC Master and achieving the pixel registration Domesday's BBC overlays require.

The recommended design is FPGA-centric:

1. FPGA: BBC Master, `&FC40-&FC43` SCSI host adapter, VP415/F-code state, `.dlv` streamer, JPEG decoder, DDR triple buffer, PCM audio, and BBC/disc genlock.
2. Stock MiSTer ARM/framework: mounted VFS and `.dlv` files through normal `hps_io`, input/OSD, scaler, and output plumbing.
3. Media tooling: convert source video to independently seekable baseline MJPEG plus PCM, initially at 416x288 for 2x expansion onto an 832x576 composition grid.

This is not a direct compile of Pi1MHz. Its bus handler, VideoCore/MMAL decoder, HVS planes, bare-metal drivers, and Raspberry Pi memory layout remain platform-specific. Its BeebSCSI/F-code logic, tests, and player behaviour are the specification; Picmatic supplies the practical MiSTer media pipeline.

## Documents

- [Feasibility assessment](docs/feasibility.md)
- [Proposed architecture and prototype plan](docs/architecture.md)
- [Source and local-asset inventory](docs/source-inventory.md)
- [Development environment](docs/development-environment.md)
- [Picmatic LaserDisc core assessment](docs/picmatic-assessment.md)

## Immediate next gate

Before implementing the full core, transplant Picmatic's `.dlv`/JPEG/DDR path into a minimal test build, then into BeebFpga. Record fit and timing at 384x288 and 416x288, and prove a stable BBC colour-0 overlay on an 832x576 composition grid. HPS H.264 decoding is now a fallback experiment, not the primary gate.

No actual LaserDisc media file was present in this folder during the initial inventory on 2026-10-24; `P1MHzImages` contained only `ReadMe.txt`. Media is intentionally excluded from Git.

