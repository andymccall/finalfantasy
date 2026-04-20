; ---------------------------------------------------------------------------
; hal.asm - Neo6502 HAL implementation.
; ---------------------------------------------------------------------------
; Vblank via API_GROUP_GRAPHICS / API_FN_FRAME_COUNT. The previous 32-bit
; counter is held in BSS; a new frame is signalled when any byte differs.
;
; Visible heartbeat: SET_CURSOR_POS(0,0) then WriteCharacter with a rotating
; glyph, giving a one-cell flicker at the top-left locked to the display
; refresh. The rotation is kept within printable ASCII (A..Z) so it never
; lands on a Neo control byte or a colour-change code ($80..$8F).
;
; API pattern: store function in API_FUNCTION, spin until API_COMMAND is
; zero (previous call done), then store the group in API_COMMAND to fire.
; Results land in API_PARAMETERS once the call completes.
; ---------------------------------------------------------------------------

.import main

.export HAL_Init
.export HAL_WaitVblank

; --- Neo6502 API -----------------------------------------------------------
WriteCharacter       = $FFF1

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_CONSOLE    = $02
API_FN_SET_CURSOR_POS = $07
API_FN_CLEAR_SCREEN  = $0C

API_GROUP_GRAPHICS   = $05
API_FN_FRAME_COUNT   = $25

; ---------------------------------------------------------------------------
; Entry: exec.zip loads the binary at $0800 and jumps there.
; ---------------------------------------------------------------------------

.segment "STARTUP"
    jmp main

; ---------------------------------------------------------------------------

.segment "BSS"

last_frame_count: .res 4
heartbeat_char:   .res 1

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_Init
    ; Clear screen so the heartbeat is the only thing on display.
    lda #API_FN_CLEAR_SCREEN
    sta API_FUNCTION
@wait_clear:
    lda API_COMMAND
    bne @wait_clear
    lda #API_GROUP_CONSOLE
    sta API_COMMAND

    stz last_frame_count + 0
    stz last_frame_count + 1
    stz last_frame_count + 2
    stz last_frame_count + 3
    lda #'A'                    ; keep the rotation inside printable ASCII
    sta heartbeat_char           ; ($80+ would be Neo colour-change codes)
    rts
.endproc

.proc HAL_WaitVblank
    ; --- wait for the frame counter to advance ---
@poll:
    lda #API_FN_FRAME_COUNT
    sta API_FUNCTION
@wait_poll:
    lda API_COMMAND
    bne @wait_poll
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND

    lda API_PARAMETERS + 0
    cmp last_frame_count + 0
    bne @synced
    lda API_PARAMETERS + 1
    cmp last_frame_count + 1
    bne @synced
    lda API_PARAMETERS + 2
    cmp last_frame_count + 2
    bne @synced
    lda API_PARAMETERS + 3
    cmp last_frame_count + 3
    bne @synced
    bra @poll

@synced:
    lda API_PARAMETERS + 0
    sta last_frame_count + 0
    lda API_PARAMETERS + 1
    sta last_frame_count + 1
    lda API_PARAMETERS + 2
    sta last_frame_count + 2
    lda API_PARAMETERS + 3
    sta last_frame_count + 3

    ; --- reset cursor to (0, 0) so the heartbeat overwrites in place ---
    stz API_PARAMETERS + 0
    stz API_PARAMETERS + 1
    lda #API_FN_SET_CURSOR_POS
    sta API_FUNCTION
@wait_cur:
    lda API_COMMAND
    bne @wait_cur
    lda #API_GROUP_CONSOLE
    sta API_COMMAND
@wait_cur_done:
    lda API_COMMAND
    bne @wait_cur_done

    ; --- print a rotating glyph (A..Z, wrap) ---
    lda heartbeat_char
    jsr WriteCharacter
    inc heartbeat_char
    lda heartbeat_char
    cmp #'Z'+1
    bne @done
    lda #'A'
    sta heartbeat_char
@done:
    rts
.endproc
