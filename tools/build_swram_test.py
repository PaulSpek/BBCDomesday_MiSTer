#!/usr/bin/env python3
"""Build the BBC Master sideways-RAM diagnostic service ROM."""
import argparse
from pathlib import Path
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("beebasm", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
for source in ("roms/swram_test_engine.asm", "roms/swram_test.asm"):
    subprocess.run([str(args.beebasm.resolve()), "-i", source], cwd=root, check=True)
binary = (root / "swram_test.rom").read_bytes()
if len(binary) != 16384 or binary[6] != 0x82:
    raise SystemExit("Invalid 16 KiB service ROM")
engine = (root / "swram_test_engine.bin").read_bytes()
if not engine or len(engine) > 0x1000:
    raise SystemExit(f"Unexpected relocated engine size: {len(engine)}")
print(f"Built swram_test.rom ({len(binary)} bytes), RAM engine {len(engine)} bytes")
