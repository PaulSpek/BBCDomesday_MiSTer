#!/usr/bin/env python3
"""Create a small, valid PVF1 frame-range slice for conversion tests.

The source PVF remains unchanged.  The output has a rebuilt index and contains
complete original records, so it can be supplied directly to ``pvf_to_ddv.py``.
"""

from __future__ import annotations

import argparse
import pathlib
import struct


HEADER = struct.Struct("<16I")
PVF_MAGIC = 0x31465650
PVF_VERSION = 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--start-frame", type=int, default=0)
    parser.add_argument("--frames", type=int, required=True)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    if args.start_frame < 0 or args.frames <= 0:
        parser.error("--start-frame must be non-negative and --frames positive")
    if args.output.exists() and not args.overwrite:
        parser.error(f"output exists: {args.output} (use --overwrite)")

    with args.input.open("rb") as source:
        raw_header = source.read(HEADER.size)
        if len(raw_header) != HEADER.size:
            raise SystemExit("PVF header is truncated")
        fields = list(HEADER.unpack(raw_header))
        if fields[0] != PVF_MAGIC or fields[1] != PVF_VERSION:
            raise SystemExit("input is not a supported PVF1 image")
        source_frames = fields[6]
        if args.start_frame + args.frames > source_frames:
            raise SystemExit("requested range is outside the source PVF")
        index_offset, data_offset = fields[10:12]
        offset_count = args.frames + (1 if args.start_frame + args.frames < source_frames else 0)
        source.seek(index_offset + args.start_frame * 4)
        raw_offsets = source.read(offset_count * 4)
        if len(raw_offsets) != offset_count * 4:
            raise SystemExit("PVF frame index is truncated")
        offsets_with_tail = struct.unpack(f"<{offset_count}I", raw_offsets)
        source_offsets = offsets_with_tail[:args.frames]

        records: list[bytes] = []
        for number, offset in enumerate(source_offsets, args.start_frame):
            source.seek(offset)
            if number + 1 < args.start_frame + args.frames:
                next_offset = source_offsets[number - args.start_frame + 1]
            elif len(offsets_with_tail) > args.frames:
                next_offset = offsets_with_tail[-1]
            else:
                source.seek(0, 2)
                next_offset = source.tell()
            source.seek(offset)
            record = source.read(next_offset - offset)
            if len(record) != next_offset - offset:
                raise SystemExit(f"PVF record {number} is truncated")
            records.append(record)

    new_index_offset = HEADER.size
    new_data_offset = new_index_offset + args.frames * 4
    new_offsets: list[int] = []
    cursor = new_data_offset
    for record in records:
        new_offsets.append(cursor)
        cursor += len(record)
    fields[6] = args.frames
    fields[10] = new_index_offset
    fields[11] = new_data_offset

    temporary = args.output.with_suffix(args.output.suffix + ".partial")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with temporary.open("wb") as target:
            target.write(HEADER.pack(*fields))
            target.write(struct.pack(f"<{args.frames}I", *new_offsets))
            for record in records:
                target.write(record)
        temporary.replace(args.output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"wrote {args.frames} frames ({args.frames * fields[5] / fields[4]:.3f}s) to {args.output}")


if __name__ == "__main__":
    main()
