# Feasibility assessment

Assessment date: 2026-10-24.

## Verdict

The project is technically possible on MiSTer, with **medium-high overall confidence**. The newly inspected Picmatic core already performs real-time LaserDisc media streaming, FPGA MJPEG decoding, PCM playback, DDR3 frame buffering, and genlock on MiSTer hardware. The remaining high-value gates are combined FPGA fit/timing and exact BBC-to-disc overlay registration.

The BBC/SCSI control side is a good fit for FPGA logic. BeebFpga already has a Master 128, correct 1 MHz-cycle stalling, free FRED/JIM address space, virtual SD-image plumbing, and the standard MiSTer top-level signals. Pi1MHz documents and implements the exact SCSI/VP415 behaviour needed by Domesday.

The Pi video implementation still cannot be transplanted: it relies on Raspberry Pi VideoCore MMAL/VCHIQ hardware decoding and HVS planes. Picmatic provides a better native solution: a `.dlv` sector streamer and baseline JPEG decoder in the FPGA, followed by RGB565 triple buffering in HPS DDR. This can use stock MiSTer mounted-image services and avoids relying on Cortex-A9 H.264 performance.

## Component assessment

| Component | Feasibility | Evidence / issue |
|---|---:|---|
| BBC Master core | High | BeebFpga supports Model B and Master 128 and is already a working MiSTer core. |
| Pi1MHz register compatibility | High | BeebFpga decodes FRED (`&FC00`) and JIM (`&FD00`) and stalls these accesses at 1 MHz. `&FC40-&FC43` currently have no conflicting peripheral. |
| SCSI REQ/ACK adapter | High | Four small memory-mapped registers plus a finite-state machine/FIFOs. Timing is easier inside the FPGA than across HPS polling. |
| VFS data volumes | High | Existing MiSTer virtual-disk I/O can expose a mounted `scsi0.dat`; the FPGA need not implement FAT. Jukebox switching needs a small ARM-side extension. |
| VP415 F-code behaviour | Medium-high | Pi1MHz has current code and host tests for goto/still/play/reverse/step/speed/audio/video/status and disc flip. Porting requires separating it from Pi drivers and FatFs. |
| Random-access media format | High | Picmatic's `.dlv` is indexed and maps disc frame N to independent JPEG frame N; Pi1MHz's PVF is similarly random-access. |
| FPGA JPEG decoding | Medium-high | Picmatic integrates a working baseline JPEG decoder and reports a hardware-tested build. Resolution and combined-core margin still need measurement. |
| Video composition | Medium-high | Picmatic proves beam-synchronous DDR line fetch and colour-0 genlock. Domesday needs different VP modes and more exact BBC overlay registration. |
| Audio | High | Picmatic already streams 44.1 kHz stereo PCM with channel control from the same `.dlv` file. |
| FPGA capacity/timing | Medium | Picmatic's A500 plus video path fits, but no committed fit report proves BeebFpga plus JPEG will fit or meet timing. |
| Main/HPS changes | High | The preferred path uses normal multi-slot `hps_io`; no custom H.264 decoder or framebuffer service in Main is required. |
| Development workflow | High once hosts return | Arc supplies Quartus 17.0.2, remote-build, and MiSTer transfer settings. Both configured SSH endpoints were unreachable during this assessment. |

## Important discoveries

### Pi image and source are different generations

The local archive is `Pi1MHz_V131.zip` (SHA-256 `82E5C93D5713728D7BE452900F9542EF55D2A1A84E1039F2E58DBC69CEA0B6EA`). The upstream checkout was at v1.41-era commit `de544a148d90d69558d3bdcc19970db1f61f4209`, dated 2026-10-23. The current source contains hardware-proven Domesday video work and newer PVF v2 tooling, so it should be the behavioural reference rather than the older binary archive.

### BeebFpga is usable but old

The selected BeebFpga repository was at commit `70e3cb4816538faccfc4233564668e34ceab5f4c` from 2022-03-20. Its MiSTer `sys/` framework predates the current template. Before feature work, update the framework carefully and get an unchanged baseline build and hardware boot.

### The framebuffer path is partly scaffolded

`BBCMicro.sv` already declares `FB_*` and `DDRAM_*` ports, while its DDR outputs are tied to zero. The QSF has `MISTER_FB` commented out, but the top module guards its ports with the obsolete name `USE_FB`. This is encouraging—the intended integration point exists—but it is not currently functional.

### Picmatic proves the hard media path

`Arcade-Picmatic_MiSTer` revision `696397b71aef7273b42200c1d82e8d3810d074db` contains a current RBF and reports a hardware-verified Marbella Vice boot. Its `ld_video` subsystem mounts `.dlv` media through `hps_io`, decodes 384x288 baseline MJPEG in FPGA logic, writes RGB565 into a DDR3 triple buffer, fetches one disc row per Amiga raster line, mixes PCM audio, and treats computer colour 0 as transparent. See [picmatic-assessment.md](picmatic-assessment.md).

This changes the recommended architecture. HPS H.264 is now a fallback rather than the first go/no-go experiment.

### Media is missing

`P1MHzImages/ReadMe.txt` describes BeebVFS directories for Community, National, Volcanoes, EcoDisc, Countryside, Financial, Culture, and BGB discs. No corresponding directory, `scsi0.dat`, PVF, MKV, TBC, PCM, IMG, or ISO was found locally. A representative video input is needed for the decoder gate.

## Video design options

### A. FPGA MJPEG/`.dlv` using the Picmatic path — recommended

- Reuse the sector streamer, JPEG wrapper/core, RGB565 writer, DDR adapter, triple buffering, line fetch, and PCM logic.
- Start with 416x288 media and expand 2x2 onto the 832x576 Pi1MHz composition grid.
- Replace Picmatic's Sony player block with the Pi1MHz-derived VP415/F-code state machine.
- Use a separate virtual slot for VFS data; BeebFpga's `hps_io` already supports multiple devices.

Advantages: demonstrated on MiSTer hardware, deterministic, supports frame-accurate random seek, requires no custom Main build, and avoids CPU decoder load. Risks: JPEG logic/timing headroom and exact overlay scaling.

### B. HPS software H.264 decode to shared DDR — fallback

- Decode each independently seekable PVF H.264 frame on an ARM worker pinned away from the latency-sensitive MiSTer loop.
- Write RGB565 or a convenient YUV/RGB format into one of two reserved DDR buffers.
- Have FPGA logic overlay non-transparent BBC pixels into the back buffer and present it through `MISTER_FB` at vertical blank.
- Keep bus/SCSI handshakes in FPGA so decoder load cannot break BBC timing.

Advantages: retains compact 1.5-2.5 GB disc-side files and reuses the PVF index. Risks: unproven Cortex-A9 performance, cache/buffer coordination, and significantly more Main/HPS integration.

### C. Predecoded frames

At 832x576, 25 fps, 54,000 pictures (36 minutes), uncompressed storage is approximately:

- RGB565: 51.7 GB per side;
- YUV 4:2:0: 38.8 GB per side.

This is simple and deterministic but consumes too much storage and ~18-24 MB/s sustained I/O before BBC data traffic. It is a useful diagnostic fallback, not the target format.

### D. FPGA H.264 decoder

Not recommended. A standards-compliant decoder is far beyond the sensible logic/DSP/resource budget and project scope.

## Go/no-go gates

1. **Baseline:** updated BeebFpga builds in Quartus 17.0.2, meets timing, boots as Master, and reports resource headroom.
2. **Register proof:** a small `&FC40-&FC43` HDL block passes a deterministic BBC test ROM and can exchange mailbox messages with HPS.
3. **Video proof:** the Picmatic-derived path sustains indexed seek/still/play at 25 fps from `.dlv`, with stable PCM and no underruns.
4. **Framebuffer proof:** 384x288 and 416x288 source tests establish the best stable 832x576 BBC colour-0 composite without tearing or registration errors.
5. **Domesday proof:** VFS boots, reads data, sends F-codes, seeks to named pictures, plays audio/video, and switches jukebox/disc side.

Failure of gate 3 does not make the whole idea impossible: HPS H.264 and lower-resolution JPEG remain alternatives, but either result changes scope.

## Legal/licensing note

This is a technical assessment, not legal advice. The top-level Beeb MiSTer wrapper is GPL-2.0-or-later, while `bbc_micro_core.vhd` contains an explicit non-commercial redistribution condition inherited from earlier work. Pi1MHz and Picmatic state GPL-3.0; Picmatic's vendored `core_jpeg` is Apache-2.0 and its LaserDisc modules record their upstream revisions. Keep provenance per file, do not assume a single repository-level licence covers everything, and review redistribution terms before publishing RBFs, ROMs, VFS images, or LaserDisc-derived media.

