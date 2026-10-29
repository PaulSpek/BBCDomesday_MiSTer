\ Parasite-side VFS/Tube bulk-load timing stress. Loaded/executed at &0E00.
osfile = &FFDD
oswrch = &FFEE
osasci = &FFE3
ptr = &70
remain = &72
offset = &74
expected = &76
actual = &77
failoffset = &78
iteration = &7A
destination = &7C
textptr = &7E

ORG &0E00
.start
CLD
LDX #&FF:TXS
LDA #banner MOD 256:STA textptr:LDA #banner DIV 256:STA textptr+1:JSR print
LDA #0:STA iteration:STA iteration+1

.next_load
\ Rebuild the complete OSFILE block because MOS updates it on return.
LDX #17:LDA #0
.clear_block STA fileblock,X:DEX:BPL clear_block
LDA #filename MOD 256:STA fileblock
LDA #filename DIV 256:STA fileblock+1
LDA iteration:AND #1:BEQ low_destination
LDA #&50:BNE set_destination
.low_destination LDA #&30
.set_destination
STA destination+1:STA fileblock+3
LDA #0:STA destination:STA fileblock+2
LDA #&FF:LDX #fileblock MOD 256:LDY #fileblock DIV 256
JSR osfile
CMP #1:BNE osfile_fail
JSR verify_pattern
BCS data_fail
INC iteration:BNE count_ok:INC iteration+1
.count_ok
LDA #pass MOD 256:STA textptr:LDA #pass DIV 256:STA textptr+1:JSR print
LDA iteration+1:JSR hexbyte:LDA iteration:JSR hexbyte
LDA #13:JSR oswrch
LDA iteration+1:CMP #1:BNE next_load
LDA #done MOD 256:STA textptr:LDA #done DIV 256:STA textptr+1:JSR print
.halt JMP halt

.osfile_fail
STA actual
LDA #file_error MOD 256:STA textptr:LDA #file_error DIV 256:STA textptr+1:JSR print
LDA actual:JSR hexbyte:LDA #13:JSR osasci:JMP halt

.data_fail
LDA #data_error MOD 256:STA textptr:LDA #data_error DIV 256:STA textptr+1:JSR print
LDA iteration+1:JSR hexbyte:LDA iteration:JSR hexbyte
LDA #32:JSR oswrch
LDA #68:JSR oswrch:LDA #61:JSR oswrch
LDA destination+1:JSR hexbyte:LDA destination:JSR hexbyte
LDA #32:JSR oswrch
LDA #79:JSR oswrch:LDA #61:JSR oswrch
LDA failoffset+1:JSR hexbyte:LDA failoffset:JSR hexbyte
LDA #32:JSR oswrch
LDA #69:JSR oswrch:LDA #61:JSR oswrch:LDA expected:JSR hexbyte
LDA #32:JSR oswrch
LDA #71:JSR oswrch:LDA #61:JSR oswrch:LDA actual:JSR hexbyte
LDA #13:JSR osasci:JMP halt

\ Verify file offsets &0400-&1C45 (6214 bytes). The image builder fills
\ each byte with low(offset) XOR high(offset) XOR &A5.
.verify_pattern
LDA destination:CLC:ADC #0:STA ptr
LDA destination+1:ADC #4:STA ptr+1
LDA #0:STA offset:LDA #4:STA offset+1
LDA #&46:STA remain:LDA #&18:STA remain+1
.verify_loop
LDY #0
LDA offset:EOR offset+1:EOR #&A5:STA expected
LDA (ptr),Y:CMP expected:BNE verify_fail
INC ptr:BNE ptr_ok:INC ptr+1
.ptr_ok INC offset:BNE offset_ok:INC offset+1
.offset_ok
LDA remain:BNE dec_low:DEC remain+1
.dec_low DEC remain
LDA remain:ORA remain+1:BNE verify_loop
CLC:RTS
.verify_fail
STA actual:LDA offset:STA failoffset:LDA offset+1:STA failoffset+1
SEC:RTS

.print LDY #0
.print_loop LDA (textptr),Y:BEQ print_done:JSR osasci:INY:BNE print_loop
.print_done RTS
.hexbyte PHA:LSR A:LSR A:LSR A:LSR A:JSR digit:PLA:AND #15
.digit CMP #10:BCC number:CLC:ADC #7
.number CLC:ADC #48:JMP oswrch

.fileblock SKIP 18
.filename EQUS "MENU",13
.banner EQUS "VFS/Tube timing stress v1.0",13,"256 x 7238-byte OSFILE loads",13,0
.pass EQUS "PASS ",0
.done EQUS 13,"DONE: 0100 LOADS PASS",13,0
.file_error EQUS 13,"FAIL OSFILE A=",0
.data_error EQUS 13,"FAIL I=",0
.finish
SAVE "timing_stress.bin",start,finish
