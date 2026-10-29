# BeebVFS1 staged boot checkpoint images

Three separate copies of the BeebVFS1 SCSI image stop at successively later
boundaries in the original `!BOOT` executable:

- `scsi0-check-root01.dat`: after the OSFILE load of `ROOT`.
- `scsi0-check-init01.dat`: after the OSFILE load of `INIT`.
- `scsi0-check-fcode01.dat`: immediately before the first `FCODE` OSCLI call.

Each image prints a persistent `REACHED` line and deliberately loops. ROOT is
1164 bytes at parasite address `&4B3C`, with additive 16-bit checksum `&C6E7`.
INIT is 492 bytes at `&4FD0`, checksum `&A99A`. The FCODE checkpoint prints
both checksums. The checksum is calculated from the bytes actually present in
coprocessor RAM, not from the disc image.

The source image is copied read-only. Only `!BOOT`, its unused allocation
slack and its directory length are changed. The checkpoint occupies
`&F000-&F2FF`; standalone copro-RAM testing has passed this range on version
05, but the patch still changes timing and should be compared with the same
images on the verified 26 October core.

Build from the project directory:

```powershell
python core/tools/patch_vfs_boot_checkpoints.py build/BeebVFS1-scsi0.dat build --beebasm build/beebasm/bin/beebasm.exe
```

MiSTer copies are under `/media/fat/BBCMicro/Domesday/BeebVFS1/`:

- `scsi0-check-root01.dat`: SHA-256 `c9ae3a815eb182e7c4327ee6518f40d18927679febe79e3017eae37f8ef791d3`
- `scsi0-check-init01.dat`: SHA-256 `8fcaded8aab66c33ebbf3a7916338b8c31b109fc8d51423b36616cb32c7a57ca`
- `scsi0-check-fcode01.dat`: SHA-256 `2a96af65ec2b237d30a177cdd7a7bb83266be2668813fbf71215f24bbceae1e0`

First version-05 hardware result: the ROOT checkpoint hangs without showing
its `REACHED` line. The verified 26 October result is still required for the
same image, but earlier checkpoint instrumentation worked there. On version 05
the failure is therefore at or before completion/return of the first ROOT
OSFILE load, before INIT and before the first video command.
