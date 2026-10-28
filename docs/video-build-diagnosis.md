# Video integration build diagnosis

## 26 October 2026

All Quartus builds run on STUDEER. Resource numbers below are from failed
pre-placement reports, not completed fits or verified timing closure.

| Build | Source | M10K blocks | Outcome |
| --- | --- | --- | --- |
| 182802-316dabb0 | d8106e0 | 617/553 | Memory capacity exceeded |
| 185350-e7d9b38e | 7725209 | Previous fitter report was reused in the initial diagnosis | Must not infer current resource usage from an older report |
| 193407-19884473 | 5767e65 | 609/553 | IDCT scratch RAMs now map to MLAB; memory still exceeded |
| 195310-40943063 | 7e6904a | 607/553 | 32-bit ROM packing; 24,219 ALMs (58%); memory still exceeded |
| 201233-2067d2bb | db6069a | ROMs still 260+80 | Quartus 17 did not define SYNTHESIS; behavioral branch was synthesized |
| 20261027-165751-d229cdef | 0bdbd46 | 622/553 | Single-port selected, but ROMs still consume 260+80; placement fails (170040) |

The former claim that logic was exactly at its capacity was incorrect: a
failed-fit summary capped one field at device capacity. The latest report
shows substantial logic headroom. Read the detailed usage and report timestamp.

### Root cause and current correction

The initial 40-bit ROM arrays used different read and write addresses. This
inferred dual-port RAM, which loses the single-port 256x40 M10K geometry.
Built-in ROM used 260 blocks and cartridges 80. The 32-bit attempt reduced
these to 256 and 64, but could not solve the 54-block shortage.

Use five-byte words with a shared read/write address. CPU reset already covers
cartridge uploads; built-in uploads are accepted only during reset. Target:
205 blocks for built-in ROM and 52 for cartridges (63 fewer than 32-bit mode).
This is a prediction until STUDEER's report confirms single-port mapping.
The 20:07 build still inferred DUAL_PORT despite the shared address, so it
was stopped during synthesis. The hardware implementation now explicitly
instantiates altsyncram with operation_mode=SINGLE_PORT. Behavioral simulation
uses the corresponding single-address array; read data during upload is unused.

### 27 October: synthesis-branch correction

The latest report still names inferred memory_rtl_0 instances, proving the
explicit primitives were not selected. Quartus 17 does not define SYNTHESIS
in this project. Hardware primitives are now the default branch. Only tests
using DOMESDAY_BEHAVIORAL_ROM select behavioral arrays. Run
`powershell -ExecutionPolicy Bypass -File tools/test_rom_slots.ps1 -Hardware`
to exercise the actual Altera memory model, including MIF initialization.
The test runner starts ModelSim in the project root so relative MIF paths work.

Build 20261027-165611-ef619231 exposed Quartus error 272006 because clock1
was tied to zero on a single-port primitive. Leaving that unused clock open
corrects elaboration (commit 0bdbd46). The next build,
20261027-165751-d229cdef, confirms operation_mode=SINGLE_PORT for both ROMs
in its log. Full resource usage and timing closure remain pending.

The Altera model tests pass for all uploaded bytes and the initial diagnostic
ROM header, with no errors or warnings before the unused-clock tie correction.
The open unused clock has no effect on the single-port functional model.

### Physical segment depth

The 17:05 fitter report confirms single-port mode, but built-in ROM still
uses 260 M10Ks and cartridges 80. Logical mode alone does not select the
256x40 physical configuration. Both primitives now specify maximum_depth=256.

Before another full build, run the isolated two-store project on STUDEER:
`quartus_sh -t tools/probe_rom_storage.tcl` from the repository root.
It uses the same device and RTL, performs synthesis and fitting, and stores
reports under `.remote-build/rom-probe/output_files`. It does not modify the
BBCMicro project or overwrite its reports. Target combined usage is 257 M10Ks.
Altera memory-model simulation passes after the segment-depth change.

Isolated probe completed successfully on STUDEER at 17:58 on 27 October,
source 8bf8943. Fitter measured 205 M10Ks for built-in ROM and 52 for
cartridges (257 total), and 4,518 ALMs. This proves the depth constraint
saves 83 M10Ks against the previous full build's 260+80. Holding all other
resources constant predicts 539/553 for the full core. The probe has no
board-level timing constraints; it validates storage implementation and
placement only, not the full core's timing closure.

## Full build 20261027-180055-09a7fef1

Completed successfully at 18:42:36, exit code 0, fresh 4,254,340-byte RBF.
Actual full-core usage: 544/553 M10Ks and 26,166/41,910 ALMs (62%). The
memory-capacity problem is resolved. Do not treat compiler success as timing
closure: worst setup slack is -31.630 ns; worst hold slack is +0.076 ns.

### Critical-path diagnosis and pipeline correction

`quartus_sta -t tools/report_critical_timing.tcl` extracts the detailed paths
from the fitted database into `.remote-build/critical-setup.rpt`.
Worst path: BBCMicro ext_A[14] -> built-in ROM address register, through
the inferred division-by-five circuit. Data delay 34.100 ns, 32 logic levels,
10.417 ns clock period; gated-source clock skew adds -7.617 ns.

Replace combinational /5 and %5 with two address pipeline stages: capture
the address, then register the product with ceil(2^20/5)=209716. Its high bits
give the exact quotient for every 18-bit address. Compute the three-bit
remainder from aligned low address/quotient bits. The M10K read is the third
stage. Cartridge slot base travels through matching stages. Built-in uploads
use group/lane counters and restart only on byte address zero.

The BBC bus scheduler (`rtl/bbc_micro_core.vhd`, CPU memory latch and ext_A
processes) holds the selected CPU address over a multi-tick memory cycle.
The new fixed read latency is three 96MHz cycles (~31.25 ns), rather than one.
Tests check all 262,144 quotient/remainder pairs with an address every cycle,
all built-in ROM bytes with gapped uploads, all cartridge slots in both models,
and Altera MIF initialization. Timing closure still requires a new full fit;
no timing exceptions have been added to hide the critical path.

## Full build 20261027-190928-fd6f2260

Source d177c92 completed at 19:39:10 with exit code 0 and a fresh
4,213,620-byte RBF. Usage 544/553 M10Ks, 25,813 ALMs. Setup slack improved
to -9.653 ns; hold slack is -0.087 ns. This is not timing closure.

Detailed setup paths now lead from T65 address/control logic into SCSI
data_reg (13.383 ns data delay, -6.357 ns clock skew) and from JPEG chroma
RAM through the color conversion into pixel_g_q (18.305 ns data delay).
The hold path is m128 -> BBC CRTC r14_cursor_h[5], with 6.355 ns skew.

### Corrections

* Register the BBC bus tuple in `aiv_scsi_bus_register` on the BBC's 48 MHz
  clock. The existing 96 MHz engine consumes the captured strobe once at
  the following ce_48 edge. The original CPU cycle still reads the previous
  adapter byte before its acknowledgement. No command protocol changes.
* The new 48 MHz register bank receives the same two-parent-cycle setup / 
  one-cycle hold constraint as the existing BBC register bank. The exception
  is restricted to `emu|scsi_bus|*`; no relaxation is added to the 96 MHz
  SCSI engine or JPEG pipeline. This represents the actual capture period.
* Split YCbCr conversion into sample, multiply, partial-sum and clip stages.
  All stages and coordinates freeze together on output backpressure. Preserve
  original signed 32-bit rounding/wraparound/clip behavior. Idle waits for
  every stage to drain, including the final accepted pixel.
* Capture reset-time model selection m128 on the falling system clock edge,
  separating it from the delayed/gated BBC rising edge that caused the hold
  race. The selected model remains constant during normal operation.

Validation: actual Master CPU + diagnostic ROM at initial phases 0/1/7/15
passes (290 accepted command/data writes, 256 TX and 256 RX payload bytes).
Legacy duplicate-strobe failure remains reproducible. JPEG standalone test
compares 3,510 bit-exact pixels with bubbles, long stalls, flushes and overflow
inputs. Integration through the real Altera Y/Cb/Cr RAM models passes all
64 monochrome, 64 4:4:4 and 256 4:2:0 pixels, including coordinates and idle
drain. The test producer reserves a full block, matching the IDCT interface;
inport_accept is not a per-coefficient ready signal.

Physical timing closure and final DSP/memory usage remain pending the next
full build on STUDEER.

### STUDEER result, 27 October 2026, build 20261027-195844-351cf097

Source 395ffd9 completed successfully at 20:28:59 (exit 0, elapsed 30m15s).
The new RBF is 4,218,220 bytes, timestamp 20:28:40. Fit uses 26,161/41,910
ALMs (62%), 4,788,849 block-memory bits (85%) and 72/112 DSP blocks (64%).
Timing is still failing: setup -5.578 ns, hold -2.338 ns. A separate
read-only TimeQuest run confirmed the worst paths:

* Setup: BBC CRTC odd_field to domesday_compositor rdaddr2[21], data delay
  9.260 ns and clock skew -6.405 ns. Next path is the same source to bit 19.
* Hold: keyboard keys[9][7] to system_via ca2_ip_reg_c, data delay 4.004 ns
  and clock skew +6.342 ns. Second violation: keys[9][6] to r_ira[7],
  -1.088 ns slack.

The previous SCSI/JPEG paths are no longer the worst reported paths; this
does not by itself prove that every path in those blocks passes. Next inspect
the compositor input boundary and keyboard-to-BBC clock relationship. Do not
treat compiler success as timing closure. This RBF has not been deployed.

### Next timing correction and test deployment

The user requested a provisional hardware test despite timing violations.
Transferred the 395ffd9 RBF to `/media/fat/_Computer/BBCMicro_Domesday_test.rbf`
on 27 October, verifying SHA-256
`070ac5d3ea14bde0e6442a0f2f90ed1807038e100012ae21dd10f8a11e906677`.
The running core was not reloaded remotely.

Next source change moves misterkeyboard from clock_32 to clock_48, matching
its one-cycle mhz1_clken pulse and VIA consumers. This removes the 32/48 MHz
matrix crossing instead of masking its hold failures. CRTC odd_field is
captured in the compositor clock domain before the row-address arithmetic;
field parity changes in vertical blank before the first active-line fetch.
No new timing exceptions. Full placement/timing verification remains pending.

`tools/test_video_boundary.ps1` tests keyboard make/break, autoscan suppression,
single-cycle scan enables and BREAK, plus 1,536 actual compositor fetch
addresses (256 lines, two fields, three buffers). The video test isolates
scanline addressing by holding shown high and DDR busy; it does not verify
DDR throughput or decoded image quality. Upstream research is recorded in
`beebfpga-upstream-review.md`; functional upstream ports remain separate.

Timing-correction build started on STUDEER at 20:51:11, source 79c099f,
build 20261027-205111-56d22070, worker PID 29840. Both boundary simulations
pass with zero errors/warnings; physical timing remains pending.

For rollback, also installed `BBCMicro_Domesday_previous.rbf` beside the
test RBF. It is `build/BBCMicro-cartridges-7c32fd7-local.rbf`, the local
26 October build whose hash matches the previously recorded deployment:
`3b9890fbee503efbcd7c7d946d27399e487b777634c7d5f28160856a667752db`.
This preserves the previous hardware-test baseline; it is not a claim of
verified timing closure. Both RBFs can be selected from the Computer menu.

Correction: the user reports that this local rollback RBF does not work.
It was previously deployed, but was NOT the build associated with the
confirmed SCSITEST pass and subsequent Domesday startup. Do not label the
local 3b9890fb build known-good. Conversation history identifies the actual
tested STUDEER build as 20261026-152243-054f1ada, 4,230,912 bytes, SHA-256
`153f2ae23fffedcd25d26379c02c948b559774cc245204add4db369d1cdea255`.
The user subsequently reported all SCSI tests passing, then LVFS menu and
Domesday startup with the BeebVFS1 image. That binary IS preserved locally
as `build/BBCMicro-cartridges-7c32fd7-studeer.rbf`. Installed with verified
transfer as `/media/fat/_Computer/BBCMicro_Domesday_verified_20261026.rbf`.
The local and STUDEER files have different hashes despite the common name;
identify deployed artifacts by hash and user test result, not source label.

User confirmed the 153f2ae2 STUDEER reference works; the new 395ffd9 RBF
does not boot correctly. At the user's request, remove only the `previous`
and `test` RBF names. Keep `BBCMicro_Domesday_verified_20261026.rbf`.
Future deployed builds use trailing sequence numbers, starting with
`BBCMicro_Domesday_01.rbf`. Parent transfer script now chooses the next
unused number, refuses to overwrite numbered builds, and records local
path/hash/verification in `build/mister-deployments.jsonl`.

### Result: build 20261027-205111-56d22070 (source 79c099f)

Completed 27 October at 21:22:48, exit 0, elapsed 31m35s. Fresh RBF:
4,209,468 bytes, timestamp 21:22:29. Fit: 26,131 ALMs (62%), 546/553 RAM
blocks, 72/112 DSPs. Hold now passes on all reported clocks (core +0.356 ns;
global worst +0.252 ns). Setup still fails at -6.227 ns, TNS -5471.498 ns.

A fresh read-only timing inspection identifies scsi_bus addr_q[0] to
aiv_scsi data_reg[4] as the worst setup path: data delay 9.863 ns, skew
-6.451 ns. The boundary register remains on the physically delayed gated
48 MHz clock; its output still feeds a long 96 MHz adapter path. Next
inspect retiming the captured bus into parent-clock registers and validating
the exact CPU read/ack ordering with the existing real-CPU regression.
The keyboard hold fix succeeded; compiler success is still not timing
closure. This build has not been deployed or assigned version _01.

### Version 01 and next SCSI boundary correction

At the user's explicit request, deployed the 79c099f RBF despite the remaining
setup failure as `BBCMicro_Domesday_01.rbf`. Verified SHA-256:
`11a492b51dcc059c49d30234143e1ebaed117018ceba929784557824e2f2953f`.
The separately named, user-confirmed 26 October reference remains available.

Next correction: clock scsi_bus directly at 96 MHz with ce_48 as a capture
enable, rather than clocking it from the physically delayed gated clock.
The tuple is sampled before the BBC clock advances the CPU; the adapter
still consumes the previous captured tuple on the following ce_48 edge.
The register-to-adapter path now launches from the same parent clock as its
destination. The existing two-cycle constraint into the capture bank reflects
its capture enable; no extra timing relaxation is added. Keep CPU read-before-
ack ordering and duplicate-write regression coverage. Extend the real-CPU
tests to four phases with both zero and 6.5 ns gated-clock insertion delay.
Simulation is not a substitute for the next placed timing report.

Validation: all eight real-CPU/diagnostic-ROM cases pass (phases 0/1/7/15,
each at zero and 6.5 ns insertion delay), 290 accepted writes and 256-byte
TX/RX in every case. Legacy double-write failure still reproduces. The clock
test uses transport-delayed edges: a delayed continuous assignment would
filter out the narrow gated pulse instead of modelling insertion delay.

### Result: build 20261028-064206-eb815f96 (source 56ff090)

Completed 28 October at 07:13:08, exit 0, elapsed 30m56s. Fresh RBF:
4,200,660 bytes, timestamp 07:12:49. Fit: 26,098 ALMs (62%), 546/553 RAM
blocks and 72/112 DSPs. The SCSI parent-clock correction removed SCSI from
the reported worst paths. Timing remains open: setup -4.104 ns, TNS
-9215.018 ns; hold -0.360 ns, TNS -1.035 ns.

Worst setup now runs from color_pipeline y_pos_o through fb_writer's
coordinate-dependent px_ready feedback to the Cb FIFO count register:
13.375 ns data delay, -0.816 ns skew. Break that combinational feedback by
holding px_ready low for every in-flight DDR write. The writer still combines
all pixels of an open 64-bit group before launching its write; it only gives
up overlap between a DDR acknowledgement and collection of the next group.
No JPEG arithmetic, coordinates, FIFO contents or DDR data layout change.

Validation adds `tb_fb_writer_backpressure`: eight pixels become exactly two
full-byte-enable 64-bit writes at halfword addresses 0 and 4 while a delayed
DDR acknowledgement exercises 14 stalled cycles. No pixels are lost or
duplicated. Existing JPEG color and output tests remain bit-exact for 3,510
pipeline pixels plus monochrome, 4:4:4 and 4:2:0 integration cases.

Worst hold is now ram_high M10K port-B write-enable to BBC tube/cpu/video
memory data registers (-0.360/-0.351/-0.324 ns) across the delayed BBC clock.
Do not mask this with a timing exception. Defer a functional memory-boundary
change until its CPU/video/Tube cycle latency is separately simulated.

Also corrected built-in upload tracking: ioctl_wr can have gaps; a low strobe
must not reset the byte-group accumulator. A simulation uploads and reads all
262,144 bytes with gaps, including the final partial word. Cartridge simulation
checks all bytes in all four slots and both models, plus invalid uploads.

The MIF parser now reads WIDTH from the file. The previous 32-bit change also
used a 32-bit reader for the unchanged 40-bit scsi_diag.mif, so a self-consistent
round-trip alone was insufficient to prove the embedded diagnostic was intact.

### Result: build 20261028-072547-624aa98f (source 0fd2d47)

Completed 28 October at 07:56:56, exit 0, elapsed 31m07s. Fresh RBF:
4,229,352 bytes. Fit: 26,777 ALMs (64%), 546/553 RAM blocks and 72/112
DSPs. Removing the coordinate-dependent JPEG writer ready loop improved
setup from -4.104 ns to -3.276 ns and reduced setup TNS from -9215.018 ns
to -2809.791 ns. Hold now passes at +0.232 ns. Every non-core setup clock
passes; HDMI has the smallest positive margin at +0.079 ns.

The twelve worst setup paths now all launch from BBC ext_A[14/16/17] into
the inferred ram_low/ram_high M10K write-enable decoder. The worst path has
7.980 ns data delay and -5.383 ns clock skew. This is a real phase-boundary
problem: ext_A launches from the delayed, gated 48 MHz BBC clock, but the
RAM was capturing on the next rising edge of the 96 MHz parent clock. The
clock-tree difference leaves only about 5 ns of effective setup time.

Next correction moves the inferred BBC RAM read, write and old_nWE capture
to the falling 96 MHz edge. This remains before the next gated BBC rising
edge, so it does not add a BBC memory cycle, while giving the RAM address and
write-enable decoder the opposite parent-clock phase. No timing exception is
added. Boundary and JPEG regressions still pass; the first parallel invocation
briefly collided in the shared ModelSim work library, and the isolated rerun
completed with zero errors or warnings. Physical verification is pending a
new STUDEER build.
