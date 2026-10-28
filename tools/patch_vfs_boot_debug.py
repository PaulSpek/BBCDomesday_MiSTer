"""Create a separate read-only-source image with instrumented !BOOT.

Only the !BOOT payload, its slack sectors and its directory length change.
The original image is never opened for writing. Requires BeebAsm.
"""
import argparse
from pathlib import Path
import shutil
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source',type=Path)
p.add_argument('output',type=Path)
p.add_argument('--beebasm',type=Path,required=True)
args=p.parse_args()
assert args.source.resolve()!=args.output.resolve()
if args.output.exists():
    raise SystemExit('Refusing to overwrite existing output')
root=Path(__file__).resolve().parents[1]
outdir=args.output.resolve().parent
subprocess.run([str(args.beebasm.resolve()),'-i',str(root/'roms/boot_debug.asm'),'-v'],cwd=outdir,check=True,stdout=subprocess.DEVNULL)
debug=(outdir/'boot_debug.bin').read_bytes()
assert len(debug)<=256, 'Debugger must fit one page'
# Locate return label by its unique prologue and first '<' output.
needle=bytes.fromhex('08 48 8a 48 98 48 a9 3c')
returned=0xF000+debug.index(needle)
with args.source.open('rb') as f:
    f.seek(512); directory=f.read(1280)
    assert directory[1:5]==b'Hugo'
    entries=[]
    for pos in range(5,1227,26):
        if not directory[pos]:break
        name=bytes(x&127 for x in directory[pos:pos+10]).split(b'\0')[0].split(b'\r')[0]
        entries.append((name,pos,int.from_bytes(directory[pos+22:pos+25],'little')))
    _,pos,sector=next(e for e in entries if e[0]==b'!BOOT')
    length=int.from_bytes(directory[pos+18:pos+22],'little')
    assert int.from_bytes(directory[pos+10:pos+14],'little')==0xE00
    f.seek(sector*256); boot=bytearray(f.read(length))
assert boot[:7]==bytes.fromhex('a2 5c a0 4a 4c 04 4d')
assert boot[0x17A1-0xE00:0x17A4-0xE00]==bytes.fromhex('ad b3 17')
assert boot[0x178F-0xE00:0x1793-0xE00]==bytes.fromhex('08 8d 16 08')
append_address=0xE00+len(boot)
def emit_text(text):
    return b''.join(bytes((0xA9,ch,0x20,0xE3,0xFF)) for ch in text.encode('ascii'))
prefix=emit_text('D02 ENTRY]\r')
suffix=emit_text('[D02 RAM]\r')
source_address=append_address+len(prefix)+11+len(suffix)+7
# Copy a full page, then perform the original entry sequence.
copy=bytes((0xA2,0,0xBD,source_address&255,source_address>>8,0x9D,0,0xF0,0xE8,0xD0,0xF7))
loader=prefix+copy+suffix+bytes.fromhex('a2 5c a0 4a 4c 04 4d')
# The very first instruction emits '[' before jumping to appended code.
# Byte 7 of the original file is an unused BRK, not a referenced entry.
assert boot[7]==0
boot[:8]=bytes((0xA9,91,0x20,0xEE,0xFF,0x4C,append_address&255,append_address>>8))
boot[0x17A1-0xE00:0x17A4-0xE00]=bytes((0x4C,0,0xF0))
boot[0x178F-0xE00:0x1793-0xE00]=bytes((0x4C,returned&255,returned>>8,0xEA))
boot+=loader+debug.ljust(256,b'\0')
next_sector=min(s for _,_,s in entries if s>sector)
assert sector*256+len(boot)<=next_sector*256, 'No space in original allocation'
shutil.copyfile(args.source,args.output)
with args.output.open('r+b') as f:
    f.seek(sector*256); f.write(boot)
    f.seek(512+pos+18); f.write(len(boot).to_bytes(4,'little'))
print(f'Created {args.output}: !BOOT {length} -> {len(boot)} bytes; entry F000 return {returned:04X}')
print('Only used !BOOT allocation and its 4-byte directory length were changed.')
