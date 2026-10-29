\ Final copro RAM-test stage. Runs at &0400 after the language image has
\ copied it there, so &8000-&BFFF can be tested destructively.
oswrch = &FFEE
osasci = &FFE3
osrdch = &FFE0
oscli = &FFF7
ptr = &70
endpage = &72
pattern = &73
patternindex = &74
failaddr = &75
expected = &77
actual = &78
textptr = &79
startpage = &7B

ORG &0400
.stage2_start
LDA #stage2_banner MOD 256:STA textptr
LDA #stage2_banner DIV 256:STA textptr+1
JSR print
LDA #&80:LDX #&C0:JSR test_region
JSR result
LDA #finished MOD 256:STA textptr
LDA #finished DIV 256:STA textptr+1
JSR print
JSR osrdch
LDX #basic MOD 256:LDY #basic DIV 256
JSR oscli
.wait JMP wait

\ A=start page, X=end-exclusive page. Carry set on first mismatch.
.test_region
STA ptr+1:STA startpage:STX endpage
LDA #0:STA ptr:STA patternindex
.next_pattern
LDX patternindex
LDA patterns,X:STA pattern
JSR write_constant
JSR verify_constant
BCS failed
INC patternindex
LDA patternindex:CMP #4:BNE next_pattern
JSR write_address
JSR verify_address
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
PHP
LDA #range MOD 256:STA textptr
LDA #range DIV 256:STA textptr+1
JSR print
PLP:BCS print_fail
LDA #pass MOD 256:STA textptr
LDA #pass DIV 256:STA textptr+1
JMP print
.print_fail
LDA #fail MOD 256:STA textptr
LDA #fail DIV 256:STA textptr+1
JSR print
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
.patterns EQUB &00,&FF,&55,&AA
.stage2_banner EQUS "Final relocated stage",13,0
.range EQUS "8000-BFFF: ",0
.pass EQUS "PASS",13,0
.fail EQUS "FAIL @",0
.finished EQUS "DONE - press a key for BASIC",13,0
.basic EQUS "BASIC",13
.stage2_end
SAVE "copro_ram_stage2.bin",stage2_start,stage2_end
