"""Execute the Menu timing-stress image in py65 with modeled OSFILE loads."""
import argparse
from pathlib import Path
import sys


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path)
parser.add_argument("--dependencies", type=Path)
parser.add_argument("--corrupt-iteration", type=int)
args = parser.parse_args()
if args.dependencies:
    sys.path.insert(0, str(args.dependencies.resolve()))
from py65.devices.mpu65c02 import MPU


data = args.image.read_bytes()
directory = data[512:1792]
entries = {}
for pos in range(5, 1227, 26):
    if not directory[pos]:
        break
    name = bytes(value & 127 for value in directory[pos:pos + 10])
    name = name.split(b"\0")[0].split(b"\r")[0].decode("ascii")
    entries[name] = tuple(int.from_bytes(directory[pos + a:pos + b], "little")
                          for a, b in ((10, 14), (14, 18), (18, 22), (22, 25)))
load, execute, length, sector = entries["MENU"]
program = data[sector * 256:sector * 256 + length]
memory = [0] * 65536
memory[load:load + length] = program
cpu = MPU(memory=memory, pc=execute)
output = []
loads = 0


def word(address):
    return memory[address] | memory[address + 1] << 8


def rts():
    cpu.pc = (cpu.stPopWord() + 1) & 0xFFFF


for _ in range(80000000):
    if cpu.pc in (0xFFEE, 0xFFE3):
        output.append(chr(cpu.a))
        rts()
    elif cpu.pc == 0xFFDD:
        assert cpu.a == 0xFF
        block = cpu.x | cpu.y << 8
        destination = word(block + 2)
        memory[destination:destination + length] = program
        loads += 1
        if args.corrupt_iteration == loads:
            memory[destination + 0x456] ^= 1
        cpu.a = 1
        rts()
    else:
        cpu.step()
    screen = "".join(output)
    # Wait for the complete diagnostic line.  Breaking as soon as the word
    # "FAIL" appears would only validate the first few output characters.
    if "DONE: 0100 LOADS PASS" in screen or ("\rFAIL " in screen and screen.endswith("\r")):
        break
else:
    raise AssertionError("Stress test did not finish")

screen = "".join(output)
if args.corrupt_iteration is None:
    assert loads == 256 and "DONE: 0100 LOADS PASS" in screen, (loads, screen[-200:])
    print("PASS 256 modeled OSFILE loads")
else:
    assert loads == args.corrupt_iteration and "FAIL I=" in screen, screen[-300:]
    print(f"PASS corruption detected on load {loads}")
