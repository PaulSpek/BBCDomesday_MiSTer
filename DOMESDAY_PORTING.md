# Domesday port baseline

This tree is based on `sharpie7/BeebFpga_MiSTer` revision
`70e3cb4816538faccfc4233564668e34ceab5f4c`.

The first modernization is deliberately boot-safe:

- the MiSTer `MISTER_FB` macro is enabled in `BBCMicro.qsf`;
- the emu port uses `MISTER_FB`, matching `sys/sys_top.v`;
- inactive RGB565 framebuffer signals are driven to known values;
- the legacy duplicate SDRAM-control assignment has been removed.

This does not claim to implement the Domesday video path yet. `FB_EN` remains
low and the normal BBC video mixer remains active. The next change can therefore
add the Picmatic-derived DDR/JPEG path without first changing the top-level
contract again.

## Upstream relationship

The implementation clone uses `origin` for the personal fork and `upstream`
for `sharpie7/BeebFpga_MiSTer`; `source-local` retains the shallow local
research checkout. The fork is published as
`PaulSpek/BBCDomesday_MiSTer`, with `domesday-main` as its default branch.

The passwordless Linux build/staging host is documented in the local,
untracked `REMOTE_ACCESS.md` file. Its verified key is kept outside the
repository. The Linux host does not currently contain Quartus, so FPGA
compilation still requires the separate Quartus machine.

## Validation order

1. Build this branch unchanged on the Arc Quartus host.
2. Confirm the RBF still boots BBC Master 128 on MiSTer.
3. Record resource/timing output with `MISTER_FB` enabled but inactive.
4. Add the Picmatic `.dlv` streamer and JPEG decoder behind a new feature
   boundary, then re-measure before enabling the compositor.
