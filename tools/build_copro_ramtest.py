#!/usr/bin/env python3
"""Build the 65C02 copro RAM-test language ROM with BeebAsm."""
import argparse
from pathlib import Path
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("beebasm", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
for source in ("roms/copro_ram_stage2.asm", "roms/copro_ramtest.asm"):
    subprocess.run([str(args.beebasm.resolve()), "-i", source], cwd=root, check=True)
binary = (root / "copro_ramtest.rom").read_bytes()
if len(binary) != 16384:
    raise SystemExit(f"Expected 16384-byte ROM, got {len(binary)}")
if binary[6] != 0xC2:
    raise SystemExit(f"Expected combined service/language type C2, got {binary[6]:02X}")
stage2 = (root / "copro_ram_stage2.bin").read_bytes()
if not stage2 or len(stage2) > 1024:
    raise SystemExit(f"Unexpected relocated stage size: {len(stage2)}")
print(f"Built copro_ramtest.rom ({len(binary)} bytes), relocated stage {len(stage2)} bytes")
