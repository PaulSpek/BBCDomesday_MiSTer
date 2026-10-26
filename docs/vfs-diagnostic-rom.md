# VFS checkpoint ROM

`tools/build_vfs_diag.py` produces a diagnostic copy of the Acorn VFS 2.02
ROM. The supplied source ROM is read-only input and is never overwritten.
The generated file remains 16 KiB and retains the original `*VFS` command.

The diagnostic overlay replaces the long `*HELP VFS` text area in the copy.
Seven three-byte calls in the VFS startup path are redirected to wrappers in
that area. Each wrapper first executes the displaced original instruction,
prints a checkpoint using `OSASCI`, and restores flags and A/X/Y exactly as
they were after the original instruction.

Build and check it from the parent project directory:

```powershell
python .\core\tools\build_vfs_diag.py `
  .\build\beebasm\bin\beebasm.exe `
  .\references\Pi1MHz\firmware\Pi1MHz\VFS.rom `
  .\build\VFS-DIAG.rom
python .\core\tools\test_vfs_diag.py `
  .\references\Pi1MHz\firmware\Pi1MHz\VFS.rom `
  .\build\VFS-DIAG.rom
```

The output lines have this form:

```text
VFS-D1 I=01
```

`I` is the byte at `&0291`, tested by the original ROM immediately before it
prints `Turn interlace on`. The checkpoints are:

| Marker | Original call completed | Meaning |
| --- | --- | --- |
| D1 | `JSR &B6B8` at `&90D3` | Immediately before the interlace-state test |
| D2 | `JSR &B6B8` at `&90E1` | Interlace-state test passed |
| D3 | `JSR &8E89` at `&90EB` | VFS configuration/status read completed |
| D4 | `JSR &9AAE` at `&9121` | First main workspace setup section completed |
| D5 | `JSR &91FC` at `&9154` | First later startup checkpoint completed |
| D6 | `JSR &873D` at `&917C` | Following startup operation completed |
| D7 | `JSR &91FC` at `&91D6` | Final instrumented startup checkpoint completed |

The original error text is preserved. If output stops after D1 and then shows
`Turn interlace on`, the ROM has branched on a non-zero `&0291` before the
remaining VFS startup path. If D2 or later appears, report the last marker and
its `I` value.

This ROM is intended to replace the fixed VFS ROM for a diagnostic build.
Loading it concurrently into cartridge slot 0-3 while the normal VFS remains
in fixed slot 8 would create two copies of the same filing-system ROM and is
not a controlled test. `*HELP VFS` is intentionally suppressed in the
diagnostic copy because its storage contains the overlay.
