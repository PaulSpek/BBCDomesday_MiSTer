"""Create a timing-stress copy of the Pi1MHz Domesday Menu SCSI image."""
import argparse
from pathlib import Path
import shutil
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--beebasm", type=Path, required=True)
args = parser.parse_args()
source = args.source.resolve()
output = args.output.resolve()
if source == output:
    raise SystemExit("Output must differ from source")
if output.exists():
    raise SystemExit(f"Refusing to overwrite {output}")

root = Path(__file__).resolve().parents[1]
output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(
    [str(args.beebasm.resolve()), "-i", str(root / "roms/timing_stress.asm"), "-v"],
    cwd=output.parent, check=True, stdout=subprocess.DEVNULL,
)
program = (output.parent / "timing_stress.bin").read_bytes()
if len(program) > 0x400:
    raise SystemExit(f"Stress program is {len(program)} bytes; maximum is 1024")

image = bytearray(source.read_bytes())
directory = image[512:1792]
if directory[1:5] != b"Hugo":
    raise SystemExit("Expected old-map ADFS Hugo root directory")
entries = {}
for pos in range(5, 1227, 26):
    if not directory[pos]:
        break
    name = bytes(value & 127 for value in directory[pos:pos + 10])
    name = name.split(b"\0")[0].split(b"\r")[0].decode("ascii")
    entries[name] = (pos, int.from_bytes(directory[pos + 18:pos + 22], "little"),
                     int.from_bytes(directory[pos + 22:pos + 25], "little"))
if set(entries) != {"!BOOT", "MENU"}:
    raise SystemExit(f"Unexpected Menu image files: {sorted(entries)}")
boot_pos, boot_length, boot_sector = entries["!BOOT"]
menu_pos, menu_length, menu_sector = entries["MENU"]
if (boot_length, menu_length) != (17, 7238):
    raise SystemExit("Unexpected original Menu allocation")

boot = b"*RUN MENU\r"
menu = bytearray(menu_length)
menu[:len(program)] = program
for offset in range(0x400, menu_length):
    menu[offset] = (offset & 255) ^ (offset >> 8) ^ 0xA5
image[boot_sector * 256:boot_sector * 256 + boot_length] = boot.ljust(boot_length, b"\0")
image[menu_sector * 256:menu_sector * 256 + menu_length] = menu

directory = bytearray(image[512:1792])
directory[boot_pos + 18:boot_pos + 22] = len(boot).to_bytes(4, "little")
directory[menu_pos + 10:menu_pos + 14] = (0x0E00).to_bytes(4, "little")
directory[menu_pos + 14:menu_pos + 18] = (0x0E00).to_bytes(4, "little")
image[512:1792] = directory
output.write_bytes(image)
print(f"Created {output}: {len(image)} bytes, MENU executable {len(program)}/{menu_length} bytes")
print("Original image was read only; allocation and image size are unchanged")
