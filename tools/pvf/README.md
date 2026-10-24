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

## High-quality Domesday JPEG cache

`pvf_to_ddv.py` creates a Domesday-specific, DLV-inspired `DDV1` image for the
FPGA JPEG path. It preserves the PVF's original 832x576 geometry, 25 fps timing,
48 kHz stereo PCM and one independently seekable picture per PVF picture. The
container uses a 64-bit indexed JPEG offset, so high-quality full-resolution
conversions are not limited to 4 GiB like the arcade DLV format.

The JPEG encoder is deliberately invoked at `qscale=1`, its highest-quality
baseline setting. JPEG remains a lossy codec, so this is not a bit-perfect
conversion; it is the no-downscale, highest-quality reference cache. Keep the
original `.pvf` as the archival master.

The conversion requires a desktop FFmpeg build. It uses a temporary directory
for a concatenated H.264 stream, 48 kHz PCM, and concatenated MJPEG frames; a
full disc therefore needs substantial free disk space. It never modifies the
source PVF.

```powershell
Set-Location 'C:\Users\Dell\Projects\Domesday\core'
python .\tools\pvf\pvf_to_ddv.py `
    ..\P1MHzImages\video.pvf `
    ..\build\video-highquality.ddv `
    --ffmpeg 'C:\path\to\ffmpeg.exe' `
    --qscale 1
```

For an initial short inspection run, retain scratch data for diagnosis:

```powershell
python .\tools\pvf\pvf_to_ddv.py `
    ..\P1MHzImages\video.pvf `
    ..\build\pvf-first-250.ddv `
    --ffmpeg 'C:\path\to\ffmpeg.exe' `
    --frames 250 --keep-work
```

`DDV1` is intentionally not yet mountable by the current BBC RBF. The next RTL
stage will consume its 64-bit frame index, baseline JPEG payload and PCM data.

`slice_pvf.py` makes a small, valid PVF1 source image for an end-to-end test
without copying a complete disc to a build host. For one minute at 25 fps:

```powershell
python .\tools\pvf\slice_pvf.py ..\P1MHzImages\video.pvf ..\build\pvf-first-1500.pvf --frames 1500
```
