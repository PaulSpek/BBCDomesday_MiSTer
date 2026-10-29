"""Create separate BeebVFS1 images that stop at or skip video OSCLI calls.

The source image is opened read-only. Only !BOOT, its unused allocation
slack, and the !BOOT directory length are changed in each new image.
"""
import argparse
from pathlib import Path
import shutil
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("stop_output", type=Path)
parser.add_argument("no_video_output", type=Path)
parser.add_argument("--beebasm", type=Path, required=True)
args = parser.parse_args()

paths = (args.source.resolve(), args.stop_output.resolve(), args.no_video_output.resolve())
if len(set(paths)) != 3:
    raise SystemExit("Source and both output paths must be different")
for output in paths[1:]:
    if output.exists():
        raise SystemExit(f"Refusing to overwrite existing output: {output}")

root = Path(__file__).resolve().parents[1]
build_dir = args.stop_output.resolve().parent
subprocess.run(
    [str(args.beebasm.resolve()), "-i", str(root / "roms/boot_video_gate.asm"), "-v"],
    cwd=build_dir,
    check=True,
    stdout=subprocess.DEVNULL,
)
gate = bytearray((build_dir / "boot_video_gate.bin").read_bytes())
if len(gate) > 256:
    raise SystemExit(f"Video gate is {len(gate)} bytes; it must fit one page")
marker = bytes.fromhex("DE AD BE EF")
marker_at = gate.find(marker)
if marker_at < 0 or gate.find(marker, marker_at + 1) >= 0:
    raise SystemExit("Expected one mode marker in assembled gate")
mode_at = marker_at + len(marker)

with args.source.open("rb") as source:
    source.seek(512)
    directory = source.read(1280)
    if directory[1:5] != b"Hugo":
        raise SystemExit("Expected an old-map ADFS Hugo root directory")
    entries = []
    for pos in range(5, 1227, 26):
        if not directory[pos]:
            break
        name = bytes(value & 127 for value in directory[pos:pos + 10])
        name = name.split(b"\0")[0].split(b"\r")[0]
        entries.append((name, pos, int.from_bytes(directory[pos + 22:pos + 25], "little")))
    _, entry_pos, sector = next(entry for entry in entries if entry[0] == b"!BOOT")
    length = int.from_bytes(directory[entry_pos + 18:entry_pos + 22], "little")
    if int.from_bytes(directory[entry_pos + 10:entry_pos + 14], "little") != 0xE00:
        raise SystemExit("Unexpected !BOOT load address")
    source.seek(sector * 256)
    original_boot = bytearray(source.read(length))

if original_boot[:7] != bytes.fromhex("A2 5C A0 4A 4C 04 4D"):
    raise SystemExit("Unexpected !BOOT entry sequence")
hook_at = 0x17A1 - 0xE00
if original_boot[hook_at:hook_at + 3] != bytes.fromhex("AD B3 17"):
    raise SystemExit("Unexpected MOS wrapper entry")

append_address = 0xE00 + len(original_boot)
source_address = append_address + 11 + 7
copy_gate = bytes((
    0xA2, 0x00,                         # LDX #0
    0xBD, source_address & 255, source_address >> 8,  # LDA source,X
    0x9D, 0x00, 0xF0,                  # STA &F000,X
    0xE8, 0xD0, 0xF7,                  # INX / BNE copy
))
original_entry = bytes.fromhex("A2 5C A0 4A 4C 04 4D")
next_sector = min(item_sector for _, _, item_sector in entries if item_sector > sector)


def create_image(output, mode):
    boot = bytearray(original_boot)
    page = bytearray(gate)
    page[mode_at] = mode
    boot[:3] = bytes((0x4C, append_address & 255, append_address >> 8))
    boot[hook_at:hook_at + 3] = bytes.fromhex("4C 00 F0")
    boot += copy_gate + original_entry + page.ljust(256, b"\0")
    if sector * 256 + len(boot) > next_sector * 256:
        raise SystemExit("Patched !BOOT no longer fits its original allocation")
    shutil.copyfile(args.source, output)
    with output.open("r+b") as target:
        target.seek(sector * 256)
        target.write(boot)
        target.seek(512 + entry_pos + 18)
        target.write(len(boot).to_bytes(4, "little"))
    return len(boot)


stop_length = create_image(args.stop_output, 0)
no_video_length = create_image(args.no_video_output, 1)
print(f"Created stop image: {args.stop_output} (!BOOT {length} -> {stop_length} bytes)")
print(f"Created no-video image: {args.no_video_output} (!BOOT {length} -> {no_video_length} bytes)")
print("Intercepted tokens: FCODE SEARCH PLAY STEP STILL RESET AUDIO")
