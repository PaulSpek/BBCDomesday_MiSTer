#!/usr/bin/env python3
"""Convert Pi1MHz PVF media to a seekable Domesday JPEG/PCM image.

The output is ``DDV1``: a deliberately Domesday-specific, DLV-inspired
container.  It has one independently-decodable baseline-JPEG picture per
source PVF picture and an index of 64-bit offsets.  The 64-bit index is
intentional: a full-resolution, high-quality JPEG conversion can exceed the
4 GiB limit of the arcade DLV ``u32`` index.

The source PVF is read-only.  Video is decoded by FFmpeg and re-encoded as
baseline MJPEG at the original geometry and cadence; PCM audio is copied from
each PVF record without resampling.  JPEG is a lossy codec, even at qscale 1,
so this tool preserves geometry and timing rather than claiming bit-perfect
pixels.
"""

from __future__ import annotations

import argparse
import json
import mmap
import pathlib
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass


PVF_MAGIC = 0x31465650  # little-endian "PVF1"
PVF_VERSION = 1
PVF_HEADER = struct.Struct("<16I")
PVF_RECORD = struct.Struct("<II")

DDV_MAGIC = b"DDV1"
DDV_VERSION = 1
DDV_HEADER_BYTES = 512
DDV_INDEX_ENTRY = struct.Struct("<QII")  # video-relative offset, size, reserved
DDV_FLAG_BASELINE_JPEG = 1
DDV_FLAG_PCM_S16LE = 2
DDV_HEADER = struct.Struct("<4s8I6Q3I")
SECTOR_BYTES = 512
COPY_CHUNK_BYTES = 1024 * 1024


@dataclass(frozen=True)
class PvFHeader:
    width: int
    height: int
    fps_num: int
    fps_den: int
    frame_count: int
    audio_rate: int
    audio_channels: int
    audio_bytes_per_frame: int
    max_video_bytes: int
    index_offset: int
    data_offset: int


def align(value: int, alignment: int = SECTOR_BYTES) -> int:
    return (value + alignment - 1) // alignment * alignment


def copy_stream(source, target, byte_count: int) -> None:
    remaining = byte_count
    while remaining:
        chunk = source.read(min(remaining, COPY_CHUNK_BYTES))
        if not chunk:
            raise ValueError("unexpected end of temporary file")
        target.write(chunk)
        remaining -= len(chunk)


def read_pvf_header(source) -> PvFHeader:
    raw = source.read(PVF_HEADER.size)
    if len(raw) != PVF_HEADER.size:
        raise ValueError("PVF header is truncated")
    fields = PVF_HEADER.unpack(raw)
    magic, version, width, height, fps_num, fps_den, frame_count = fields[:7]
    audio_rate, audio_channels, audio_bytes_per_frame = fields[7:10]
    index_offset, data_offset = fields[10:12]
    max_video_bytes = fields[12]
    expected_data_offset = PVF_HEADER.size + frame_count * 4
    if magic != PVF_MAGIC or version != PVF_VERSION:
        raise ValueError("input is not a supported PVF1 image")
    if not width or not height or not fps_num or not fps_den or not frame_count:
        raise ValueError("PVF has invalid geometry, timing, or frame count")
    if index_offset != PVF_HEADER.size or data_offset != expected_data_offset:
        raise ValueError("PVF has an unsupported index/data layout")
    if audio_rate != 48000 or audio_channels != 2 or audio_bytes_per_frame != 7680:
        raise ValueError(
            "this initial Domesday converter expects 48 kHz stereo PVF audio "
            "(7680 bytes/frame)"
        )
    return PvFHeader(
        width, height, fps_num, fps_den, frame_count, audio_rate, audio_channels,
        audio_bytes_per_frame, max_video_bytes, index_offset, data_offset,
    )


def read_offsets(source, header: PvFHeader) -> list[int]:
    source.seek(header.index_offset)
    raw = source.read(header.frame_count * 4)
    if len(raw) != header.frame_count * 4:
        raise ValueError("PVF index is truncated")
    offsets = list(struct.unpack(f"<{header.frame_count}I", raw))
    if offsets[0] < header.data_offset or any(b <= a for a, b in zip(offsets, offsets[1:])):
        raise ValueError("PVF index is not strictly increasing")
    return offsets


def extract_pvf_range(
    source_path: pathlib.Path,
    header: PvFHeader,
    offsets: list[int],
    start_frame: int,
    frame_count: int,
    h264_path: pathlib.Path,
    audio_path: pathlib.Path,
) -> None:
    """Write concatenated H.264 access units and matching PCM to scratch files."""
    end_frame = start_frame + frame_count
    with source_path.open("rb") as source, h264_path.open("wb") as h264, audio_path.open("wb") as audio:
        for number in range(start_frame, end_frame):
            source.seek(offsets[number])
            raw_record = source.read(PVF_RECORD.size)
            if len(raw_record) != PVF_RECORD.size:
                raise ValueError(f"PVF record {number} header is truncated")
            video_len, audio_len = PVF_RECORD.unpack(raw_record)
            if not video_len or video_len > header.max_video_bytes:
                raise ValueError(f"PVF record {number} has invalid video length {video_len}")
            if audio_len != header.audio_bytes_per_frame:
                raise ValueError(f"PVF record {number} has unexpected audio length {audio_len}")
            video = source.read(video_len)
            pcm = source.read(audio_len)
            if len(video) != video_len or len(pcm) != audio_len:
                raise ValueError(f"PVF record {number} is truncated")
            h264.write(video)
            audio.write(pcm)
            if number and number % 1000 == 0:
                print(f"extracted {number - start_frame}/{frame_count} PVF frames", flush=True)


def encode_mjpeg(
    ffmpeg: str,
    header: PvFHeader,
    h264_path: pathlib.Path,
    mjpeg_path: pathlib.Path,
    qscale: int,
) -> None:
    command = [
        ffmpeg, "-hide_banner", "-y",
        "-f", "h264", "-r", f"{header.fps_num}/{header.fps_den}", "-i", str(h264_path),
        "-map", "0:v:0", "-an",
        "-c:v", "mjpeg", "-q:v", str(qscale), "-pix_fmt", "yuvj420p",
        "-f", "mjpeg", str(mjpeg_path),
    ]
    print("running FFmpeg MJPEG encode", flush=True)
    subprocess.run(command, check=True)


def scan_mjpeg(path: pathlib.Path, expected_frames: int) -> list[tuple[int, int]]:
    """Return (offset,length) for each complete JPEG in a concatenated MJPEG file."""
    frames: list[tuple[int, int]] = []
    with path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        position = 0
        size = len(data)
        while position < size:
            start = data.find(b"\xff\xd8", position)
            if start < 0:
                break
            end = data.find(b"\xff\xd9", start + 2)
            if end < 0:
                raise ValueError(f"MJPEG frame {len(frames)} has no EOI marker")
            end += 2
            frames.append((start, end - start))
            position = end
    if len(frames) != expected_frames:
        raise ValueError(f"FFmpeg produced {len(frames)} JPEG frames; expected {expected_frames}")
    if not all(length and length <= 0xFFFFFFFF for _, length in frames):
        raise ValueError("a JPEG frame is empty or exceeds DDV index capacity")
    return frames


def write_ddv(
    output: pathlib.Path,
    header: PvFHeader,
    start_frame: int,
    frame_count: int,
    mjpeg_path: pathlib.Path,
    audio_path: pathlib.Path,
    frames: list[tuple[int, int]],
) -> None:
    video_size = mjpeg_path.stat().st_size
    audio_size = audio_path.stat().st_size
    expected_audio_size = frame_count * header.audio_bytes_per_frame
    if audio_size != expected_audio_size:
        raise ValueError(f"temporary PCM size {audio_size} does not match expected {expected_audio_size}")

    index_offset = DDV_HEADER_BYTES
    index_size = frame_count * DDV_INDEX_ENTRY.size
    video_offset = align(index_offset + index_size)
    audio_offset = align(video_offset + video_size)
    samples_per_frame = header.audio_bytes_per_frame // 4
    if header.audio_channels != 2 or samples_per_frame * 4 != header.audio_bytes_per_frame:
        raise ValueError("PVF audio is not 16-bit stereo PCM")

    ddv_header = bytearray(DDV_HEADER_BYTES)
    DDV_HEADER.pack_into(
        ddv_header, 0,
        DDV_MAGIC, DDV_VERSION,
        header.width, header.height, header.fps_num, header.fps_den, frame_count,
        header.audio_rate, header.audio_channels,
        index_offset, index_size, video_offset, video_size, audio_offset, audio_size,
        start_frame, samples_per_frame, DDV_FLAG_BASELINE_JPEG | DDV_FLAG_PCM_S16LE,
    )

    temporary = output.with_suffix(output.suffix + ".partial")
    if temporary.exists():
        temporary.unlink()
    try:
        with temporary.open("wb") as target, mjpeg_path.open("rb") as mjpeg, audio_path.open("rb") as audio:
            target.write(ddv_header)
            for offset, length in frames:
                target.write(DDV_INDEX_ENTRY.pack(offset, length, 0))
            target.write(b"\0" * (video_offset - target.tell()))
            copy_stream(mjpeg, target, video_size)
            target.write(b"\0" * (audio_offset - target.tell()))
            copy_stream(audio, target, audio_size)
        temporary.replace(output)
    finally:
        if temporary.exists():
            temporary.unlink()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path, help="source Pi1MHz video.pvf")
    parser.add_argument("output", type=pathlib.Path, help="output .ddv image")
    parser.add_argument("--ffmpeg", default="ffmpeg", help="FFmpeg executable (default: ffmpeg on PATH)")
    parser.add_argument("--qscale", type=int, default=1, choices=range(1, 32), metavar="1..31",
                        help="FFmpeg MJPEG quantizer; 1 is the highest quality")
    parser.add_argument("--start-frame", type=int, default=0, help="source PVF frame to start at")
    parser.add_argument("--frames", type=int, help="number of frames to convert (default: all remaining)")
    parser.add_argument("--work-dir", type=pathlib.Path, help="scratch directory; default is beside output")
    parser.add_argument("--keep-work", action="store_true", help="retain H.264, PCM and MJPEG scratch files")
    parser.add_argument("--overwrite", action="store_true", help="replace an existing output image")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.input.is_file():
        raise SystemExit(f"input PVF not found: {args.input}")
    if args.output.exists() and not args.overwrite:
        raise SystemExit(f"output already exists: {args.output} (use --overwrite to replace it)")
    if args.start_frame < 0:
        raise SystemExit("--start-frame must not be negative")
    if shutil.which(args.ffmpeg) is None and not pathlib.Path(args.ffmpeg).is_file():
        raise SystemExit(f"FFmpeg executable not found: {args.ffmpeg}")

    with args.input.open("rb") as source:
        header = read_pvf_header(source)
        offsets = read_offsets(source, header)
    frame_count = args.frames if args.frames is not None else header.frame_count - args.start_frame
    if frame_count <= 0 or args.start_frame + frame_count > header.frame_count:
        raise SystemExit("requested PVF frame range is outside the source image")

    work_dir = args.work_dir or args.output.with_suffix(args.output.suffix + ".work")
    if work_dir.exists() and any(work_dir.iterdir()):
        raise SystemExit(f"work directory is not empty: {work_dir}")
    work_dir.mkdir(parents=True, exist_ok=True)
    h264_path = work_dir / "video.h264"
    audio_path = work_dir / "audio.s16le"
    mjpeg_path = work_dir / "video.mjpeg"
    try:
        extract_pvf_range(args.input, header, offsets, args.start_frame, frame_count, h264_path, audio_path)
        encode_mjpeg(args.ffmpeg, header, h264_path, mjpeg_path, args.qscale)
        frames = scan_mjpeg(mjpeg_path, frame_count)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_ddv(args.output, header, args.start_frame, frame_count, mjpeg_path, audio_path, frames)
        manifest = {
            "format": "DDV1",
            "input": str(args.input),
            "width": header.width,
            "height": header.height,
            "fps": [header.fps_num, header.fps_den],
            "source_start_frame": args.start_frame,
            "frame_count": frame_count,
            "audio": {"rate": header.audio_rate, "channels": header.audio_channels, "bytes_per_frame": header.audio_bytes_per_frame},
            "jpeg": {"codec": "baseline-mjpeg", "qscale": args.qscale, "lossless": False},
        }
        args.output.with_suffix(args.output.suffix + ".json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {args.output} ({args.output.stat().st_size:,} bytes)")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"conversion failed: {error}") from error
    finally:
        if not args.keep_work:
            for path in (h264_path, audio_path, mjpeg_path):
                path.unlink(missing_ok=True)
            try:
                work_dir.rmdir()
            except OSError:
                pass


if __name__ == "__main__":
    main()
