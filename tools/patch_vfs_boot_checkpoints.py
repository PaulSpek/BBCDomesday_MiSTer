"""Create three separate BeebVFS1 !BOOT checkpoint images."""
import argparse
from pathlib import Path
import shutil
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("output_directory", type=Path)
parser.add_argument("--beebasm", type=Path, required=True)
args = parser.parse_args()
source = args.source.resolve()
output_directory = args.output_directory.resolve()
output_directory.mkdir(parents=True, exist_ok=True)
outputs = [
    output_directory / "BeebVFS1-check-root01-scsi0.dat",
    output_directory / "BeebVFS1-check-init01-scsi0.dat",
    output_directory / "BeebVFS1-check-fcode01-scsi0.dat",
]
for output in outputs:
    if output.exists():
        raise SystemExit(f"Refusing to overwrite existing output: {output}")

root = Path(__file__).resolve().parents[1]
subprocess.run(
    [str(args.beebasm.resolve()), "-i", str(root / "roms/boot_stage_checkpoint.asm"), "-v"],
    cwd=output_directory, check=True, stdout=subprocess.DEVNULL,
)
checkpoint = bytearray((output_directory / "boot_stage_checkpoint.bin").read_bytes())
if len(checkpoint) > 768:
    raise SystemExit(f"Checkpoint code is {len(checkpoint)} bytes; maximum is 768")
marker = bytes.fromhex("DE AD BE EF")
marker_at = checkpoint.find(marker)
if marker_at < 0 or checkpoint.find(marker, marker_at + 1) >= 0:
    raise SystemExit("Expected exactly one mode marker")
mode_at = marker_at + len(marker)
return_needle = bytes.fromhex("08 48 AD FE F2")
return_offset = checkpoint.find(return_needle)
if return_offset < 0 or checkpoint.find(return_needle, return_offset + 1) >= 0:
    raise SystemExit("Expected exactly one return-hook signature")
return_address = 0xF000 + return_offset

with source.open("rb") as image:
    image.seek(512)
    directory = image.read(1280)
    if directory[1:5] != b"Hugo":
        raise SystemExit("Expected old-map ADFS Hugo root directory")
    entries = []
    for pos in range(5, 1227, 26):
        if not directory[pos]:
            break
        name = bytes(value & 127 for value in directory[pos:pos + 10])
        name = name.split(b"\0")[0].split(b"\r")[0]
        entries.append((name, pos, int.from_bytes(directory[pos + 22:pos + 25], "little")))
    _, entry_pos, sector = next(entry for entry in entries if entry[0] == b"!BOOT")
    length = int.from_bytes(directory[entry_pos + 18:entry_pos + 22], "little")
    image.seek(sector * 256)
    original = bytearray(image.read(length))

if original[:7] != bytes.fromhex("A2 5C A0 4A 4C 04 4D"):
    raise SystemExit("Unexpected !BOOT entry")
entry_hook = 0x17A1 - 0xE00
return_hook = 0x178F - 0xE00
if original[entry_hook:entry_hook + 3] != bytes.fromhex("AD B3 17"):
    raise SystemExit("Unexpected generic wrapper entry")
if original[return_hook:return_hook + 4] != bytes.fromhex("08 8D 16 08"):
    raise SystemExit("Unexpected generic wrapper return")

append_address = 0xE00 + len(original)
page = checkpoint.ljust(768, b"\0")
source_address = append_address + 33 + 7
loader = bytes((
    0xA2, 0x00, 0xBD, source_address & 255, source_address >> 8,
    0x9D, 0x00, 0xF0, 0xE8, 0xD0, 0xF7,
    0xA2, 0x00, 0xBD, (source_address + 256) & 255, (source_address + 256) >> 8,
    0x9D, 0x00, 0xF1, 0xE8, 0xD0, 0xF7,
    0xA2, 0x00, 0xBD, (source_address + 512) & 255, (source_address + 512) >> 8,
    0x9D, 0x00, 0xF2, 0xE8, 0xD0, 0xF7,
))
original_entry = bytes.fromhex("A2 5C A0 4A 4C 04 4D")
next_sector = min(item_sector for _, _, item_sector in entries if item_sector > sector)

for mode, output in enumerate(outputs):
    boot = bytearray(original)
    code = bytearray(page)
    code[mode_at] = mode
    boot[:3] = bytes((0x4C, append_address & 255, append_address >> 8))
    boot[entry_hook:entry_hook + 3] = bytes.fromhex("4C 00 F0")
    boot[return_hook:return_hook + 4] = bytes((0x4C, return_address & 255, return_address >> 8, 0xEA))
    boot += loader + original_entry + code
    if sector * 256 + len(boot) > next_sector * 256:
        raise SystemExit("Patched !BOOT exceeds its original allocation")
    shutil.copyfile(source, output)
    with output.open("r+b") as target:
        target.seek(sector * 256)
        target.write(boot)
        target.seek(512 + entry_pos + 18)
        target.write(len(boot).to_bytes(4, "little"))
    print(f"Created mode {mode}: {output} (!BOOT {length} -> {len(boot)} bytes)")
