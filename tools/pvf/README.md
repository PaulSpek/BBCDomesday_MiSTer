# PVF H.264 throughput benchmark

`extract_h264_sample.py` copies consecutive, independently decodable H.264
access units from a Pi1MHz PVF into a standard Annex-B stream. It never modifies
the source and deliberately omits PCM audio.

Generate a ten-second sample from the representative disc:

```powershell
python tools/pvf/extract_h264_sample.py `
  ../P1MHzImages/video.pvf ../build/pvf-benchmark-250.h264 --frames 250
```

The manually dispatched `Build MiSTer H264 benchmark` workflow builds a static
ARMv7/NEON FFmpeg binary from the pinned official FFmpeg source revision. Copy
the binary and sample to MiSTer, then measure pure video decode throughput with:

```sh
/media/fat/linux/ffmpeg-pvf-bench -benchmark -threads 2 \
  -i /media/fat/BBCMicro/pvf-benchmark-250.h264 -f null -
```

The decoder gate passes only if sustained speed is comfortably above `1.0x`
(25 fps) while the BBC core is running; target at least `1.25x` to retain margin
for PVF I/O, RGB conversion, audio and frame transport.
