"""Execute the copro RAM-test ROM with py65, including an injected F000 fault."""
import argparse
from pathlib import Path
import sys


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dependencies", type=Path)
args = parser.parse_args()
if args.dependencies:
    sys.path.insert(0, str(args.dependencies.resolve()))
from py65.devices.mpu65c02 import MPU


class Memory(list):
    def __init__(self, fault_page=None):
        super().__init__([0] * 65536)
        self.fault_page = fault_page
        self.inject = False

    def __setitem__(self, address, value):
        if (self.inject and isinstance(address, int) and self.fault_page is not None
                and self.fault_page <= address < self.fault_page + 0x100):
            value ^= 1
        super().__setitem__(address, value)


class HostMemory(Memory):
    def __setitem__(self, address, value):
        if self.inject and isinstance(address, int) and 0x8000 <= address < 0xC000:
            return
        super().__setitem__(address, value)


def rts(cpu):
    cpu.pc = (cpu.stPopWord() + 1) & 0xFFFF


def run_language(fault_page=None):
    rom = (Path(__file__).resolve().parents[1] / "copro_ramtest.rom").read_bytes()
    memory = Memory(fault_page)
    memory[0x8000:0xC000] = rom
    memory.inject = True
    cpu = MPU(memory=memory, pc=0x8000)
    output = []
    command = None
    for _ in range(12000000):
        if cpu.pc in (0xFFEE, 0xFFE3):
            output.append(chr(cpu.a))
            rts(cpu)
        elif cpu.pc == 0xFFE0:
            cpu.a = 32
            rts(cpu)
        elif cpu.pc == 0xFFF7:
            address = cpu.x | cpu.y << 8
            chars = []
            while memory[address] not in (0, 13):
                chars.append(chr(memory[address]))
                address += 1
            command = "".join(chars)
            break
        elif cpu.pc >= 0xF800:
            raise AssertionError(f"Unexpected Tube-ROM call &{cpu.pc:04X}")
        else:
            cpu.step()
    else:
        raise AssertionError("RAM test did not finish")
    return "".join(output), command


def run_host_guard():
    rom = (Path(__file__).resolve().parents[1] / "copro_ramtest.rom").read_bytes()
    memory = HostMemory()
    memory[0x8000:0xC000] = rom
    memory.inject = True
    cpu = MPU(memory=memory, pc=0x8000)
    output = []
    for _ in range(100000):
        if cpu.pc in (0xFFEE, 0xFFE3):
            output.append(chr(cpu.a))
            rts(cpu)
        elif cpu.pc == 0xFFF7:
            address = cpu.x | cpu.y << 8
            command = bytearray()
            while memory[address] not in (0, 13):
                command.append(memory[address])
                address += 1
            return "".join(output), command.decode("ascii")
        else:
            cpu.step()
    raise AssertionError("Host guard did not leave for BASIC")


def run_service():
    rom = (Path(__file__).resolve().parents[1] / "copro_ramtest.rom").read_bytes()
    memory = [0] * 65536
    memory[0x8000:0xC000] = rom
    command = b"CPURAMTEST\r"
    memory[0x200:0x200 + len(command)] = command
    memory[0xF2], memory[0xF3] = 0, 2
    cpu = MPU(memory=memory, pc=0x8003)
    cpu.a, cpu.x, cpu.y = 4, 1, 0
    cpu.stPushWord(0x02FF)
    for _ in range(10000):
        if cpu.pc == 0xFFF4:
            assert (cpu.a, cpu.x, cpu.y) == (142, 1, 0)
            return
        cpu.step()
    raise AssertionError("Service command did not select its ROM")


if __name__ == "__main__":
    run_service()
    output, command = run_host_guard()
    assert "Requires active 65C02 coprocessor" in output, output
    assert command == "BASIC", command
    print("PASS host-side destructive-run guard")
    output, command = run_language()
    assert output.count("PASS") == 4, output
    assert "FAIL" not in output, output
    assert command == "BASIC", command
    print("PASS complete RAM and service-command path")
    output, command = run_language(0xF000)
    assert "F000-F7FF: FAIL @F000 E=00 G=01" in output, output
    assert output.count("PASS") == 3, output
    assert command == "BASIC", command
    print("PASS injected F000 fault reporting")
