# Picmatic LaserDisc core assessment

Assessment date: 2026-10-24. Inspected revision: `696397b71aef7273b42200c1d82e8d3810d074db`.

## Conclusion

Yes: `Arcade-Picmatic_MiSTer` is a real MiSTer LaserDisc implementation, not merely a controller stub. It mounts an indexed `.dlv` media file through the normal `hps_io` block interface, decodes an MJPEG frame in FPGA logic, writes RGB565 pictures to HPS DDR3, reads them back in sync with the computer raster, mixes PCM audio, and genlocks the computer graphics over the disc image.

Its README reports that the current Marbella Vice build was verified on physical MiSTer hardware and reaches the game's coin-wait state. Only Marbella Vice is currently described as working and tested, so this is strong architectural evidence rather than proof that every control or media edge case is complete.

For Domesday this is the most relevant implementation found so far. It removes the earlier dependence on unproven Cortex-A9 H.264 software decoding and on a custom `Main_MiSTer` video service.

## What the core implements

| Function | Picmatic implementation | Domesday relevance |
|---|---|---|
| Mounted media | `S0,DLV,Mount LaserDisc` through standard `hps_io` sector reads | Reuse; add another virtual slot for Domesday VFS data. |
| Container | 512-byte `.dlv` header, frame index, independent JPEG frames, PCM blob | Reuse or make a compatible Domesday profile/converter. |
| Video decode | Vendored `ultraembedded/core_jpeg`, baseline JPEG to RGB | Reuse with attribution and its Apache-2.0 terms. |
| Frame storage | RGB565 frames in a triple buffer in HPS DDR3 | Reuse, with addresses and arbitration adapted to BeebFpga. |
| Display | One DDR row fetched into a line buffer per source raster line | Reuse the pattern; retime for the BBC raster. |
| Composition | Amiga colour index 0 is transparent, computer beam is timing master | Adapt to VP415 VP1-VP5 modes and BBC colour-0 transparency. |
| Audio | 44.1 kHz stereo PCM streamed from `.dlv`, with channel control | Reuse/adapt for VP415 audio channel commands. |
| Player protocol | Sony LDP-1450 command interpreter on an 8N1 serial link | Do not reuse as the Domesday interface; replace with VP415 F-code state. |

The media converter creates 384x288, 25 fps, 4:2:0 baseline MJPEG without restart markers plus 44.1 kHz stereo PCM. The README estimates about 1.2 GB for a 36-minute disc. Disc frame number maps directly to video frame number, which preserves the random-access behaviour a LaserDisc application expects.

## Directly reusable RTL

The likely reusable block is `rtl/ld_video.sv` together with selected files under `rtl/ld/`:

- `dlv_streamer.v`: indexed frame selection, sector requests, playback pacing, and audio ring;
- `jpeg_frame_decoder.v` and `core_jpeg/`: baseline JPEG decoding;
- `fb_writer.v`: RGB888-to-RGB565 frame writes to HPS DDR;
- `ddram.sv`: MiSTer HPS-DDR interface adaptation;
- the triple-buffer selection, line fetch, and audio plumbing in `ld_video.sv`.

The modules should first be ported with minimal changes and exercised independently. `ld_player.sv` is a Sony LDP-1450 implementation and is not the correct Domesday command layer.

## Necessary Domesday changes

### BBC and player control

Domesday sends Philips VP415 F-codes through BeebSCSI commands on the BBC 1 MHz bus, not Sony serial commands. The new core still needs:

- Pi1MHz-compatible registers at `&FC40-&FC43`;
- SCSI REQ/ACK and READ/WRITE BUFFER behaviour;
- a VP415/F-code state machine based on Pi1MHz's tested behaviour;
- VFS block-image service and jukebox/disc-side selection;
- a mapping from VP415 picture numbers to `.dlv` frame numbers.

### Two mounted-image consumers

BeebFpga currently instantiates `hps_io` with three virtual devices for its existing media. Its local `hps_io` supports up to ten. A fourth slot can therefore be assigned to `.dlv`, while a VFS `scsi0.dat` uses its own slot. The shared sector-data bus needs clean per-slot routing and request arbitration, but this does not require a custom MiSTer executable.

### Resolution and overlay fidelity

Picmatic uses 384x288 because that maps one disc pixel to one Amiga low-resolution pixel. Current Pi1MHz PVF v2 media uses 832x576 to align the LaserDisc image and BBC graphics on a pixel-precise output grid.

Three candidates should be measured:

1. **416x288 JPEG, doubled to 832x576 for composition.** Best first prototype: close to Picmatic's proven load and exactly half the Pi1MHz grid in each axis.
2. **384x288 JPEG with horizontal resampling to the BBC grid.** Direct reuse of Picmatic's current settings, but overlay alignment may be less exact.
3. **832x576 JPEG.** Highest fidelity, but 6.24 times the pixels of the decoder's 320x240 reference point and roughly four times 416x288. It may have inadequate decode/timing/resource margin when combined with the BBC core.

The first hardware experiment should use 416x288 source frames, expand each source pixel to a 2x2 block, and composite against the BBC's 832x576 sampling grid. If fine text or map boundaries expose alignment errors, test a higher horizontal resolution before attempting full 832x576 JPEG.

### VP415 display modes

The final pixel mux must implement the semantics already captured by Pi1MHz:

- VP1: disc video only;
- VP2: computer only;
- VP3/VP4/VP5: superimposed display, with BBC colour 0 transparent;
- E0/E1: independent video disable/enable;
- still, play, forward/reverse, step, speed, and audio-channel state.

This is conceptually the same beam-synchronous genlock used by Picmatic, but the transparency signal must come from the BBC video path and follow VP415 mode state rather than Amiga Denise's `zd` output.

## Throughput and capacity

The upstream JPEG decoder documents 2.1 cycles per output pixel for YCbCr 4:2:0 at peak. At Picmatic's 28.375 MHz decoder clock, the ideal pixel-rate calculation is comfortably above 416x288x25, but real throughput also includes JPEG parsing, DDR writes, sector delivery, and stalls. Only synthesis and hardware measurements establish margin.

No Quartus fit or timing report is committed in the Picmatic checkout. The included RBF and hardware report demonstrate that its A500 plus LaserDisc path fits, but not that BeebFpga plus the same blocks will automatically fit. A baseline build followed by a decoder-only integration build is required.

## Revised risk assessment

| Risk | Level | Reason |
|---|---:|---|
| Basic LaserDisc media playback on MiSTer | Low-medium | Demonstrated by two MiSTer core families and by Picmatic on hardware. |
| FPGA resource/timing fit with BBC Master | Medium | No combined fit report yet; JPEG decoder is the major added block. |
| BBC/video pixel registration | Medium-high | Domesday overlays are more exacting than a simple arcade genlock. |
| VP415/F-code behaviour | Medium | Pi1MHz supplies code/tests, but it must be expressed in HDL or a small deterministic service. |
| VFS plus `.dlv` coexistence | Low-medium | `hps_io` supports several virtual slots; arbitration and UI need implementation. |
| Storage size | Low | MJPEG is larger than H.264 but Picmatic's result is still practical on MiSTer storage. |
| Custom Main/HPS software | Low | Not required for the preferred architecture; stock mounted-image I/O is sufficient. |

## Recommended proof sequence

1. Build the unmodified Picmatic core and retain its current RBF as the known-good media reference.
2. Run a short synthetic `.dlv` on real MiSTer and measure seek, still-frame, audio, and sustained 25 fps behaviour.
3. Transplant the LaserDisc media block into a current MiSTer template with a generated test raster.
4. Integrate it into BeebFpga, first at 384x288 and then 416x288, while recording Quartus logic, RAM, DSP, and timing results.
5. Implement VP1-VP5 compositing before SCSI/F-code control.
6. Add the `&FC40-&FC43` adapter, a read-only VFS image, and the Pi1MHz F-code tests.
7. Convert a short, legally available Domesday clip to `.dlv`; validate frame-number mapping and overlay registration before converting full sides.

## Provenance

Picmatic is GPL-3.0 and includes a vendored LaserDisc path identified as coming from `MiSTer-devel/Arcade-LaserdiscGames_MiSTer` revision `d948270`. Its vendored `core_jpeg` snapshot is identified as revision `bb03cce` and remains Apache-2.0. Preserve per-file notices and revision information when extracting these modules.
