# BBC Master SCSI diagnostic ROM

The diagnostic is a 16 KiB service ROM in Master sideways slot 1. Source:
`roms/scsi_diag.asm`. It follows the header and service-call conventions in
`../../docs/sidewrom.pdf`, including a type
byte of `&82`, title, copyright marker and service call 4. It claims only
`*SCSITEST`. It does not replace VFS in slot 8 or select a filing system.

Build from the project parent directory with BeebAsm v1.11:

```powershell
python core/tools/build_scsi_diag.py build/beebasm/bin/beebasm.exe
```

The generated `roms/scsi_diag.mif` is checked in so a remote Quartus build
does not require BeebAsm. The local `scsi_diag.rom` binary is ignored.

The core OSD can replace Master sideways slots 0 and 1 without rebuilding the
RBF. Slot 0 starts empty; slot 1 starts with this diagnostic ROM. In Master
mode choose **Load Master ROM slot 0** or **Load Master ROM slot 1** and select
an exactly 16,384-byte `.rom` file. The BBC is reset during the transfer so
the MOS rescans its ROMs. A short, oversized or non-sequential transfer makes
that slot invisible until a full ROM is loaded or the core is reloaded. The
file lives in FPGA RAM and must be selected again after reloading the core;
the built-in diagnostic returns in slot 1 on a fresh core load.

Both slots explicitly use MLAB distributed memory (`ramstyle = "MLAB,
no_rw_check"`). The previous implementation needed 32 extra M10K blocks and
failed fitting with error 170048 on the 553-M10K Cyclone V. MLABs use spare
logic resources instead, preserving the synchronous one-clock read interface,
MIF initialization, and the OSD loader without requiring external SDRAM.
Read-during-write data is unspecified: the BBC remains in reset throughout
the transfer and the slot is exposed only after all 16,384 bytes validate.
The first 16K x 8 MLAB version also exceeded the device's 985 memory LAB
locations. Each slot now packs two incoming bytes into one 16-bit write to an
8K x 16 memory. That reduces the required MLAB banks from 512 to 256 per slot.
MIFs use 8192 16-bit little-endian words; `.rom` uploads remain 16384 bytes.
Check both MLAB and M10K usage in the fit report after changing these memories.

To test the interface, choose Master mode and mount a `scsi0.dat` on the
Domesday LV-ROM OSD slot. At a `*` prompt type `*SCSITEST`.
Record all output, including FC41 hex on failure. The tests are:

1. BUS FREE flags before selection.
2. TEST UNIT READY on host ID `&10`.
3. READ CAPACITY(10), printing all eight response bytes.
4. READ(6) at logical block 0, reading 256 bytes and printing an additive
   eight-bit checksum. This checksum is informational until compared with
   the same sector of the mounted image.
5. WRITE F-code `?P` and READ F-code, confirming the reply begins with `P`.

Each phase wait times out after a bounded number of status polls. On failure,
the ROM reports the last FC41 byte and continues with a fresh selection. A
PASS means this test completed, not that the full Pi1MHz command set or VFS
works. The ROM uses zero-page `&70–&78` as transient command workspace; it
does not claim permanent RAM or intercept IRQs. The test does not write media.

The test source intentionally avoids use of the current filing system, so it
can run even when `*VFS` hangs. If the command is not recognized, inspect the
Master ROM list and whether the slot 1 image was actually loaded by the RBF.

Hardware result, 2026-10-26: the initial MiSTer run reported BUS FREE `PASS`
and returned a valid READ CAPACITY response (`00 00 24 00 00 01 00 00`), but
marked completed commands `FAIL FC41=E3`. `E3` is the correct message-in
phase: C/D, I/O, REQ, BSY and MSG are all high. The diagnostic originally
expected `63`, incorrectly omitting C/D. The corrected ROM expects `E3`; this
does not change the FPGA SCSI adapter.

Version 1.1 also prints the current X register as `X=nn` on a failure. For
READ6 it is the number of 256-byte data bytes already consumed; for F-code it
distinguishes a failure at the initial data-out/data-in phase (`X=00`) from a
later byte-transfer failure. TUR and CAPACITY use X while constructing their
CDB/data loop, so its value is only diagnostic for the streaming tests.

BeebEm check (2026-10-26): the initial ROM printed each diagnostic line over
the preceding one because it sent CR through OSWRCH. Text now uses OSASCI,
which advances to the next line. The updated standalone binary is at
`../../build/SCSITEST.rom` relative to this document.
