# Proposed architecture and prototype plan

The current detailed implementation sequence, based on core version 06 and
the 29 October hardware results, is maintained in
[video-implementation-plan.md](video-implementation-plan.md). The phases below
record the original prototype proposal and are not a completion checklist.

## Target split

```text
 hps_io slot: VFS image ----> FPGA SCSI target <---- BBC &FC40-&FC43 adapter
                                                        |
                                                        v
                                                VP415/F-code state
                                                        |
 hps_io slot: .dlv --------> indexed frame/PCM streamer-+
                                  |                     |
                                  v                     v
                         FPGA JPEG decoder         PCM audio
                                  |
                                  v
                         DDR3 triple frame buffer
                                  |
                         beam-synchronous line fetch
                                  |
BBC RGB + transparency ----------+----> VP1-VP5 pixel mux ----> MiSTer video
```

The FPGA must never wait for Linux userspace on a 6502 bus cycle. It answers register accesses from local state and lets standard `hps_io` satisfy asynchronous sector requests. The player, decoder, buffer ownership, and compositing stay deterministic in FPGA logic.

## FPGA responsibilities

### BBC core baseline

- Start from BeebFpga's Master 128 mode.
- Update `sys/` from current Template_MiSTer before adding functionality.
- Wire the currently dormant HPS-DDR interface for the Picmatic-derived frame buffers.
- Retain the normal direct video path as a debug/fallback mode.

### Pi1MHz-compatible host adapter

Implement the default hard-disc base at FRED `&40`:

| Address | Read | Write |
|---|---|---|
| `&FC40` | SCSI data byte; acknowledge/take data | SCSI data byte; acknowledge host write |
| `&FC41` | SCSI status flags | VFS/SCSI jukebox selection |
| `&FC42` | unused/default | assert SCSI select |
| `&FC43` | unused/default | enable/disable BBC IRQ |

The status byte uses Pi1MHz's bit layout: C/D, I/O, REQ, IRQ, two spare/status bits, BSY, and MSG. The HDL should clear REQ atomically when `&FC40` is consumed, mirroring the race fix documented in current Pi1MHz.

Start with programmed I/O and a small pair of FIFOs. Add IRQ only after polling mode works.

### LaserDisc media path and video mux

- Begin with baseline 4:2:0 MJPEG at 416x288 and expand it 2x2 to the same 832x576 sampling grid used by current PVF v2 media.
- Treat BBC color 0 as transparent for VP3/VP4/VP5, opaque for computer-only VP2, and disable the BBC layer for video-only VP1.
- Preserve E0/E1 video enable independently of VP mode.
- Port Picmatic's indexed `.dlv` streamer, JPEG decoder, RGB565 DDR writer, triple buffering, and PCM path.
- Fetch the decoded disc row into a line buffer and combine it with the BBC pixel stream under the BBC beam timing.
- Keep 384x288 and full 832x576 media as measured alternatives.

## MiSTer framework responsibilities

The preferred architecture uses stock `Main_MiSTer` behaviour. BeebFpga currently uses three virtual devices and its `hps_io` supports up to ten; add distinct slots for VFS and `.dlv` media and route each slot's block requests to the correct FPGA client.

### Storage and media association

- Mount/select a BeebVFS `scsi0.dat` as a normal virtual block image.
- Associate it with a sibling `video.pvf`.
- Initially select VFS and `.dlv` explicitly from the OSD. Later add a manifest or naming convention so an `&FC41` jukebox event can select a matched pair without modifying the base video pipeline.
- Keep writable BBC data and read-only VFS media separate.

## VP415 player state

Port behaviour, not Raspberry Pi hardware code or Picmatic's Sony protocol:

- adapt Pi1MHz media validation/frame mapping into a `.dlv` conversion and verification tool;
- reuse or adapt F-code parser/state tests;
- implement picture-number seek, still, forward/reverse play, step, slow/fast speeds, stop/info registers, audio channel enables, video enable, VP modes, and disc flip;
- produce completion replies when the requested action completes, with a bounded timeout as Pi1MHz does.

Do not port VCHIQ, MMAL, HVS, bare-metal SD/FatFs, GPIO FIQ, or Raspberry Pi audio drivers.

### Decoder and audio

- Use Picmatic's FPGA `core_jpeg` wrapper and DDR writer.
- Preserve its independent-frame index, audio-priority sector arbitration, and PCM ring buffering.
- Add counters for decoded/late/dropped frames, seek latency, audio underruns, and longest decode time.
- Retain HPS H.264 as an optional later experiment, not a dependency of the first prototype.

## Prototype phases

### Phase 0 — reproducible baseline

1. Vendor/fork BeebFpga into the project rather than editing the research checkout.
2. Refresh the MiSTer framework from Template_MiSTer.
3. Build on the remote Quartus 17.0.2 host.
4. Deploy via the Arc-derived transfer configuration.
5. Record fit/timing summary and boot the Master core unchanged.

Exit: known-good RBF plus resource/timing baseline.

### Phase 1 — bus and SCSI proof

1. Add the four-register adapter and a simulation testbench.
2. Return stable status/data values to a short BBC BASIC/ROM diagnostic.
3. Implement SCSI selection and REQ/ACK byte phases.
4. Expose one read-only VFS LUN through MiSTer's mounted-image path.

Exit: Domesday/VFS software can enumerate/read the emulated device without video.

### Phase 2 — LaserDisc media proof

1. Port the Picmatic `.dlv` streamer, JPEG decoder, DDR writer, line reader, and PCM path.
2. Build at 384x288 and 416x288 and record fit/timing.
3. Verify seek, still, forward playback, and audio using a synthetic legal clip.

Exit: stable 25 fps disc video/audio under the BBC raster with no player protocol yet.

### Phase 3 — F-code proof

1. Route SCSI WRITE/READ BUFFER commands to the FPGA player state machine.
2. Port F-code tests and player state against the working decoder.
3. Verify frame/status replies and jukebox selection using logs.

Exit: BBC software controls a synthetic player and sees correct replies.

### Phase 4 — genlock/video gate

1. Implement VP1-VP5 and E0/E1 pixel selection against the DDR line buffer.
2. Verify BBC colour-0 transparency and opaque computer-only mode.
3. Compare 384x288 and 416x288 source alignment on an 832x576 test grid.
4. Measure seek latency, decoder margin, audio underruns, and tearing on MiSTer.

Exit: stable composited moving video with measured headroom.

### Phase 5 — complete Domesday path

Add reverse/variable-speed playback, disc flip, on-screen picture number, audio-channel control, robust media changes, diagnostics, and packaging.

## Tests to carry over

- Pi1MHz `src/tests/fcode` for F-code parsing and completion behaviour.
- Pi1MHz `tools/verify_pvf.py` for media validation.
- New HDL tests for every `&FC40-&FC43` read/write transition, including REQ clear on data consumption and reset mid-transfer.
- End-to-end scripted checks: boot VFS, read catalogue, seek picture, play 10 seconds, pause, step, reverse, toggle VP modes, and change jukebox.

