"""Execute the service ROM with py65 and a scripted SCSI register model.

This tests diagnostic reporting, not FPGA bus timing or MOS compatibility.
"""
from pathlib import Path
from py65.devices.mpu6502 import MPU


class Bus(list):
    def __init__(self, fault):
        super().__init__([0] * 65536)
        self.phase = "free"
        self.command = []
        self.pos = 0
        self.fault = fault
        self.status = 0
        self.fcode = bytearray()
        self.last_fcode = b''
        self.history = []

    def __getitem__(self, address):
        if address == 0xFC41:
            return dict(free=0, command=0xA2, data=0x62,
                        write=0x22, status=0xE2, message=0xE3)[self.phase]
        if address == 0xFC40:
            if self.phase == "status":
                self.phase = "message"
                return self.status
            if self.phase == "message":
                self.phase = "free"
                return 0
            if self.phase == "data":
                opcode = self.command[0]
                value = 0
                if opcode == 0x25:
                    value = [0, 0, 0x24, 0, 0, 1, 0, 0][self.pos]
                if opcode == 0xC8 and self.pos < 7:
                    responses = {b'?P': b'P`AA@@\r', b'?F': b'F00001\r',
                                 b'?T1': b'TMiSTer\r', b'?V1': b'V0\r',
                                 b'?Y1': b'YMounted\r', b'F00001R': b'A0\r'}
                    response = responses.get(self.last_fcode, b'\r')
                    if self.fault == 'empty' and self.last_fcode != b'?P':
                        response = b'\r'
                    value = response[self.pos] if self.pos < len(response) else 0
                self.pos += 1
                limit = 8 if opcode == 0x25 else 256
                if opcode == 0xC8 and self.fault == "read254":
                    limit = 254
                if self.pos == limit:
                    self.phase = "status"
                return value
        return super().__getitem__(address)

    def __setitem__(self, address, value):
        if address == 0xFC42:
            self.command = []
            self.phase = "command"
            self.status = 0
        elif address == 0xFC40:
            if self.phase == "command":
                self.command.append(value)
                if len(self.command) == (10 if self.command[0] == 0x25 else 6):
                    self.pos = 0
                    self.phase = ("write" if self.command[0] == 0xCA else
                                  "status" if self.command[0] == 0 else "data")
                    if self.command[0] == 0xCA:
                        self.fcode = bytearray()
                    if self.command[0] == 0xC8 and self.fault == 'timeout':
                        self.phase = 'command'
            elif self.phase == "write":
                self.fcode.append(value)
                self.pos += 1
                if self.pos == (254 if self.fault == "write254" else 256):
                    self.status = 2 if self.fault == "write254" else 0
                    self.phase = "status"
                    self.last_fcode = bytes(self.fcode).split(b'\r')[0]
                    self.history.append(self.last_fcode)
        elif address == 0xFC43:
            self.phase = 'free'
        else:
            super().__setitem__(address, value)


def run(fault, command=b'SCSITEST'):
    bus = Bus(fault)
    binary = (Path(__file__).resolve().parents[1] / "scsi_diag.rom").read_bytes()
    bus[0x8000:0xC000] = binary
    bus[0x200:0x201+len(command)] = command + b'\r'
    bus[0xF2], bus[0xF3] = 0, 2
    cpu = MPU(memory=bus, pc=0x8003)
    cpu.a, cpu.x, cpu.y = 4, 0, 0
    cpu.stPushWord(0x02FF)
    output = []
    for _ in range(5000000):
        if cpu.pc == 0x300:
            return "".join(output)
        if cpu.pc in (0xFFEE, 0xFFE3):
            output.append(chr(cpu.a))
            cpu.pc = (cpu.stPopWord() + 1) & 0xFFFF
        else:
            cpu.step()
    raise AssertionError("ROM did not return")


if __name__ == "__main__":
    for fault, expected in [
        (None, "STEP/END EXP TX/RX: 07/03 00 0100/0100"),
        ("write254", "STEP/END EXP TX/RX: 02/00 22 00FE/0000"),
        ("read254", "STEP/END EXP TX/RX: 05/00 62 0100/00FE"),
    ]:
        output = run(fault)
        assert "diagnostic v1.6" in output, output
        assert expected in output, output
        if fault == "write254":
            assert "VALID S/M REPLY: 01 02/" in output, output
        if fault == "read254":
            assert "50 60 41 41 40 40 0D" in output, output
        print(f"PASS ROM reporting: {fault or 'complete'}")
    for fault in (None, 'empty', 'timeout'):
        output = run(fault, b'LVDTEST')
        assert 'LaserDisc test v1.6' in output, output
        if fault is None:
            assert output.count('PASS') == 8, output
            assert 'FAIL' not in output, output
        elif fault == 'empty':
            assert output.count('REPLY FAIL') == 6, output
        else:
            assert output.count('FAIL FC41=') == 8, output
        print(f'PASS LVDTEST: {fault or "complete"}')
