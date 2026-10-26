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
works. The ROM uses zero-page `&70–&87` as transient command workspace; it
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

Version 1.5 is usable with the existing RBF. It deliberately does not invoke
the unvalidated FPGA debug selectors from v1.2–v1.4. Its measurements are
collected by the ROM through normal SCSI registers. It prints:

`STEP/END EXP TX/RX: 02/00 22 00FE/0000`

- STEP: 01 write CDB, 02 write data, 03 write completion, 04 read CDB,
  05 read data, 06 read completion, 07 verify reply. 00 denotes earlier tests.
- END: 00 before completion, 01 waiting for status, 02 waiting for message,
  03 waiting for bus free or checking the completion bytes.
- EXP: expected phase, compared against FC41 masked with E3.
- TX/RX: separate 16-bit hexadecimal counts of F-code data writes/reads
  performed by the ROM. 0100 means 256. These do not prove FPGA acceptance.

`VALID S/M REPLY: 01 02/00 00 00 00 00 00 00 00`

- VALID: bit 0 means S (status byte) was captured; bit 1 means M (message)
  was captured. Ignore S/M values whose validity bits are clear.
- REPLY: first seven F-code reply bytes. Only bytes below RX are valid.
- A pending STATUS byte at a failed streaming wait is read once, before
  printing, to record whether it contains GOOD (00) or CHECK CONDITION (02).
- X is saved immediately on entry to the failure handler, before output.

Run `tools/test_scsi_diag.py` with py65 installed after assembling. It executes
the actual service ROM against a scripted register model for success, a short
write at 254 bytes, and a short read at 254 bytes. It checks the step, counters,
status validity and reply capture. This validates ROM reporting; real BBC bus
timing and the cause of the FPGA failure still require hardware measurements.

Increment the displayed and header version for every diagnostic revision.

BeebEm check (2026-10-26): the initial ROM printed each diagnostic line over
the preceding one because it sent CR through OSWRCH. Text now uses OSASCI,
which advances to the next line. The updated standalone binary is at
`../../build/SCSITEST.rom` relative to this document.
