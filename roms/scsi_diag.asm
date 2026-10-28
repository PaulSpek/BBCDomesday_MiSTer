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
txcount = &79
rxcount = &7B
stage = &7D
endstep = &7E
valid = &7F
failx = &80
reply = &81
fcptr = &88
fclen = &8A
lvrow = &8B
lvchar = &8C

ORG &8000
.romstart
JMP entry
JMP service
EQUB &82
EQUB copyright-1-romstart
EQUB 1
EQUS "SCSI DIAG",0
EQUS "1.7",0
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
\ Retry the second command at the original command-tail offset.
PLA:TAY:PHA
LDX #0
.lvmatch
LDA (&F2),Y
AND #&DF
CMP lvcommand,X
BNE unclaimed
INY:INX:CPX #7:BNE lvmatch
LDA (&F2),Y
CMP #13:BEQ lvclaimed
CMP #32:BNE unclaimed
.lvclaimed
JSR runlv
PLA:TAY
PLA:TAX
LDA #0
RTS
.unclaimed
PLA:TAY
PLA:TAX
LDA #4
.pass
RTS
.command EQUS "SCSITEST"
.lvcommand EQUS "LVDTEST"

.run
LDX #&17
LDA #0
.clearwork
STA &70,X
DEX
BPL clearwork
LDA #0:STA &FC43
\ Preserve the user's display mode.
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
LDA #fcodetext MOD 256:STA fcptr
LDA #fcodetext DIV 256:STA fcptr+1
LDA #3:STA fclen
JSR exchange
BCS oldfcodefail
LDA #7:STA stage
LDA reply:CMP #80
BNE oldfcodefail
JSR passline
JSR metrics
JMP done
.oldfcodefail
JSR fail
JMP done

\ Common CA/C8 transport; never assert semantic success here.
.exchange
LDA #0
STA txcount:STA txcount+1:STA rxcount:STA rxcount+1
STA sample:STA index
LDX #6
.clearreply
STA reply,X:DEX:BPL clearreply
LDA #0:STA endstep:STA valid
LDA #1:STA stage
LDA #&10:STA &FC42
LDX #0
.fwritecdb
LDA #&A2:JSR waitphase
BCC fwritecdbready
JMP exchangefail
.fwritecdbready
LDA fwritetab,X:STA &FC40
INX
CPX #6
BNE fwritecdb
LDA #2:STA stage
LDX #0
.fwriteblock
LDA #&22:JSR waitphase
BCC fwriteblockready
JMP exchangefail
.fwriteblockready
LDA #0
CPX fclen
BCS fcpad
TXA:TAY
LDA (fcptr),Y
.fcpad
STA &FC40
INC txcount
BNE txnowrap
INC txcount+1
.txnowrap
INX
BNE fwriteblock
LDA #3:STA stage
JSR endcommand
BCS exchangefail
LDA #4:STA stage
LDA #0:STA endstep:STA valid
LDA #&10:STA &FC42
LDX #0
.freadcdb
LDA #&A2:JSR waitphase
BCS exchangefail
LDA freadtab,X:STA &FC40
INX
CPX #6
BNE freadcdb
LDA #5:STA stage
LDX #0
.freadblock
LDA #&62:JSR waitphase
BCS exchangefail
LDA &FC40
CPX #7
BCS notfirst
STA reply,X
.notfirst
INC rxcount
BNE rxnowrap
INC rxcount+1
.rxnowrap
INX
BNE freadblock
LDA #6:STA stage
JSR endcommand
BCS exchangefail
CLC
RTS
.exchangefail
STX failx
SEC
RTS
.fcodefail JSR fail
.done
LDA #footer MOD 256:STA ptr
LDA #footer DIV 256:STA ptr+1
JSR print
LDA #0:STA &FC43
RTS

\ Commands occupy eight bytes each including CR and zero padding. Both
\ frame-number queries are compared with F00001, not just transport GOOD.
.runlv
\ Preserve the user's display mode.
LDA #lvbanner MOD 256:STA ptr
LDA #lvbanner DIV 256:STA ptr+1
JSR print
LDA #0:STA lvrow:STA &FC43
.lvnext
LDA lvrow:ASL A:ASL A:ASL A
CLC:ADC #lvcommands MOD 256:STA fcptr
LDA #lvcommands DIV 256:ADC #0:STA fcptr+1
LDA #0:STA fclen
.lvlength
LDY fclen
LDA (fcptr),Y
BEQ lvsend
CMP #13:BNE lvprintchar
LDA #32
.lvprintchar
JSR osasci
INC fclen
BNE lvlength
.lvsend
JSR exchange
BCC lvtransportok
JSR fail
JMP lvadvance
.lvtransportok
LDA #lvraw MOD 256:STA ptr
LDA #lvraw DIV 256:STA ptr+1
JSR print
LDX #0
.lvrawloop
LDA reply,X:JSR hexbyte
LDA #32:JSR oswrch
INX:CPX #7:BNE lvrawloop
LDA #13:JSR osasci
\ The first frame query only checks format, the second must be frame 1.
LDA lvrow
CMP #1:BEQ lvframe
CMP #6:BEQ lvframe
CMP #5:BEQ lvseek
LDA reply
LDX lvrow
CMP lvexpected,X
BNE lvreplybad
LDA lvrow:BEQ lvloaded
CMP #7:BNE lvprefixok
.lvloaded
LDA reply+1:AND #&20:BEQ lvreplybad
.lvprefixok
JSR passline
JMP lvadvance
.lvseek
LDA reply:CMP #65:BNE lvreplybad
LDA reply+1:CMP #48:BNE lvreplybad
LDA reply+2:CMP #13:BNE lvreplybad
JSR passline
JMP lvadvance
.lvframe
LDA reply:CMP #70:BNE lvreplybad
LDX #1
.lvdigits
LDA reply,X:CMP #48:BCC lvreplybad
CMP #58:BCS lvreplybad
INX:CPX #6:BNE lvdigits
LDA reply+6:CMP #13:BNE lvreplybad
LDA lvrow:CMP #6:BNE lvframeok
LDX #1
.lvtarget
LDA reply,X:CMP lvframeone,X:BNE lvreplybad
INX:CPX #6:BNE lvtarget
.lvframeok
JSR passline
JMP lvadvance
.lvreplybad
LDA #lvbad MOD 256:STA ptr
LDA #lvbad DIV 256:STA ptr+1
JSR print
.lvadvance
INC lvrow
LDA lvrow:CMP #8:BEQ lvdone
JMP lvnext
.lvdone
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
LDA #1:STA endstep
LDA #0:STA valid
LDA #&E2:JSR waitphase
BCS endfail
LDA &FC40:STA sample
LDA #1:STA valid
LDA #2:STA endstep
\ Message-in has C/D, I/O, REQ, BSY and MSG all asserted: FC41=&E3.
\ &63 incorrectly omitted C/D, making every normally completed command fail
\ only after its valid status byte had been read.
LDA #&E3:JSR waitphase
BCS endfail
LDA &FC40:STA index
LDA #3:STA valid:STA endstep
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
STX failx
\ If a streaming wait found STATUS, capture its byte once. No debug
\ selector writes are needed, making v1.5 independent of FPGA debug HDL.
LDA laststatus:AND #&E3:CMP #&E2
BNE failprint
LDA valid:AND #1
BNE failprint
LDA &FC40:STA sample
LDA #1:STA valid
.failprint
LDA #failtext MOD 256:STA ptr
LDA #failtext DIV 256:STA ptr+1
JSR print
LDA laststatus:JSR hexbyte
LDA #32:JSR oswrch
LDA #88:JSR oswrch
LDA #61:JSR oswrch
LDA failx:JSR hexbyte
LDA #13:JSR osasci
JSR metrics
LDA #0:STA &FC43
RTS
.metrics
LDA #metrictext MOD 256:STA ptr
LDA #metrictext DIV 256:STA ptr+1
JSR print
LDA stage:JSR hexbyte
LDA #47:JSR oswrch
LDA endstep:JSR hexbyte
LDA #32:JSR oswrch
LDA result:JSR hexbyte
LDA #32:JSR oswrch
LDA txcount+1:JSR hexbyte
LDA txcount:JSR hexbyte
LDA #47:JSR oswrch
LDA rxcount+1:JSR hexbyte
LDA rxcount:JSR hexbyte
LDA #13:JSR osasci
LDA #replytext MOD 256:STA ptr
LDA #replytext DIV 256:STA ptr+1
JSR print
LDA valid:JSR hexbyte
LDA #32:JSR oswrch
LDA sample:JSR hexbyte
LDA #47:JSR oswrch
LDA index:JSR hexbyte
LDA #32:JSR oswrch
LDX #0
.replyprint
LDA reply,X:JSR hexbyte
LDA #32:JSR oswrch
INX:CPX #7:BNE replyprint
LDA #13:JMP osasci
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
.lvcommands
EQUS "?P",13:SKIP 5
EQUS "?F",13:SKIP 5
EQUS "?T1",13:SKIP 4
EQUS "?V1",13:SKIP 4
EQUS "?Y1",13:SKIP 4
EQUS "F00001R",13
EQUS "?F",13:SKIP 5
EQUS "?P",13:SKIP 5
.lvexpected EQUB 80,70,84,86,89,65,70,80
.lvframeone EQUS "F00001",13
.lvbanner EQUS "AIV LaserDisc test v1.7",13,"Mount DDV + LV-ROM before test",13,"RAW = first 7 of 256 reply bytes",13,0
.lvraw EQUS "RAW ",0
.lvbad EQUS "REPLY FAIL",13,0
.banner EQUS "AIV SCSI diagnostic v1.7",13,"FC41 phases / bounded timeout",13,0
.busname EQUS "BUS FREE: ",0
.turname EQUS "TUR host 10: ",0
.capname EQUS "CAPACITY host 10: ",0
.readname EQUS "READ6 LBA 0 checksum: ",0
.fcodename EQUS "F-CODE ?P: ",0
.oktext EQUS "PASS",13,0
.failtext EQUS "FAIL FC41=",0
.metrictext EQUS "STEP/END EXP TX/RX: ",0
.replytext EQUS "VALID S/M REPLY: ",0
.footer EQUS "Done. Report full screen text.",13,0

SKIP &C000-P%
SAVE "scsi_diag.rom",romstart,&C000
