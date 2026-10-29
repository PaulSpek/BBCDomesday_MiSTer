# BeebVFS1 !BOOT analysis, 28 October 2026

Read-only input: MiSTer `/media/fat/BBCMicro/Domesday/BeebVFS1/scsi0.dat`.
Local image SHA-256:
`6b8ca639a240c81e4efde1b2cc55ca186c654c4e6af5ff3ef9107f6e7d9e42af`.
Extraction script: `tools/inspect_vfs_boot.py`. Local extracted binaries,
directory listing, strings and linear disassemblies are in
`../../build/BeebVFS1-analysis/` (not committed).

## Verified metadata and startup

The root directory is old-map ADFS (`Hugo`). !BOOT is a 16,464-byte executable
at sector 24 (256-byte sectors), with load and execution addresses &0E00.
It is not BASIC or a textual *EXEC script.

Other extracted files: INIT (492 bytes), ROOT (1164), STINIT1 (5568),
STINIT2 (3320) and USERKERN (16534, load/exec &0E00). Their presence does
not establish their execution order; the initialization files are binary.

Entry &0E00 loads X/Y with &4A5C and jumps to &4D04. The startup code
clears decimal mode, initializes the stack, reads descriptor words via
&4E29 and initializes memory via &4E3E. Later paths call OSBYTE &82/&84
and transfer indirectly through &0054. Code and descriptor data must be
decoded together; a whole-file linear disassembly includes data as opcodes.

The routine beginning at &4E0F fetches a byte through &0006, uses it to
look up a handler address and jumps through &0052. Thus the executable
contains an interpreter/dispatch runtime.

## Correction to the previous fatal-error interpretation

!BOOT contains exactly the error-display strings from the earlier photo:
FATAL ERROR (&1BD5), PROGRAM ENDED (&1BE3), ENTER '*' COMMAND (&1BF1),
and P / PC / A / LAST 8 INSTRUCTIONS (&1C05).

Code at &1B24–&1BA0 prints this diagnostic and enters an OSWORD-0/OSCLI
command loop. The eight displayed instructions are bytes fetched near the
runtime stream pointer in &0006/&0007. The displayed PC must not be assumed
to be the native 65C02 instruction address. The previous claim that the
screen came from the coprocessor ROM was incorrect: the application runtime
had already been reached. The root cause of its error remains unknown.

## Dependencies and next measurement

The binary contains `*SRWRITE FFFF3000 +500 0000` (&2373),
`*SRREAD FFFF3000 +500 0000` (&2391), POINTER, TSET, FCODE, SEARCH, PLAY,
STEP, STILL, RESET and AUDIO commands. It also contains overlay load/link
failure messages (&1C88/&1CAE) and a file-not-found format (&2FFF).

These show sideways-memory, host-service, overlay and videodisc dependencies,
but not which call hangs. Tube Elite and SCSITEST do not exercise all these
paths, and setup timing remains open at -3.341 ns.

Next trace boundary: executed OSFILE/OSGBPB/OSCLI/OSWORD requests and return
values, runtime stream PC and recently dispatched opcodes. Capture the last
completed request to distinguish an overlay load, sideways-memory service
or videodisc operation. Static inspection alone cannot locate the current
hang or establish a Tube/SCSI handshake deadlock.

## Executed parasite-code trace

`tools/trace_vfs_boot.py` now executes the original image's !BOOT with a
py65 65C02 and ideal RAM. It models a small, explicit subset of MOS calls:
parasite memory queries, OSBYTE settings, captured character output and
read-only OSFILE metadata/load operations using the actual image files.
Unsupported services stop the run and record registers and recent native
instructions. No successful videodisc response is invented.

Run from the project parent directory:

```powershell
python core/tools/trace_vfs_boot.py build/BeebVFS1-scsi0.dat --dependencies build/boot-analysis-deps --output build/BeebVFS1-analysis/execution-trace.json
```

Observed sequence with the documented initial-memory assumptions:

1. OSFILE 5 reads ROOT metadata; OSFILE FF loads its 1164 bytes at &4B3C.
2. OSFILE 5 reads INIT metadata; OSFILE FF loads its 492 bytes at &4FD0.
3. At instruction 144427, the executable calls OSCLI at &FFF7 with
   X/Y=&338D: `FCODE I0` followed by CR. No screen text has been emitted.

This is a deliberate model boundary, NOT a reproduced hardware hang.
MOS/VFS/Tube firmware and FPGA hardware are not executed in this harness;
all OSFILE data bypasses those layers. The runtime PC in &6 points at a
service wrapper here and is not necessarily the caller's application PC.
The trace nevertheless establishes a concrete early hardware measurement:
does loading ROOT and INIT complete, and does `*FCODE I0` return?

The local Pi1MHz source `src/BeebSCSI/fcode.c` identifies I0 as disabling
front-panel buttons and explicitly documents no player reply for I0/I1.
Thus absence of an F-code payload for I0 is not itself an error. VFS still
needs its SCSI transaction to complete. The hypothesis that the first
hardware stall is ?F has not been established by this execution trace.

The tracer options `--ack-fcode-init --interlace-on` deliberately advance
through only the documented reply-less initialization burst (`I0`, `J0`,
`$0`) and the interlace state already confirmed on hardware. The next calls
observed are OSBYTE `&90` and `&72`; no general OSCLI success or videodisc
reply is fabricated.

## Video-call isolation experiment

`tools/patch_vfs_boot_video_gate.py` produces two separate images documented
in `docs/boot-video-isolation.md`. One stops visibly before the first known
LaserVision OSCLI command. The other bypasses only those command tokens and
allows the remaining executable to continue. Comparing both images on the
26 October reference core and the current core distinguishes corruption before
the first video call from a fault triggered by entering the video command
path. It does not by itself distinguish logic errors from open timing paths.
