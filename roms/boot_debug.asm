\ Diagnostic only: Domesday parasite heap ends at &EFFC; ROM starts &F800.
\ Copied from appended file data to &F000 before original startup.
ORG &F000
.start
PHP:PHA:TXA:PHA:TYA:PHA
LDA #13:JSR &FFE3
LDA #62:JSR &FFEE
LDA &53:JSR hex
LDA &52:JSR hex
LDA #32:JSR &FFEE
LDA &54:JSR hex
LDA #32:JSR &FFEE
LDA &57:JSR hex
LDA &56:JSR hex
\ Show the actual OSCLI text, limited to 64 characters.
LDA &52:CMP #&F7:BNE commanddone
LDA &53:CMP #&FF:BNE commanddone
LDA #32:JSR &FFEE
LDY #0
.commandloop
LDA (&56),Y
CMP #13:BEQ commanddone
CMP #0:BEQ commanddone
JSR &FFEE
INY:CPY #64:BCC commandloop
.commanddone
LDA #13:JSR &FFE3
PLA:TAY:PLA:TAX:PLA:PLP
\ Original instruction displaced by the entry hook.
LDA &17B3
JMP &17A4

.returned
PHP:PHA:TXA:PHA:TYA:PHA
LDA #60:JSR &FFEE
\ Stack: Y, X, A, flags. Read saved A without changing the stack.
TSX:LDA &0103,X:JSR hex
LDA #32:JSR &FFEE
TSX:LDA &0104,X:JSR hex
LDA #13:JSR &FFE3
PLA:TAY:PLA:TAX:PLA:PLP
\ Original PHP / STA &0816 displaced by the return hook.
PHP:STA &0816
JMP &1793

.hex
PHA:LSR A:LSR A:LSR A:LSR A
JSR digit
PLA:AND #15
.digit
CMP #10:BCC number
CLC:ADC #7
.number
CLC:ADC #48
JMP &FFEE
.finish
SAVE "boot_debug.bin",start,finish
