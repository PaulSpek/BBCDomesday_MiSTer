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

Also corrected built-in upload tracking: ioctl_wr can have gaps; a low strobe
must not reset the byte-group accumulator. A simulation uploads and reads all
262,144 bytes with gaps, including the final partial word. Cartridge simulation
checks all bytes in all four slots and both models, plus invalid uploads.

The MIF parser now reads WIDTH from the file. The previous 32-bit change also
used a 32-bit reader for the unchanged 40-bit scsi_diag.mif, so a self-consistent
round-trip alone was insufficient to prove the embedded diagnostic was intact.
