"""Run the actual !BOOT on py65; stop at unsupported MOS calls.

Functional parasite-code analysis, NOT a full MOS/Tube/FPGA simulation.
Image is read-only; no unimplemented service is silently acknowledged.
"""
import argparse
from collections import deque
import json
from pathlib import Path
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('image', type=Path)
p.add_argument('--dependencies', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--steps', type=int, default=2000000)
p.add_argument('--ack-fcode-i0', action='store_true',
               help='Model only the documented no-reply FCODE I0 OSCLI call')
p.add_argument('--ack-fcode-init', action='store_true',
               help='Model the documented no-reply FCODE I0/J0/$0 init burst')
p.add_argument('--interlace-on', action='store_true',
               help='Model the OSBYTE &90 interlace query as enabled (X=0)')
args = p.parse_args()
sys.path.insert(0, str(args.dependencies.resolve()))
from py65.devices.mpu65c02 import MPU
from py65.disassembler import Disassembler

with args.image.open('rb') as image:
    image.seek(512)
    directory = image.read(1280)
    assert directory[1:5] == b'Hugo'
    entries = {}
    for offset in range(5, 1227, 26):
        if not directory[offset]:
            break
        data = directory[offset:offset+26]
        name = bytes(x & 127 for x in data[:10]).split(b'\0')[0].split(b'\r')[0].decode('ascii')
        entries[name] = tuple(int.from_bytes(data[a:b], 'little') for a,b in ((10,14),(14,18),(18,22),(22,25)))
    load, execute, size, sector = entries['!BOOT']
    image.seek(sector*256)
    program = image.read(size)

memory = [0]*65536
memory[load:load+size] = program
cpu = MPU(memory=memory, pc=execute)
dis = Disassembler(cpu)
recent = deque(maxlen=32)
events = []
screen = []
osbyte_values = {0xE5:0, 2:0, 3:0}
def word(address):
    return memory[address] | memory[address+1]<<8
def rts():
    cpu.pc = (cpu.stPopWord()+1) & 65535
def event(service):
    item = dict(step=step, service=service, a=cpu.a, x=cpu.x, y=cpu.y,
                return_to=(word(0x100+cpu.sp+1)+1)&65535,
                runtime_pc=word(6))
    events.append(item)
    return item
def filename(address):
    chars = []
    for value in memory[address:address+256]:
        if value in (0, 13):
            break
        chars.append(chr(value))
    return ''.join(chars)
def put32(address, value):
    memory[address:address+4] = value.to_bytes(4, 'little')

reason = 'instruction budget exhausted'
for step in range(args.steps):
    if cpu.pc in (0xFFEE, 0xFFE3):
        screen.append(chr(cpu.a))
        rts()
        continue
    if cpu.pc == 0xFFF4:
        item = event('OSBYTE')
        if cpu.a == 0x82:  # parasite address high word
            cpu.x, cpu.y = 0, 0
        elif cpu.a == 0x83:  # assumed parasite user-memory bottom
            cpu.x, cpu.y = 0, 0x08
        elif cpu.a == 0x84:  # assumed parasite user-memory top
            cpu.x, cpu.y = 0, 0xF8
        elif cpu.a in osbyte_values:
            previous = osbyte_values[cpu.a]
            osbyte_values[cpu.a] = (previous & cpu.y) ^ cpu.x
            cpu.x, cpu.y = previous, 0
        elif cpu.a == 0x90 and args.interlace_on:
            cpu.x, cpu.y = 0, 0
        else:
            reason = f'unsupported OSBYTE &{cpu.a:02X}'
            break
        item['model'] = 'explicit OSBYTE memory/configuration model'
        rts()
        continue
    if cpu.pc in (0xFFF7, 0xFFF1, 0xFFDD, 0xFFDA, 0xFFD7, 0xFFD4, 0xFFD1, 0xFFCE, 0xFFE0):
        service = {0xFFF7:'OSCLI',0xFFF1:'OSWORD',0xFFDD:'OSFILE',0xFFDA:'OSARGS',0xFFD7:'OSBGET',0xFFD4:'OSBPUT',0xFFD1:'OSGBPB',0xFFCE:'OSFIND',0xFFE0:'OSRDCH'}[cpu.pc]
        item = event(service)
        address = cpu.x | cpu.y<<8
        item['block_address'] = address
        item['block_hex'] = bytes(memory[address:address+32]).hex(' ')
        if service == 'OSCLI':
            item['command'] = filename(address)
            command = item['command'].strip().upper()
            no_reply_init = {'FCODE I0', 'FCODE J0', 'FCODE $0'}
            if ((args.ack_fcode_i0 and command == 'FCODE I0') or
                    (args.ack_fcode_init and command in no_reply_init)):
                item['model'] = 'documented no-reply F-code returned successfully'
                rts()
                continue
        if service == 'OSFILE':
            name = filename(word(address))
            item['name'] = name
            key = name.upper().removeprefix('$.')
            entry = entries.get(key)
            if cpu.a == 5:
                cpu.a = 1 if entry else 0
                if entry:
                    file_load, file_exec, file_size, file_sector = entry
                    for delta,value in ((2,file_load),(6,file_exec),(10,file_size),(14,3)):
                        put32(address+delta,value)
                item['result'] = cpu.a
                rts()
                continue
            if cpu.a == 255 and entry:
                file_load, file_exec, file_size, file_sector = entry
                destination = word(address+2) if memory[address+6] == 0 else file_load & 65535
                if destination+file_size > 0xF800:
                    reason = 'file load outside modelled parasite RAM'
                    break
                with args.image.open('rb') as image:
                    image.seek(file_sector*256)
                    payload = image.read(file_size)
                if len(payload) != file_size:
                    raise ValueError('Truncated file in input image')
                memory[destination:destination+file_size] = payload
                for delta,value in ((2,file_load),(6,file_exec),(10,file_size),(14,3)):
                    put32(address+delta,value)
                cpu.a = 1
                item['loaded_at'] = destination
                rts()
                continue
        reason = f'unsupported {service} &{cpu.a:02X}'
        break
    if cpu.pc >= 0xF800:
        reason = f'unmodelled ROM execution at &{cpu.pc:04X}'
        break
    length, instruction = dis.instruction_at(cpu.pc)
    recent.append(f'{cpu.pc:04X}: {instruction}')
    cpu.step()

result = dict(scope='actual executable, ideal RAM, intercepted MOS calls; no real Tube/MOS/FPGA',
              assumptions=['zero initial RAM', 'parasite memory bottom 0800 top F800', 'OS output captured without hardware timing'],
              reason=reason, instructions=step, native_pc=cpu.pc, runtime_pc=word(6),
              events=events, screen=''.join(screen), recent=list(recent))
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
