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

## Mounted-media integration baseline

The first Domesday-specific RTL boundary is now present in
`rtl/domesday/domesday_bridge.sv`:

- MiSTer virtual disk slot 3 accepts native Pi1MHz `.PVF` LaserDisc images;
- mount/unmount events and image size are latched independently of the BBC
  floppy and MMFS slots;
- sector zero is read and the PVF1 magic, version, geometry, timing, index/data
  offsets, frame count, and maximum access-unit size are validated;
- an optional OSD setting lights the user LED only for a valid PVF header.

This isolates the next stage: PVF index/record streaming and the HPS H.264
decode benchmark can use the established slot without changing the existing
BBC storage interfaces again.

## Upstream relationship

The implementation clone uses `origin` for the personal fork and `upstream`
for `sharpie7/BeebFpga_MiSTer`; `source-local` retains the shallow local
research checkout. The fork is published as
`PaulSpek/BBCDomesday_MiSTer`, with `domesday-main` as its default branch.

The passwordless STUDEER Quartus host and MiSTer deployment path are documented
in the local, untracked `REMOTE_ACCESS.md` file. Their private keys are kept
outside the repository.

## Validation order

1. Build this branch on the STUDEER Quartus host.
2. Confirm the RBF still boots BBC Master 128 on MiSTer.
3. Mount a `.PVF` through the new OSD entry and confirm the optional Domesday
   status LED lights only after its PVF1 header has been read and validated.
4. Record resource/timing output with `MISTER_FB` enabled but inactive.
5. Add PVF index/record streaming and benchmark native H.264 decode before
   enabling the compositor.
