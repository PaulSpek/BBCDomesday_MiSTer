#!/usr/bin/env python3
"""Build a checkpoint-instrumented VFS ROM without changing the source ROM."""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
from pathlib import Path


ROM_BASE = 0x8000
ROM_SIZE = 16 * 1024
PATCH_START = 0xA94D
PATCH_LIMIT = 0xAA4D

# Address, exact original instruction, replacement wrapper label.
HOOKS = (
    (0x90D3, bytes.fromhex("20 B8 B6"), "diag1"),
    (0x90E1, bytes.fromhex("20 B8 B6"), "diag2"),
    (0x90EB, bytes.fromhex("20 89 8E"), "diag3"),
    (0x9121, bytes.fromhex("20 AE 9A"), "diag4"),
    (0x9154, bytes.fromhex("20 FC 91"), "diag5"),
    (0x917C, bytes.fromhex("20 3D 87"), "diag6"),
    (0x91D6, bytes.fromhex("20 FC 91"), "diag7"),
)

# The diagnostic overlay occupies the original long *HELP VFS payload. Skip
# that payload instead of allowing the help printer to interpret machine code.
HELP_HOOK = (0xA94A, bytes.fromhex("20 50 AA"), bytes.fromhex("4C 33 A9"))


def parse_labels(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="ascii")
    return {name: int(value) for name, value in re.findall(r"'([^']+)':(\d+)L", text)}


def replace_exact(image: bytearray, address: int, old: bytes, new: bytes) -> None:
    offset = address - ROM_BASE
    actual = bytes(image[offset:offset + len(old)])
    if actual != old:
        raise SystemExit(
            f"VFS ROM mismatch at &{address:04X}: expected {old.hex(' ')}, "
            f"found {actual.hex(' ')}"
        )
    if len(old) != len(new):
        raise ValueError("in-place replacement must preserve length")
    image[offset:offset + len(new)] = new


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("beebasm", type=Path, help="path to BeebAsm executable")
    parser.add_argument("source_rom", type=Path, help="original 16 KiB VFS.rom")
    parser.add_argument("output_rom", type=Path, help="new VFS-DIAG.rom path")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    output = args.output_rom.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    patch_file = root / "vfs_diag_patch.bin"
    labels_file = output.with_suffix(".labels.txt")

    subprocess.run(
        [
            str(args.beebasm.resolve()),
            "-i", "roms/vfs_diag_patch.asm",
            "-labels", str(labels_file),
            "-d",
        ],
        cwd=root,
        check=True,
    )

    source = args.source_rom.resolve()
    original = source.read_bytes()
    if len(original) != ROM_SIZE:
        raise SystemExit(f"expected a {ROM_SIZE}-byte VFS ROM, got {len(original)} bytes")
    image = bytearray(original)
    patch = patch_file.read_bytes()
    if len(patch) > PATCH_LIMIT - PATCH_START:
        raise SystemExit(f"diagnostic overlay is too large: {len(patch)} bytes")
    patch_offset = PATCH_START - ROM_BASE
    image[patch_offset:patch_offset + len(patch)] = patch

    labels = parse_labels(labels_file)
    for address, old, label in HOOKS:
        target = labels[label]
        replace_exact(image, address, old, bytes((0x20, target & 0xFF, target >> 8)))
    replace_exact(image, *HELP_HOOK)

    output.write_bytes(image)
    patch_file.unlink()
    labels_file.unlink()

    original_hash = hashlib.sha256(original).hexdigest()
    diagnostic_hash = hashlib.sha256(image).hexdigest()
    print(f"Original preserved: {source} SHA256={original_hash}")
    print(f"Diagnostic ROM:     {output} SHA256={diagnostic_hash}")
    print(f"Overlay bytes:      {len(patch)} of {PATCH_LIMIT - PATCH_START}")


if __name__ == "__main__":
    main()
