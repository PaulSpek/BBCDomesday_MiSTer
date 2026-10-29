\ Domesday !BOOT staged checkpoint, relocated to parasite RAM at &F000.
\ Patcher mode: 0 stop after ROOT load, 1 after INIT, 2 before FCODE.
sumlo = &60
sumhi = &61
cptr = &62
remain = &64
expectlo = &66
expecthi = &67
textptr = &68
pending = &F2FE
oswrch = &FFEE
osasci = &FFE3

ORG &F000
.start
LDA #0:STA pending
\ Detect OSFILE &FF load calls for ROOT (&0494) and INIT (&049C).
LDA &53:CMP #&FF:BNE check_cli
LDA &52:CMP #&DD:BNE check_cli
LDA &54:CMP #&FF:BNE normal
LDA &57:CMP #&04:BNE normal
LDA &56:CMP #&94:BEQ mark_root
CMP #&9C:BNE normal
LDA #2:STA pending:JMP normal
.mark_root LDA #1:STA pending:JMP normal

.check_cli
LDA mode_value:CMP #2:BNE normal
LDA &53:CMP #&FF:BNE normal
LDA &52:CMP #&F7:BNE normal
LDY #0
.cli_compare
LDA (&56),Y:AND #&DF:CMP fcode,Y:BNE normal
INY:CPY #5:BNE cli_compare
LDA (&56),Y:CMP #13:BEQ before_fcode
CMP #32:BNE normal
.before_fcode
LDA #pre_fcode MOD 256:STA textptr
LDA #pre_fcode DIV 256:STA textptr+1
JSR print
JSR check_root
JSR check_init
JMP halt

.normal
LDA &17B3:JMP &17A4

\ Hooked wrapper return. Preserve the real A/flags unless this mode stops.
.returned
PHP:PHA
LDA pending:BEQ resume
CMP #1:BNE returned_init
LDA mode_value:BNE resume
LDA #after_root MOD 256:STA textptr
LDA #after_root DIV 256:STA textptr+1
JSR print:JSR check_root:JMP halt
.returned_init
LDA mode_value:CMP #1:BNE resume
LDA #after_init MOD 256:STA textptr
LDA #after_init DIV 256:STA textptr+1
JSR print:JSR check_init:JMP halt
.resume
LDA #0:STA pending
PLA:PLP
\ Original PHP / STA &0816 / PLA / STA &0817 / RTS epilogue.
PHP:STA &0816:PLA:STA &0817:RTS

.check_root
LDA #root_name MOD 256:STA textptr:LDA #root_name DIV 256:STA textptr+1:JSR print
LDA #&3C:STA cptr:LDA #&4B:STA cptr+1
LDA #&8C:STA remain:LDA #&04:STA remain+1
LDA #&E7:STA expectlo:LDA #&C6:STA expecthi
JMP checksum_and_show
.check_init
LDA #init_name MOD 256:STA textptr:LDA #init_name DIV 256:STA textptr+1:JSR print
LDA #&D0:STA cptr:LDA #&4F:STA cptr+1
LDA #&EC:STA remain:LDA #&01:STA remain+1
LDA #&9A:STA expectlo:LDA #&A9:STA expecthi
.checksum_and_show
LDA #0:STA sumlo:STA sumhi
.sum_loop
LDY #0:LDA (cptr),Y:CLC:ADC sumlo:STA sumlo:BCC no_carry:INC sumhi
.no_carry
INC cptr:BNE ptr_ok:INC cptr+1
.ptr_ok
LDA remain:BNE dec_low:DEC remain+1
.dec_low DEC remain
LDA remain:ORA remain+1:BNE sum_loop
LDA #sum_text MOD 256:STA textptr:LDA #sum_text DIV 256:STA textptr+1:JSR print
LDA sumhi:JSR hexbyte:LDA sumlo:JSR hexbyte
LDA #32:JSR oswrch
LDA sumlo:CMP expectlo:BNE show_fail
LDA sumhi:CMP expecthi:BNE show_fail
LDA #pass MOD 256:STA textptr:LDA #pass DIV 256:STA textptr+1:JMP print
.show_fail
LDA #fail MOD 256:STA textptr:LDA #fail DIV 256:STA textptr+1:JMP print

.print LDY #0
.print_loop LDA (textptr),Y:BEQ print_done:JSR osasci:INY:BNE print_loop
.print_done RTS
.hexbyte PHA:LSR A:LSR A:LSR A:LSR A:JSR digit:PLA:AND #15
.digit CMP #10:BCC number:CLC:ADC #7
.number CLC:ADC #48:JMP oswrch
.halt JMP halt

.fcode EQUS "FCODE"
.after_root EQUS 13,13,"REACHED: AFTER ROOT LOAD",13,0
.after_init EQUS 13,13,"REACHED: AFTER INIT LOAD",13,0
.pre_fcode EQUS 13,13,"REACHED: BEFORE FCODE I0",13,0
.root_name EQUS "ROOT ",0
.init_name EQUS "INIT ",0
.sum_text EQUS "SUM=",0
.pass EQUS "PASS",13,0
.fail EQUS "FAIL",13,0
.mode_marker EQUB &DE,&AD,&BE,&EF
.mode_value EQUB 0
.finish
SAVE "boot_stage_checkpoint.bin",start,finish
