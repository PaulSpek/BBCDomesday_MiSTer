# BeebVFS1 video-call isolation images

Two diagnostic copies of `scsi0.dat` isolate the point where !BOOT starts
using the LaserVision command interface. The source image remains unchanged.

`scsi0-video-stop01.dat` runs the original startup and file-loading path. At
the first OSCLI command whose token is `FCODE`, `SEARCH`, `PLAY`, `STEP`,
`STILL`, `RESET` or `AUDIO`, it prints the command followed by
`STOPPED BEFORE VIDEO CALL` and deliberately waits forever. Seeing that text
proves that execution reached the video-call boundary; the command itself was
not issued.

`scsi0-no-video01.dat` runs the same code, but returns locally from those
commands without sending them to VFS/Pi1MHz emulation. Other OSCLI commands,
all file operations and the rest of !BOOT are left intact. OSCLI has no
defined result, so the bypass returns A=0 with carry clear through !BOOT's
existing service-call epilogue. This is an isolation experiment, not a
complete simulated player: later application code can still fail because it
does not receive real player state or video frames.

Both images install a one-page gate at parasite address &F000. Static analysis
of this executable places its allocator ceiling at &EFFC and the Tube ROM at
&F800. The test still changes startup timing and depends on that memory range;
results must therefore be compared on the same core and configuration.

Build from the project root with:

```powershell
python core/tools/patch_vfs_boot_video_gate.py build/BeebVFS1-scsi0.dat build/BeebVFS1-video-stop01-scsi0.dat build/BeebVFS1-no-video01-scsi0.dat --beebasm build/beebasm/bin/beebasm.exe
```

Mount each image as the Domesday VFS/SCSI image and reload the core before
running `!BOOT`. The original `scsi0.dat` and the earlier debug images can be
selected again without modification.
