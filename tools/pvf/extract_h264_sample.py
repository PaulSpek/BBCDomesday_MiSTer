#!/usr/bin/env python3
"""Extract consecutive self-contained H.264 access units from a Pi1MHz PVF.

The resulting Annex-B stream is intended for decoder throughput benchmarks.
PVF media remains read-only and no audio data is copied.
"""

from __future__ import annotations

import argparse
import pathlib
import struct


PVF_MAGIC = 0x31465650
PVF_VERSION = 1
HEADER = struct.Struct("<16I")
RECORD = struct.Struct("<II")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--start-frame", type=int, default=0)
    parser.add_argument("--frames", type=int, default=250)
    args = parser.parse_args()

    if args.start_frame < 0 or args.frames <= 0:
        parser.error("--start-frame must be non-negative and --frames positive")

    with args.input.open("rb") as source:
        raw_header = source.read(HEADER.size)
        if len(raw_header) != HEADER.size:
            raise SystemExit("PVF header is truncated")

        fields = HEADER.unpack(raw_header)
        magic, version, width, height, fps_num, fps_den, frame_count = fields[:7]
        index_offset, data_offset = fields[10:12]
        if magic != PVF_MAGIC or version != PVF_VERSION:
            raise SystemExit("not a supported PVF1 file")
        if fps_den == 0 or frame_count == 0:
            raise SystemExit("invalid PVF timing or frame count")

        end_frame = args.start_frame + args.frames
        if end_frame > frame_count:
            raise SystemExit(
                f"requested frames {args.start_frame}..{end_frame - 1}, "
                f"but PVF has {frame_count} frames"
            )

        source.seek(index_offset + args.start_frame * 4)
        raw_index = source.read(args.frames * 4)
        if len(raw_index) != args.frames * 4:
            raise SystemExit("PVF frame index is truncated")
        offsets = struct.unpack(f"<{args.frames}I", raw_index)
        if offsets[0] < data_offset or any(b <= a for a, b in zip(offsets, offsets[1:])):
            raise SystemExit("PVF frame offsets are invalid")

        args.output.parent.mkdir(parents=True, exist_ok=True)
        total_video = 0
        with args.output.open("wb") as target:
            for frame_number, offset in enumerate(offsets, args.start_frame):
                source.seek(offset)
                raw_record = source.read(RECORD.size)
                if len(raw_record) != RECORD.size:
                    raise SystemExit(f"record {frame_number} header is truncated")
                video_len, _audio_len = RECORD.unpack(raw_record)
                access_unit = source.read(video_len)
                if len(access_unit) != video_len:
                    raise SystemExit(f"record {frame_number} video is truncated")
                target.write(access_unit)
                total_video += video_len

    seconds = args.frames * fps_den / fps_num
    print(
        f"extracted {args.frames} frames ({seconds:.3f}s) at "
        f"{width}x{height} from frame {args.start_frame}; "
        f"wrote {total_video} bytes to {args.output}"
    )


if __name__ == "__main__":
    main()
