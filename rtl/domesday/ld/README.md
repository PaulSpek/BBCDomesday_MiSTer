# Domesday LaserDisc video path

The baseline-JPEG decoder and DDR helpers were vendored from the local
`Arcade-Picmatic_MiSTer` reference at its pinned LaserDisc implementation.
`core_jpeg/` is Ultra-Embedded's Apache-2.0 `core_jpeg` at the revision noted
by that reference; its `LICENSE` is retained. `ddram.sv` retains its GPLv3
header. The surrounding BBC core is GPL-2.0-or-later, so the combined build is
distributed under the compatible GPLv3 option.

`domesday_video.sv` is the BBC-specific layer. It accepts the DDV JPEG byte
stream, decodes 832x576 RGB into a triple-buffered RGB565 DDR framebuffer and
hard-keys the BBC graphics over its central 640x512 raster.

The bridge starts with frame zero after a DDV mount.  Once a decoded frame is
adopted at BBC vertical blank, the compositor requests the next indexed DDV
frame, resets the JPEG engine and decodes it into the next free DDR buffer.
This provides sequential, tear-free video decomposition as the first playback
step. F-code-driven seek/play state, exact 25 fps pacing, PCM audio and the full
832x576 overscan window remain separate follow-up stages.
