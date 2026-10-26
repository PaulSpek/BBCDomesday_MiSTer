#!/usr/bin/env python3
"""Structural regression checks for the generated VFS diagnostic ROM."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


BASE = 0x8000
HOOKS = (0x90D3, 0x90E1, 0x90EB, 0x9121, 0x9154, 0x917C, 0x91D6)
ORIGINAL_CALLS = (0xB6B8, 0xB6B8, 0x8E89, 0x9AAE, 0x91FC, 0x873D, 0x91FC)
SOURCE_SHA256 = "f165ce0aec17e916dc15f36b53a6441fd80cfafded3c8f20163b64b998333e19"
ALLOWED_RANGES = tuple((address - BASE, address - BASE + 3) for address in HOOKS) + (
    (0xA94A - BASE, 0xA94D - BASE),
    (0xA94D - BASE, 0xAA4D - BASE),
)


def allowed(offset: int) -> bool:
    return any(start <= offset < end for start, end in ALLOWED_RANGES)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("diagnostic", type=Path)
    args = parser.parse_args()

    original = args.original.read_bytes()
    diagnostic = args.diagnostic.read_bytes()
    if len(original) != 16384 or len(diagnostic) != 16384:
        raise SystemExit("both ROMs must be exactly 16 KiB")
    if hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
        raise SystemExit("source is not the supported Acorn VFS 2.02 ROM")
    changed = [index for index, pair in enumerate(zip(original, diagnostic)) if pair[0] != pair[1]]
    unexpected = [index for index in changed if not allowed(index)]
    if unexpected:
        raise SystemExit(f"unexpected changed byte at ROM offset &{unexpected[0]:04X}")
    targets = []
    for address in HOOKS:
        offset = address - BASE
        if diagnostic[offset] != 0x20:
            raise SystemExit(f"checkpoint hook at &{address:04X} is not JSR")
        target = diagnostic[offset + 1] | diagnostic[offset + 2] << 8
        if not 0xA94D <= target < 0xAA4D:
            raise SystemExit(f"checkpoint hook at &{address:04X} targets outside overlay")
        targets.append(target)
    emit = targets[0] + 7 * 21
    for number, (target, original_call) in enumerate(zip(targets, ORIGINAL_CALLS), 1):
        expected = bytes((
            0x20, original_call & 0xFF, original_call >> 8,
            0x08, 0x48, 0x8A, 0x48, 0x98, 0x48,
            0xA9, ord(str(number)), 0x20, emit & 0xFF, emit >> 8,
            0x68, 0xA8, 0x68, 0xAA, 0x68, 0x28, 0x60,
        ))
        offset = target - BASE
        if diagnostic[offset:offset + len(expected)] != expected:
            raise SystemExit(f"checkpoint wrapper D{number} does not preserve expected state")
    marker_code = bytes.fromhex(
        "A9 56 20 E3 FF A9 46 20 E3 FF A9 53 20 E3 FF "
        "A9 2D 20 E3 FF A9 44 20 E3 FF"
    )
    if marker_code not in diagnostic[0xA94D - BASE:0xAA4D - BASE]:
        raise SystemExit("checkpoint text missing from overlay")
    if b"Turn interlace on\0" not in diagnostic:
        raise SystemExit("original interlace error text was not preserved")
    print(f"PASS VFS diagnostic ROM: {len(changed)} changed bytes, all in declared patch ranges")


if __name__ == "__main__":
    main()
