"""Run SWRAMTEST in py65 with independent, aliased and faulty banks."""
import argparse
from pathlib import Path
import sys


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dependencies", type=Path)
args = parser.parse_args()
if args.dependencies:
    sys.path.insert(0, str(args.dependencies.resolve()))
from py65.devices.mpu65c02 import MPU


class BankedMemory(list):
    def __init__(self, alias=False, faulty_bank=None):
        super().__init__([0] * 65536)
        self.rom = (Path(__file__).resolve().parents[1] / "swram_test.rom").read_bytes()
        self.banks = {bank: bytearray(0x4000) for bank in range(4, 8)}
        if alias:
            self.banks[7] = self.banks[6]
        self.selected = 1
        self.faulty_bank = faulty_bank

    def __getitem__(self, address):
        if isinstance(address, int) and 0x8000 <= address < 0xC000:
            if self.selected == 1:
                return self.rom[address - 0x8000]
            if self.selected in self.banks:
                return self.banks[self.selected][address - 0x8000]
            return 0xFF
        return super().__getitem__(address)

    def __setitem__(self, address, value):
        if isinstance(address, int) and address == 0xFE30:
            self.selected = value & 15
            return
        if isinstance(address, int) and 0x8000 <= address < 0xC000:
            if self.selected in self.banks:
                if self.selected == self.faulty_bank:
                    value ^= 1
                self.banks[self.selected][address - 0x8000] = value
            return
        super().__setitem__(address, value)


def rts(cpu):
    cpu.pc = (cpu.stPopWord() + 1) & 0xFFFF


def run(alias=False, faulty_bank=None):
    memory = BankedMemory(alias, faulty_bank)
    command = b"SWRAMTEST\r"
    memory[0x200:0x200 + len(command)] = command
    memory[0xF2], memory[0xF3] = 0, 2
    memory[0xF4] = 1
    cpu = MPU(memory=memory, pc=0x8003)
    cpu.a, cpu.x, cpu.y = 4, 1, 0
    cpu.stPushWord(0x02FF)
    output = []
    for _ in range(20000000):
        if cpu.pc == 0x300:
            return "".join(output), memory
        if cpu.pc in (0xFFEE, 0xFFE3):
            output.append(chr(cpu.a))
            rts(cpu)
        else:
            cpu.step()
    raise AssertionError("SWRAMTEST did not return")


if __name__ == "__main__":
    output, memory = run()
    assert output.count("BANK 0") == 4, output
    assert output.count("PASS") == 5 and "FAIL" not in output, output
    assert memory.selected == 1 and memory[0xF4] == 1
    print("PASS independent banks and ROM restoration")
    output, _ = run(alias=True)
    assert "BANK ISOLATION: FAIL" in output, output
    print("PASS aliased-bank detection")
    output, _ = run(faulty_bank=6)
    assert "BANK 06: FAIL" in output, output
    print("PASS faulty-bank reporting")
