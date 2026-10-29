\ Domesday !BOOT diagnostic gate, copied to parasite RAM at &F000.
\ The patcher changes mode_value: 0 = stop visibly, 1 = skip command.
ORG &F000
.start
\ This replaces LDA &17B3 at the generic MOS-call wrapper entry.
\ Only intercept OSCLI (&FFF7); every other service follows the original path.
LDA &53:CMP #&FF:BNE normal
LDA &52:CMP #&F7:BNE normal

\ Match the command token against the known LaserVision command set.
LDX #0
.next_command
LDA commands,X:CMP #&FF:BEQ normal
LDY #0
.compare
LDA commands,X:BEQ token_end
CMP (&56),Y:BNE mismatch
INX:INY:BNE compare
.token_end
LDA (&56),Y
CMP #13:BEQ video_command
CMP #32:BEQ video_command
CMP #0:BEQ video_command
.mismatch
LDA commands,X
BEQ next_token
CMP #&FF:BEQ normal
INX:BNE mismatch
.next_token
INX:BNE next_command

.video_command
LDA mode_value:BNE skip_video
LDX #0
.print_message
LDA message,X:BEQ print_command
JSR &FFEE
INX:BNE print_message
.print_command
LDY #0
.print_loop
LDA (&56),Y
CMP #13:BEQ stopped
CMP #0:BEQ stopped
JSR &FFEE
INY:CPY #48:BCC print_loop
.stopped
LDA #13:JSR &FFE3
LDX #0
.print_stop
LDA stop_message,X:BEQ halt
JSR &FFEE
INX:BNE print_stop
.halt
JMP halt

.skip_video
\ OSCLI has no defined result. Return a neutral success-like A/flags pair
\ through the executable's original wrapper epilogue.
LDA #0:CLC:JMP &178F

.normal
LDA &17B3:JMP &17A4

.message
EQUB 13,13
EQUS "VIDEO REACHED: "
EQUB 0
.stop_message
EQUS "STOPPED BEFORE VIDEO CALL"
EQUB 13,0
.commands
EQUS "FCODE":EQUB 0
EQUS "SEARCH":EQUB 0
EQUS "PLAY":EQUB 0
EQUS "STEP":EQUB 0
EQUS "STILL":EQUB 0
EQUS "RESET":EQUB 0
EQUS "AUDIO":EQUB 0
EQUB &FF
.mode_marker
EQUB &DE,&AD,&BE,&EF
.mode_value
EQUB 0
.finish
SAVE "boot_video_gate.bin",start,finish
