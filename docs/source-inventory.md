# Source and asset inventory

Inventory date: 2026-10-24.

## Local inputs

### `Pi1MHz_V131.zip`

- Size: 4,867,794 bytes.
- SHA-256: `82E5C93D5713728D7BE452900F9542EF55D2A1A84E1039F2E58DBC69CEA0B6EA`.
- Contains Raspberry Pi boot firmware, kernels, ROMs, configuration, and BeebSCSI/VFS support files.
- It is a deployable binary image, not the source used for this assessment.

### `P1MHzImages`

- Only `ReadMe.txt` was present.
- The text maps BeebVFS directories 1-20 to Community, National, Volcanoes, EcoDisc, Countryside, Financial, Culture, and BGB media.
- No disc data or video files were present.

### Arc MiSTer project

Location: `C:\Users\Dell\Projects\Arc`.

Reusable environment details found in ignored `local.settings.ps1`:

- Quartus 17.0 tool paths;
- a remote Windows build host/repository mapping;
- MiSTer SSH/SCP destination under `/media/fat/_Computer/`;
- PuTTY `plink`/`pscp` paths and pinned host-key data.

Credentials were not copied into this project. See [development-environment.md](development-environment.md).

## Reproducible upstream checkouts

Shallow research copies are under ignored `references/`.

| Repository | Revision inspected | Date | Purpose |
|---|---|---|---|
| [dp111/Pi1MHz](https://github.com/dp111/Pi1MHz) | `de544a148d90d69558d3bdcc19970db1f61f4209` | 2026-10-23 | BeebSCSI, VP415 F-codes, PVF, video/player behaviour |
| [sharpie7/BeebFpga_MiSTer](https://github.com/sharpie7/BeebFpga_MiSTer) | `70e3cb4816538faccfc4233564668e34ceab5f4c` | 2022-03-20 | BBC B/Master MiSTer core basis |
| [MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | `e698ccdb876cfd8340635141316bdb8ac50833cc` | 2026-10-24 | ARM-side file, framebuffer, shared-memory, and core services |
| [MiSTer-devel/Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) | `5dda37366d02b04b8448da7b322235c1831af811` | 2026-10-16 | Current MiSTer FPGA framework |
| [jsmolina/Arcade-Picmatic_MiSTer](https://github.com/jsmolina/Arcade-Picmatic_MiSTer) | `696397b71aef7273b42200c1d82e8d3810d074db` | 2026-10-23 | Hardware-tested `.dlv`, FPGA MJPEG decode, PCM, DDR3 frame buffers, and genlock |

Recreate them with:

```powershell
git clone --depth 1 https://github.com/dp111/Pi1MHz.git references/Pi1MHz
git clone --depth 1 https://github.com/sharpie7/BeebFpga_MiSTer.git references/BeebFpga_MiSTer
git clone --depth 1 https://github.com/MiSTer-devel/Main_MiSTer.git references/Main_MiSTer
git clone --depth 1 https://github.com/MiSTer-devel/Template_MiSTer.git references/Template_MiSTer
git clone --depth 1 https://github.com/jsmolina/Arcade-Picmatic_MiSTer.git references/Arcade-Picmatic_MiSTer
```

## Key evidence locations

### Pi1MHz

- `ReadMe.md`: supported devices and GPL-3.0-or-later statement.
- `docs/user/screen-and-video.md`: hardware-proven Domesday player, required PVF media, and measured Pi performance.
- `docs/dev/laserdisc-video-integration-plan.md`: integration design, F-codes, buffering, and overlay semantics.
- `docs/dev/h264-hardware-decode.md`: Raspberry Pi-specific MMAL/VCHIQ decode path.
- `src/pvf.h`: indexed PVF v1 container and all-IDR record layout.
- `src/BeebSCSI/fcode.c`: VP415 protocol implementation.
- `src/harddisc_emulator.c`: `&FC40-&FC43` adapter and race-sensitive REQ/ACK behaviour.
- `src/videoplayer.c`: player state, seeks, audio, and Pi hardware decode integration.
- `src/tests/fcode`: portable protocol tests.
- `tools/make_pvfv2.py` and `tools/verify_pvf.py`: media preparation and validation.

### BeebFpga_MiSTer

- `BBCMicro.sv`: MiSTer top level, video, virtual SD, dormant framebuffer/DDRAM ports.
- `rtl/bbc_micro_core.vhd`: Master implementation, 1 MHz stalling, FRED/JIM decode, and CPU data mux.
- `BBCMicro.qsf`: Cyclone V target, Quartus 17.0.2, and disabled `MISTER_FB` macro.
- `sys/hps_io.sv`: ARM/FPGA control and virtual-image interface.

### MiSTer

- Main `video.cpp`: Linux framebuffer at reserved HPS DDR, framebuffer switching, and core/HPS framebuffer protocol.
- Main `shmem.cpp`: `/dev/mem` mapping used by existing support modules.
- Main `user_io.cpp`: mounted-image and per-core HPS service hooks.
- Template `sys/sys_top.v`: current DDR/scaler/framebuffer bridge.

### Arcade-Picmatic_MiSTer

- `README.md`: hardware design, current tested status, media conversion, and controls.
- `rtl/ld_video.sv`: complete `.dlv` to DDR/video/audio integration and triple buffering.
- `rtl/ld/dlv_streamer.v`: standard `hps_io` sector reader, indexed frame seeks, and PCM ring.
- `rtl/ld/jpeg_frame_decoder.v` and `rtl/ld/core_jpeg/`: baseline JPEG decoding to RGB.
- `rtl/ld/fb_writer.v` and `rtl/ld/ddram.sv`: RGB565 frame storage through MiSTer's HPS DDR port.
- `rtl/ld_player.sv`: Sony LDP-1450 protocol reference; useful structurally but not protocol-compatible with VP415.
- `tools/avi2dlv.py`: 25 fps, baseline MJPEG/PCM `.dlv` converter.
- `doc/picmatic-plan.md`: subsystem provenance, design decisions, and staged validation plan.

## External hardware reference

Intel's [Cyclone V HPS Technical Reference Manual](https://www.intel.com/programmable/technical-pdfs/683126.pdf) describes the dual Cortex-A9 HPS, DDR controller, peripherals, and FPGA bridges. It does not provide a video codec block comparable to Raspberry Pi VideoCore, which is why H.264 performance is an explicit benchmark gate.

