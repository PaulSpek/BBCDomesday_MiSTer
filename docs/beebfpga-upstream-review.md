# BeebFpga upstream review, 27 October 2026

Reference clone: `../references/hoglet-BeebFpga`, from
https://github.com/hoglet67/BeebFpga . Compared against this core at 395ffd9.
`master` is f0c99eb (10 December 2024); active `dev` is 49c63cc
(23 October 2026, MMFS 1.61). Checking master alone misses recent work.
There are 100 commits touching src/common in master..dev; this is a targeted
review of relevant changes, not verification of every upstream commit.

## Candidates

* High priority: [f777c8f, VIA handshaking and double reads](https://github.com/hoglet67/BeebFpga/commit/f777c8fc2a9565dc3bf2780182fe831a46d5470d).
  Upstream fixes input latching, port A readback, VIA selection during
  stretched cycles, and floating/looped-back system VIA port A pins. Our
  m6522 still latches on ca1_int/cb1_int, and the core has the older keyboard
  port A loopback. Port the changes together and test the actual CPU/VIA bus
  under stretched reads, handshakes and keyboard scanning. This is distinct
  from our external AIV SCSI byte-acknowledgement fix.
* High priority, small candidate: [821d575, Timer 2 pulse counting](https://github.com/hoglet67/BeebFpga/commit/821d575e2302b2a7b2b5dc64671245514e3d1108).
  Adds `and ena` to timer completion. Our corresponding condition still
  lacks it. Test T2 under pulse counting and timed modes before adoption.
* Medium priority: [7e5cbea, SAA5050 hold mosaics](https://github.com/hoglet67/BeebFpga/commit/7e5cbea1e541eacb938c8af9f61ed590ce79af9f).
  Clears held graphics when returning to alpha and removes a release on
  alpha selection. Our teletext code has diverged, so do not transplant only
  these lines without comparing preceding teletext fixes and rendering tests.
* Medium priority: [7c0ad92, CRTC display enable](https://github.com/hoglet67/BeebFpga/commit/7c0ad929bc8c97988b8c6d0876ec7456d15e554a)
  and [527ca18, interlaced video judder](https://github.com/hoglet67/BeebFpga/commit/527ca18178837cd9566dae9deae7d4ee1c852eea).
  Our CRTC intentionally bypasses the mode 7 DE delay and exports its own
  ODD_FIELD_IO/HBLANK interface. Upstream changed video pipeline and field
  output semantics. Compare raster captures before changing alignment;
  its standalone scan doubler is not the MiSTer video pipeline.
* Lower priority for Domesday: 2026 TMS5220 speech accuracy, VideoNuLA
  scrolling/scandoubler corrections and MMFS 1.61. Useful separately; they
  do not resolve the current compositor and keyboard timing paths. MMFS is
  separate from the VFS ROM and AIV SCSI data path.

The `clock_rework` branch last changed in March 2020. It is not a recent
MiSTer clocking solution. Upstream targets several other boards; a full merge
would replace substantial board-specific memory, clock and video plumbing.
Also note the October 2026 revert of an earlier VIA shift-register clock fix:
an old commit with "fix" in its title is not automatically the preferred code.

## Action this round

Keep upstream functional changes separate from physical timing corrections.
Move our MiSTer keyboard matrix from clock_32 to clock_48, matching its
scan enable, matrix selectors and VIA consumers. Capture CRTC field parity
locally at 96 MHz before compositor row arithmetic. No timing exceptions
were added and no upstream functional changes were merged in this build.
After timing closes, VIA handshaking/readback is the first upstream port to
evaluate with a dedicated CPU/VIA simulation.
