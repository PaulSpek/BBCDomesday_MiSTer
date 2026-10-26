\ BBC Master AIV SCSI diagnostic service ROM. BeebAsm v1.11.
\ Slot 1, invoked with *SCSITEST. No filing-system hooks or disk writes.
oswrch = &FFEE
osasci = &FFE3
ptr = &70
timeoutlo = &72
timeouthi = &73
laststatus = &74
result = &75
sample = &76
index = &77
checksum = &78

ORG &8000
.romstart
JMP entry
JMP service
EQUB &82
EQUB copyright-1-romstart
EQUB 1
EQUS "SCSI DIAG",0
EQUS "1.0",0
EQUB 0
.copyright EQUS "(C)2026 Domesday project",0

.entry
RTS

.service
CMP #4
BNE pass
TXA:PHA
TYA:PHA
LDX #0
.match
LDA (&F2),Y
AND #&DF
CMP command,X
BNE mismatch
INY
INX
CPX #8
BNE match
LDA (&F2),Y
CMP #13
BEQ claimed
CMP #32
BNE mismatch
.claimed
JSR run
PLA:TAY
PLA:TAX
LDA #0
RTS
.mismatch
PLA:TAY
PLA:TAX
LDA #4
.pass
RTS
.command EQUS "SCSITEST"

.run
LDA #0:STA &FC43
LDA #22:JSR oswrch
LDA #7:JSR oswrch
LDA #banner MOD 256:STA ptr
LDA #banner DIV 256:STA ptr+1
JSR print

\ Bus-free must be observable before any selection.
LDA &FC41:STA laststatus
LDA #busname MOD 256:STA ptr
LDA #busname DIV 256:STA ptr+1
JSR print
LDA laststatus:AND #&A2
BEQ goodbus
JSR fail
JMP afterbus
.goodbus JSR passline
.afterbus

\ TEST UNIT READY: six CDB bytes followed by status and message.
LDA #turname MOD 256:STA ptr
LDA #turname DIV 256:STA ptr+1
JSR print
LDA #&10:STA &FC42
LDX #0
.turcdb
LDA #&A2:JSR waitphase
BCS turfail
LDA #0:STA &FC40
INX
CPX #6
BNE turcdb
JSR endcommand
BCS turfail
JSR passline
JMP aftertur
.turfail JSR fail
.aftertur

\ READ CAPACITY: 10-byte CDB, eight bytes of response. Print each byte.
LDA #capname MOD 256:STA ptr
LDA #capname DIV 256:STA ptr+1
JSR print
LDA #&10:STA &FC42
LDX #0
.capcdb
LDA #&A2:JSR waitphase
BCS capfail
LDA captab,X:STA &FC40
INX
CPX #10
BNE capcdb
LDX #0
.capdata
LDA #&62:JSR waitphase
BCS capfail
LDA &FC40:JSR hexbyte
LDA #32:JSR oswrch
INX
CPX #8
BNE capdata
JSR endcommand
BCS capfail
JSR passline
JMP aftercap
.capfail JSR fail
.aftercap

\ READ(6), logical block 0. Consume all 256 bytes and print a checksum.
LDA #readname MOD 256:STA ptr
LDA #readname DIV 256:STA ptr+1
JSR print
LDA #&10:STA &FC42
LDX #0
.readcdb
LDA #&A2:JSR waitphase
BCS readfail
LDA readtab,X:STA &FC40
INX
CPX #6
BNE readcdb
LDA #0:STA checksum
LDX #0
.readblock
LDA #&62:JSR waitphase
BCS readfail
LDA &FC40
CLC:ADC checksum:STA checksum
INX
BNE readblock
JSR endcommand
BCS readfail
LDA checksum:JSR hexbyte
LDA #32:JSR oswrch
JSR passline
JMP afterread
.readfail JSR fail
.afterread

\ WRITE F-code ?P and read its 256-byte player-status reply.
LDA #fcodename MOD 256:STA ptr
LDA #fcodename DIV 256:STA ptr+1
JSR print
LDA #&10:STA &FC42
LDX #0
.fwritecdb
LDA #&A2:JSR waitphase
BCS fcodefail
LDA fwritetab,X:STA &FC40
INX
CPX #6
BNE fwritecdb
LDX #0
.fwriteblock
LDA #&22:JSR waitphase
BCS fcodefail
LDA fcodetext,X:STA &FC40
INX
BNE fwriteblock
JSR endcommand
BCS fcodefail
LDA #&10:STA &FC42
LDX #0
.freadcdb
LDA #&A2:JSR waitphase
BCS fcodefail
LDA freadtab,X:STA &FC40
INX
CPX #6
BNE freadcdb
LDX #0
.freadblock
LDA #&62:JSR waitphase
BCS fcodefail
LDA &FC40
CPX #0
BNE notfirst
CMP #80
BNE fcodefail
.notfirst
INX
BNE freadblock
JSR endcommand
BCS fcodefail
JSR passline
JMP done
.fcodefail JSR fail
.done
LDA #footer MOD 256:STA ptr
LDA #footer DIV 256:STA ptr+1
JSR print
LDA #0:STA &FC43
RTS

\ Expected phase bits: C/D, I/O, REQ, BSY, MSG. Ignore IRQ/spares.
\ Carry set on timeout or unexpected phase; laststatus retains FC41.
.waitphase
STA result
LDA #0:STA timeoutlo
STA timeouthi
.poll
LDA &FC41:STA laststatus
AND #&E3
CMP result
BEQ ready
INC timeoutlo
BNE poll
INC timeouthi
BNE poll
SEC
RTS
.ready
CLC
RTS

.endcommand
LDA #&E2:JSR waitphase
BCS endfail
LDA &FC40:STA sample
\ Message-in has C/D, I/O, REQ, BSY and MSG all asserted: FC41=&E3.
\ &63 incorrectly omitted C/D, making every normally completed command fail
\ only after its valid status byte had been read.
LDA #&E3:JSR waitphase
BCS endfail
LDA &FC40:STA index
LDA #0:JSR waitphase
BCS endfail
LDA sample
BNE endfail
LDA index
BNE endfail
CLC
RTS
.endfail
SEC
RTS

.passline
LDA #oktext MOD 256:STA ptr
LDA #oktext DIV 256:STA ptr+1
JMP print
.fail
LDA #failtext MOD 256:STA ptr
LDA #failtext DIV 256:STA ptr+1
JSR print
LDA laststatus:JSR hexbyte
LDA #32:JSR oswrch
LDA #88:JSR oswrch
LDA #61:JSR oswrch
TXA:JSR hexbyte
LDA #32:JSR oswrch
LDA #68:JSR oswrch
LDA #67:JSR oswrch
LDA #61:JSR oswrch
LDA #&D1:STA &FC43
LDA &FC40:JSR hexbyte
LDA #32:JSR oswrch
LDA #80:JSR oswrch
LDA #72:JSR oswrch
LDA #61:JSR oswrch
LDA #&D2:STA &FC43
LDA &FC40:JSR hexbyte
LDA #13:JSR osasci
LDA #0:STA &FC43
RTS
.print
LDY #0
.printloop
LDA (ptr),Y
BEQ printdone
JSR osasci
INY
BNE printloop
.printdone RTS
.hexbyte
PHA
LSR A:LSR A:LSR A:LSR A
JSR digit
PLA
AND #15
.digit
CMP #10
BCC numeric
CLC:ADC #7
.numeric
CLC:ADC #48
JMP oswrch

.captab EQUB &25,0,0,0,0,0,0,0,0,0
.readtab EQUB &08,0,0,0,1,0
.fwritetab EQUB &CA,0,0,0,0,0
.freadtab EQUB &C8,0,0,0,0,0
.fcodetext EQUB "?","P",13
SKIP 253
.banner EQUS "AIV SCSI diagnostic v1.1",13,"FC41 phases / bounded timeout",13,0
.busname EQUS "BUS FREE: ",0
.turname EQUS "TUR host 10: ",0
.capname EQUS "CAPACITY host 10: ",0
.readname EQUS "READ6 LBA 0 checksum: ",0
.fcodename EQUS "F-CODE ?P: ",0
.oktext EQUS "PASS",13,0
.failtext EQUS "FAIL FC41=",0
.footer EQUS "Done. Report full screen text.",13,0

SKIP &C000-P%
SAVE "scsi_diag.rom",romstart,&C000
