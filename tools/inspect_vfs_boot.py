"""Extract old-map ADFS root files and disassemble !BOOT for offline diagnosis.

Usage: python tools/inspect_vfs_boot.py image output_directory [py65_directory]
The input image is opened read-only. Generated files are analysis artifacts.
"""
import json
from pathlib import Path
import re
import sys

image, output = Path(sys.argv[1]), Path(sys.argv[2])
if len(sys.argv) > 3:
    sys.path.insert(0, sys.argv[3])
from py65.devices.mpu65c02 import MPU
from py65.disassembler import Disassembler

output.mkdir(parents=True, exist_ok=True)
with image.open('rb') as source:
    source.seek(512)
    directory = source.read(1280)
    if directory[1:5] != b'Hugo':
        raise ValueError('Expected old-map ADFS Hugo root directory')
    entries = []
    for pos in range(5, 5 + 47 * 26, 26):
        if directory[pos] == 0:
            break
        name = bytes(b & 127 for b in directory[pos:pos+10]).split(b'\r')[0].split(b'\0')[0].decode('ascii')
        number = lambda start, length: int.from_bytes(directory[pos+start:pos+start+length], 'little')
        entry = dict(name=name, load=number(10,4), execute=number(14,4), length=number(18,4), sector=number(22,3))
        entries.append(entry)
    (output/'directory.json').write_text(json.dumps(entries, indent=2))
    for entry in entries:
        if entry['name'] not in ('!BOOT','INIT','ROOT','STINIT1','STINIT2','USERKERN'):
            continue
        source.seek(entry['sector']*256)
        data = source.read(entry['length'])
        if len(data) != entry['length']:
            raise ValueError(f'Truncated {entry}')
        name = entry['name'].replace('!', '')
        (output/(name+'.bin')).write_bytes(data)
        strings = [f'{entry["load"]+m.start():04X}: {m.group().decode("ascii")}' for m in re.finditer(rb'[ -~]{5,}', data)]
        (output/(name+'.strings.txt')).write_text('\n'.join(strings))
        if entry['load'] == 0xE00:
            memory = [0]*65536
            memory[0xE00:0xE00+len(data)] = data
            dis = Disassembler(MPU(memory=memory))
            lines = []
            pc = 0xE00
            while pc < 0xE00+len(data):
                length, instruction = dis.instruction_at(pc)
                lines.append(f'{pc:04X}: {bytes(memory[pc:pc+length]).hex(" "):8s} {instruction}')
                pc += length
            (output/(name+'.asm')).write_text('\n'.join(lines))
        print(entry)
