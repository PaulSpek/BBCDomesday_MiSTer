# Domesday Menu VFS/Tube timing-stress image

`scsi0-timing-stress01.dat` is a copy of the original 9472-byte
`Domesday/Menu/scsi0.dat`. The original is unchanged. Its existing `MENU`
allocation is replaced by a 65C02 executable and deterministic payload; the
existing `!BOOT` runs that executable. No filesystem allocation or image size
changes are needed.

The executable performs 256 OSFILE loads of the complete 7238-byte `MENU`
file, alternating parasite destinations `&3000` and `&5000`. After every load
it verifies offsets `&0400-&1C45` (6214 bytes) against a known address-derived
pattern. This repeatedly exercises the same VFS/Tube bulk-load path on which
the version-05 ROOT checkpoint hangs. It does not exercise LaserVision player
commands.

Installed MiSTer path:
`/media/fat/BBCMicro/Domesday/Menu/scsi0-timing-stress01.dat`.
Its SHA-256 is
`0d249044c0d57275777f17b7416261f3a6b0dd426aeb78b30d283e38ca5344a7`.

The display updates `PASS nnnn` after each verified load. Success ends with
`DONE: 0100 LOADS PASS`. A mismatch reports iteration, destination, file
offset, expected byte and received byte, then stops. No initial banner means
the first executable load itself did not complete reliably.

Build and validate:

```powershell
python core/tools/make_menu_timing_stress.py references/Pi1MHz/tools/menu/scsi0.dat build/Menu-timing-stress01-scsi0.dat --beebasm build/beebasm/bin/beebasm.exe
python core/tools/test_menu_timing_stress.py build/Menu-timing-stress01-scsi0.dat --dependencies build/boot-analysis-deps
python core/tools/test_menu_timing_stress.py build/Menu-timing-stress01-scsi0.dat --dependencies build/boot-analysis-deps --corrupt-iteration 3
```
