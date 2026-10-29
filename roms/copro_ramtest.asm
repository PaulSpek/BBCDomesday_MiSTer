\ BBC Master 65C02 copro RAM test language/service ROM. BeebAsm v1.11.
osbyte = &FFF4
oswrch = &FFEE
osasci = &FFE3
oscli = &FFF7
ptr = &70
endpage = &72
pattern = &73
patternindex = &74
failaddr = &75
expected = &77
actual = &78
textptr = &79
copysrc = &7B
copydst = &7D
copylen = &7F

ORG &8000
.romstart
JMP language
JMP service
EQUB &C2
EQUB copyright-1-romstart
EQUB 1
EQUS "COPRO RAM TEST",0
EQUS "1.0",0
EQUB 0
.copyright EQUS "(C)2026 Domesday project",0

\ Host-side service entry. *CPURAMTEST selects this language ROM; the MOS
\ then copies the language image through the Tube before entering it.
.service
CMP #4:BNE pass_service
TXA:PHA
TYA:PHA
LDX #0
.match
LDA (&F2),Y:AND #&DF:CMP command,X:BNE mismatch
INY:INX:CPX #10:BNE match
LDA (&F2),Y:CMP #13:BEQ claimed
CMP #32:BNE mismatch
.claimed
PLA:TAY
PLA:TAX
LDY #0:LDA #142
JSR osbyte
LDA #0:RTS
.mismatch
PLA:TAY
PLA:TAX
LDA #4
.pass_service RTS
.command EQUS "CPURAMTEST"

.language
CLI
LDX #&FF:TXS
\ Refuse destructive host operation. This probe is writable only after the
\ language image has been copied into the coprocessor's RAM.
LDA writable_probe:STA expected
EOR #&FF:STA writable_probe:CMP writable_probe:BEQ copro_confirmed
JMP not_copro
.copro_confirmed
LDA expected:STA writable_probe
LDA #banner MOD 256:STA textptr
LDA #banner DIV 256:STA textptr+1
JSR print

LDA #low_range MOD 256:STA textptr
LDA #low_range DIV 256:STA textptr+1
JSR print
LDA #&08:LDX #&80:JSR test_region:JSR result
LDA #upper_range MOD 256:STA textptr
LDA #upper_range DIV 256:STA textptr+1
JSR print
LDA #&C0:LDX #&F0:JSR test_region:JSR result
LDA #high_range MOD 256:STA textptr
LDA #high_range DIV 256:STA textptr+1
JSR print
LDA #&F0:LDX #&F8:JSR test_region:JSR result

\ Relocate the final stage to &0400 before it overwrites this ROM image.
LDA #stage2_blob MOD 256:STA copysrc
LDA #stage2_blob DIV 256:STA copysrc+1
LDA #0:STA copydst:LDA #4:STA copydst+1
LDA #stage2_size MOD 256:STA copylen
LDA #stage2_size DIV 256:STA copylen+1
.copy_loop
LDA copylen:ORA copylen+1:BEQ copy_done
LDY #0:LDA (copysrc),Y:STA (copydst),Y
INC copysrc:BNE src_ok:INC copysrc+1
.src_ok INC copydst:BNE dst_ok:INC copydst+1
.dst_ok LDA copylen:BNE len_low:DEC copylen+1
.len_low DEC copylen:JMP copy_loop
.copy_done JMP &0400

.not_copro
LDA #host_warning MOD 256:STA textptr
LDA #host_warning DIV 256:STA textptr+1
JSR print
LDX #host_basic MOD 256:LDY #host_basic DIV 256
JSR oscli
.host_wait JMP host_wait

\ A=start page, X=end-exclusive page. Carry set on first mismatch.
.test_region
STA ptr+1:STA startpage:STX endpage
LDA #0:STA ptr:STA patternindex
.next_pattern
LDX patternindex:LDA patterns,X:STA pattern
JSR write_constant:JSR verify_constant:BCS failed
INC patternindex:LDA patternindex:CMP #4:BNE next_pattern
JSR write_address:JSR verify_address
.failed RTS
.reset_pointer LDA #0:STA ptr:LDA startpage:STA ptr+1:RTS
.write_constant
JSR reset_pointer
.wc_page LDY #0:LDA pattern
.wc_byte STA (ptr),Y:INY:BNE wc_byte
INC ptr+1:LDA ptr+1:CMP endpage:BNE wc_page
RTS
.verify_constant
JSR reset_pointer
.vc_page LDY #0
.vc_byte LDA (ptr),Y:CMP pattern:BNE constant_fail
INY:BNE vc_byte
INC ptr+1:LDA ptr+1:CMP endpage:BNE vc_page
CLC:RTS
.constant_fail STA actual:LDA pattern:STA expected:JMP save_failure
.write_address
JSR reset_pointer
.wa_page LDY #0
.wa_byte TYA:EOR ptr+1:EOR #&A5:STA (ptr),Y
INY:BNE wa_byte
INC ptr+1:LDA ptr+1:CMP endpage:BNE wa_page
RTS
.verify_address
JSR reset_pointer
.va_page LDY #0
.va_byte TYA:EOR ptr+1:EOR #&A5:STA expected
LDA (ptr),Y:CMP expected:BNE address_fail
INY:BNE va_byte
INC ptr+1:LDA ptr+1:CMP endpage:BNE va_page
CLC:RTS
.address_fail STA actual
.save_failure STY failaddr:LDA ptr+1:STA failaddr+1:SEC:RTS
.result
PHP:PLP:BCS print_fail
LDA #pass MOD 256:STA textptr:LDA #pass DIV 256:STA textptr+1:JMP print
.print_fail
LDA #fail MOD 256:STA textptr:LDA #fail DIV 256:STA textptr+1:JSR print
LDA failaddr+1:JSR hexbyte:LDA failaddr:JSR hexbyte
LDA #32:JSR oswrch:LDA #69:JSR oswrch:LDA #61:JSR oswrch
LDA expected:JSR hexbyte:LDA #32:JSR oswrch
LDA #71:JSR oswrch:LDA #61:JSR oswrch:LDA actual:JSR hexbyte
LDA #13:JMP osasci
.print LDY #0
.print_loop LDA (textptr),Y:BEQ print_done:JSR osasci:INY:BNE print_loop
.print_done RTS
.hexbyte PHA:LSR A:LSR A:LSR A:LSR A:JSR digit:PLA:AND #15
.digit CMP #10:BCC number:CLC:ADC #7
.number CLC:ADC #48:JMP oswrch

.writable_probe EQUB &5A
.startpage EQUB 0
.patterns EQUB &00,&FF,&55,&AA
.banner EQUS "65C02 copro RAM test v1.0",13,"Destructive; Tube OS &F800+ preserved",13,0
.host_warning EQUS "Requires active 65C02 coprocessor",13,0
.host_basic EQUS "BASIC",13
.low_range EQUS "0800-7FFF: ",0
.upper_range EQUS "C000-EFFF: ",0
.high_range EQUS "F000-F7FF: ",0
.pass EQUS "PASS",13,0
.fail EQUS "FAIL @",0
.stage2_blob
INCBIN "copro_ram_stage2.bin"
.stage2_blob_end
stage2_size = stage2_blob_end-stage2_blob
SKIP &C000-P%
SAVE "copro_ramtest.rom",romstart,&C000
