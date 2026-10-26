#!/usr/bin/env python3
"""Assemble the BBC SCSI diagnostic ROM with BeebAsm and emit Quartus HEX."""

import argparse
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("beebasm", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    subprocess.run(
        [str(args.beebasm.resolve()), "-i", "roms/scsi_diag.asm"],
        cwd=root,
        check=True,
    )
    binary = (root / "scsi_diag.rom").read_bytes()
    if len(binary) != 16384 or binary[:3] != bytes((0x4C, binary[1], binary[2])):
        raise SystemExit("Invalid 16 KiB service ROM")
    (root / "roms/scsi_diag.hex").write_text(
        "".join(f"{byte:02X}\n" for byte in binary), encoding="ascii"
    )
    print("Built 16 KiB diagnostic ROM in Master slot 1")


if __name__ == "__main__":
    main()
