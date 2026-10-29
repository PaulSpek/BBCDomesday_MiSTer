\ Destructive BBC Master sideways-RAM test engine, relocated to host &2000.
oswrch = &FFEE
osasci = &FFE3
romsel = &FE30
ptr = &70
endpage = &72
pattern = &73
patternindex = &74
failaddr = &75
expected = &77
actual = &78
textptr = &79
bank = &7B

ORG &2000
.engine_start
STA originalslot
CLI
LDA #banner MOD 256:STA textptr
LDA #banner DIV 256:STA textptr+1
JSR print
LDA #4:STA bank
.bank_loop
JSR select_test_bank
JSR test_bank
PHP
JSR restore_rom
PLP
CLI
JSR print_bank_result
INC bank:LDA bank:CMP #8:BNE bank_loop
JSR isolation_test
LDA #finished MOD 256:STA textptr
LDA #finished DIV 256:STA textptr+1
JSR print
LDA #0
RTS

.select_test_bank
SEI
LDA bank:STA &F4:STA romsel
RTS
.restore_rom
LDA originalslot:STA &F4:STA romsel
CLI
RTS

\ Carry set on first mismatch. Tests constants then address-derived data.
.test_bank
LDA #0:STA patternindex
.next_pattern
LDX patternindex:LDA patterns,X:STA pattern
JSR write_constant:JSR verify_constant:BCS test_failed
INC patternindex:LDA patternindex:CMP #4:BNE next_pattern
JSR write_address:JSR verify_address
.test_failed RTS
.reset_pointer LDA #0:STA ptr:LDA #&80:STA ptr+1:RTS
.write_constant
JSR reset_pointer
.wc_page LDY #0:LDA pattern
.wc_byte STA (ptr),Y:INY:BNE wc_byte
INC ptr+1:LDA ptr+1:CMP #&C0:BNE wc_page
RTS
.verify_constant
JSR reset_pointer
.vc_page LDY #0
.vc_byte LDA (ptr),Y:CMP pattern:BNE constant_fail
INY:BNE vc_byte
INC ptr+1:LDA ptr+1:CMP #&C0:BNE vc_page
CLC:RTS
.constant_fail STA actual:LDA pattern:STA expected:JMP save_failure
.write_address
JSR reset_pointer
.wa_page LDY #0
.wa_byte TYA:EOR ptr+1:EOR bank:EOR #&A5:STA (ptr),Y
INY:BNE wa_byte
INC ptr+1:LDA ptr+1:CMP #&C0:BNE wa_page
RTS
.verify_address
JSR reset_pointer
.va_page LDY #0
.va_byte TYA:EOR ptr+1:EOR bank:EOR #&A5:STA expected
LDA (ptr),Y:CMP expected:BNE address_fail
INY:BNE va_byte
INC ptr+1:LDA ptr+1:CMP #&C0:BNE va_page
CLC:RTS
.address_fail STA actual
.save_failure STY failaddr:LDA ptr+1:STA failaddr+1:SEC:RTS

.print_bank_result
PHP
LDA #bank_text MOD 256:STA textptr
LDA #bank_text DIV 256:STA textptr+1
JSR print
LDA bank:JSR hexbyte
LDA #58:JSR oswrch:LDA #32:JSR oswrch
PLP:BCS print_fail
LDA #pass MOD 256:STA textptr:LDA #pass DIV 256:STA textptr+1:JMP print
.print_fail
LDA #fail MOD 256:STA textptr:LDA #fail DIV 256:STA textptr+1:JSR print
JSR print_failure:RTS
.print_failure
LDA failaddr+1:JSR hexbyte:LDA failaddr:JSR hexbyte
LDA #32:JSR oswrch:LDA #69:JSR oswrch:LDA #61:JSR oswrch
LDA expected:JSR hexbyte:LDA #32:JSR oswrch
LDA #71:JSR oswrch:LDA #61:JSR oswrch:LDA actual:JSR hexbyte
LDA #13:JMP osasci

\ Write a distinct bank/address signature to every bank, then revisit all
\ banks. Aliased bank selections cannot all retain their expected signatures.
.isolation_test
LDA #4:STA bank
.iso_write_bank
JSR select_test_bank:JSR reset_pointer
.iw_page LDY #0
.iw_byte TYA:EOR ptr+1:EOR bank:EOR #&5A:STA (ptr),Y
INY:BNE iw_byte
INC ptr+1:LDA ptr+1:CMP #&C0:BNE iw_page
INC bank:LDA bank:CMP #8:BNE iso_write_bank
LDA #4:STA bank
.iso_verify_bank
JSR select_test_bank:JSR reset_pointer
.iv_page LDY #0
.iv_byte
TYA:EOR ptr+1:EOR bank:EOR #&5A:STA expected
LDA (ptr),Y:CMP expected:BNE iso_fail
INY:BNE iv_byte
INC ptr+1:LDA ptr+1:CMP #&C0:BNE iv_page
INC bank:LDA bank:CMP #8:BNE iso_verify_bank
JSR restore_rom
LDA #isolation MOD 256:STA textptr:LDA #isolation DIV 256:STA textptr+1:JSR print
LDA #pass MOD 256:STA textptr:LDA #pass DIV 256:STA textptr+1:JMP print
.iso_fail
STA actual:STY failaddr:LDA ptr+1:STA failaddr+1
JSR restore_rom
LDA #isolation MOD 256:STA textptr:LDA #isolation DIV 256:STA textptr+1:JSR print
LDA #fail MOD 256:STA textptr:LDA #fail DIV 256:STA textptr+1:JSR print
LDA #bank_text MOD 256:STA textptr:LDA #bank_text DIV 256:STA textptr+1:JSR print
LDA bank:JSR hexbyte:LDA #32:JSR oswrch
JSR print_failure
RTS

.print LDY #0
.print_loop LDA (textptr),Y:BEQ print_done:JSR osasci:INY:BNE print_loop
.print_done RTS
.hexbyte PHA:LSR A:LSR A:LSR A:LSR A:JSR digit:PLA:AND #15
.digit CMP #10:BCC number:CLC:ADC #7
.number CLC:ADC #48:JMP oswrch

.originalslot EQUB 0
.patterns EQUB &00,&FF,&55,&AA
.banner EQUS "BBC Master sideways RAM test v1.0",13,"Banks 4-7; destructive",13,0
.bank_text EQUS "BANK ",0
.isolation EQUS "BANK ISOLATION: ",0
.pass EQUS "PASS",13,0
.fail EQUS "FAIL @",0
.finished EQUS "DONE - reset before other work",13,0
.engine_end
SAVE "swram_test_engine.bin",engine_start,engine_end
