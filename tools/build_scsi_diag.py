#!/usr/bin/env python3
"""Assemble the BBC SCSI diagnostic ROM with BeebAsm and emit Quartus MIF."""

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
    lines = [
        "DEPTH = 16384;", "WIDTH = 8;", "ADDRESS_RADIX = HEX;",
        "DATA_RADIX = HEX;", "CONTENT BEGIN",
    ]
    for address in range(0, len(binary), 32):
        values = " ".join(f"{byte:02X}" for byte in binary[address:address + 32])
        lines.append(f"{address:04X}: {values};")
    lines.append("END;")
    (root / "roms/scsi_diag.mif").write_text("\n".join(lines) + "\n", encoding="ascii")
    print("Built 16 KiB diagnostic ROM in Master slot 1")


if __name__ == "__main__":
    main()
