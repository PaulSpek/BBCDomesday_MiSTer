# Instrumented BeebVFS1 boot image 01

Original: `/media/fat/BBCMicro/Domesday/BeebVFS1/scsi0.dat`.
Diagnostic copy: same directory, `scsi0-debug01.dat`.
Load the diagnostic copy in the **Domesday LV-ROM volume** OSD entry;
keep the DDV mounted in the LaserDisc cache entry. Reload the core before
the test and use the same VFS/interlace/Tube configuration as the original
boot test. Run !BOOT the same way as before. No new RBF or sideways ROM is
required. Restore the original image in the OSD to remove all instrumentation.

Debug version 01 preserves the file's load/execute address &0E00 and patches
its native system-service wrapper. A small loader appended to !BOOT copies
debug code to &F000–&F0FF before the original startup. This address range is
above this executable's parasite allocator limit &EFFC and below the Tube
ROM at &F800. This choice applies specifically to the extracted BeebVFS1
executable, not arbitrary BBC programs. ROOT/INIT overlays overwrite the
disposable startup code but not the relocated instrumentation.

The hooks preserve A, X, Y and flags. They log:

```text
>FFDD 05 0494
<01 30
...
>FFF7 FF 338D FCODE I0
```

`>` marks entry to the general native service wrapper: target address,
accumulator argument and X/Y parameter pointer. OSCLI text is printed up to
64 characters. `<` marks return: accumulator and processor flags. The same
return hook also logs the runtime's direct OSBYTE calls, so a `<` line does
not always have a preceding `>` line. FFDD is OSFILE; FFF7 is OSCLI; FFF1 is
OSWORD. A final `>` without a subsequent `<` identifies an outstanding call
on this path. A hang after `<` can be inside the interpreter/application.
The OSWORD/CLI handler itself is not patched, nor are all possible native
call sites. Output uses the existing mode and output-stream settings.

The debug image is produced by `tools/patch_vfs_boot_debug.py`, with source
`roms/boot_debug.asm`. The source image is opened read-only and copied to a
new output path (existing output paths are refused). Only !BOOT contents,
its available slack sectors and the four-byte directory file length change.
No image geometry, other file or SCSI service is changed.

Validation: the original and patched executables were run using
`tools/trace_vfs_boot.py`. All intercepted service types, A/X/Y arguments,
filenames and file-load destinations are equal through ROOT and INIT loading
and the first FCODE I0 call. The patched run additionally emits the shown
entry/return text. This validates the executed prefix only, not the full
Domesday runtime, real MOS/Tube timing, or freedom from later code conflicts.
Screen output changes timing and may change reproduction of the hardware
fault. Photograph the final lines if it stalls; if it instead progresses,
record that as a timing-sensitive result.
