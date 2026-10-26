\ Diagnostic overlay for the third-party Acorn VFS 2.02 ROM.
\
\ This code replaces only the long *HELP VFS text area at &A94D-&AA4C in
\ the generated diagnostic copy. The original VFS.rom is never modified.
\ Each wrapper executes the displaced instruction, prints a checkpoint and
\ restores processor flags and A/X/Y before returning.

osasci = &FFE3
interlace_state = &0291

ORG &A94D
.patch_start

.diag1
JSR &B6B8
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'1':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

.diag2
JSR &B6B8
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'2':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

.diag3
JSR &8E89
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'3':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

.diag4
JSR &9AAE
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'4':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

.diag5
JSR &91FC
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'5':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

.diag6
JSR &873D
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'6':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

.diag7
JSR &91FC
PHP:PHA:TXA:PHA:TYA:PHA
LDA #'7':JSR emit
PLA:TAY:PLA:TAX:PLA:PLP
RTS

\ A contains the ASCII checkpoint digit. OSASCI is used rather than direct
\ screen memory so the output follows the active BBC video mode.
.emit
PHA
LDA #13:JSR osasci
LDA #'V':JSR osasci
LDA #'F':JSR osasci
LDA #'S':JSR osasci
LDA #'-':JSR osasci
LDA #'D':JSR osasci
PLA:JSR osasci
LDA #' ':JSR osasci
LDA #'I':JSR osasci
LDA #'=':JSR osasci
LDA interlace_state
JSR hexbyte
LDA #13
JMP osasci

.hexbyte
PHA
LSR A:LSR A:LSR A:LSR A
JSR nibble
PLA
AND #15
.nibble
CMP #10
BCC numeric
CLC:ADC #7
.numeric
CLC:ADC #'0'
JMP osasci

.patch_end

IF patch_end > &AA4D
ERROR "VFS diagnostic overlay exceeds original help-text area"
ENDIF

SAVE "vfs_diag_patch.bin",patch_start,patch_end
