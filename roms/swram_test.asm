\ BBC Master sideways RAM diagnostic service ROM. BeebAsm v1.11.
osbyte = &FFF4
srcptr = &70
dstptr = &72
copylen = &74

ORG &8000
.romstart
JMP entry
JMP service
EQUB &82
EQUB copyright-1-romstart
EQUB 1
EQUS "SWRAM TEST",0
EQUS "1.0",0
EQUB 0
.copyright EQUS "(C)2026 Domesday project",0
.entry RTS

.service
CMP #4:BNE pass
TXA:PHA
TYA:PHA
LDX #0
.match
LDA (&F2),Y:AND #&DF:CMP command,X:BNE mismatch
INY:INX:CPX #9:BNE match
LDA (&F2),Y:CMP #13:BEQ claimed
CMP #32:BNE mismatch
.claimed
PLA:TAY
PLA:TAX
TXA:PHA
LDA #engine_blob MOD 256:STA srcptr
LDA #engine_blob DIV 256:STA srcptr+1
LDA #0:STA dstptr:LDA #&20:STA dstptr+1
LDA #engine_size MOD 256:STA copylen
LDA #engine_size DIV 256:STA copylen+1
.copy_loop
LDA copylen:ORA copylen+1:BEQ copy_done
LDY #0:LDA (srcptr),Y:STA (dstptr),Y
INC srcptr:BNE src_ok:INC srcptr+1
.src_ok INC dstptr:BNE dst_ok:INC dstptr+1
.dst_ok LDA copylen:BNE len_low:DEC copylen+1
.len_low DEC copylen:JMP copy_loop
.copy_done
PLA
JMP &2000
.mismatch
PLA:TAY
PLA:TAX
LDA #4
.pass RTS
.command EQUS "SWRAMTEST"
.engine_blob
INCBIN "swram_test_engine.bin"
.engine_blob_end
engine_size = engine_blob_end-engine_blob
SKIP &C000-P%
SAVE "swram_test.rom",romstart,&C000
