; ---------------------------------------------------------------------------
; hal.asm - Neo6502 HAL implementation.
; ---------------------------------------------------------------------------
; Vblank via API_GROUP_GRAPHICS / API_FN_FRAME_COUNT. The previous 32-bit
; counter is held in BSS; a new frame is signalled when any byte differs.
;
; On init the console screen is cleared and the virtual PPU is reset. After
; each vblank the HAL walks the 32x30 visible region of the nametable
; mirror and pushes non-zero cells through SET_CURSOR_POS + WriteCharacter.
;
; API pattern: store function in API_FUNCTION, spin until API_COMMAND is
; zero (previous call done), then store the group in API_COMMAND to fire.
; Results land in API_PARAMETERS once the call completes.
; ---------------------------------------------------------------------------

.import main
.import HAL_PPUInit
.import HAL_FlushNametable
.import HAL_LoadTiles

.export HAL_Init
.export HAL_WaitVblank
.export neo_col_offset

; --- Neo6502 API -----------------------------------------------------------
ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_CONSOLE    = $02
API_FN_DEFINE_CHAR   = $05
API_FN_SCREEN_SIZE   = $09
API_FN_CLEAR_SCREEN  = $0C

API_GROUP_GRAPHICS   = $05
API_FN_FRAME_COUNT   = $25

NES_VIEW_COLS        = 32

; ---------------------------------------------------------------------------
; Entry: exec.zip loads the binary at $0800 and jumps there.
; ---------------------------------------------------------------------------

.segment "STARTUP"
    jmp main

; ---------------------------------------------------------------------------

.segment "BSS"

last_frame_count: .res 4
neo_col_offset:   .res 1             ; (console_width - 32) / 2; added by flush

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_Init
    ; --- clear the console screen -------------------------------------------
    lda #API_FN_CLEAR_SCREEN
    sta API_FUNCTION
@wait_clear:
    lda API_COMMAND
    bne @wait_clear
    lda #API_GROUP_CONSOLE
    sta API_COMMAND
@wait_clear_done:
    lda API_COMMAND
    bne @wait_clear_done

    ; --- centre the 32-wide NES region in the (wider) console --------------
    ; Screen Size returns width in param 0, height in param 1. Firmware is
    ; known to always report a console width >= 32, so no underflow guard.
    lda #API_FN_SCREEN_SIZE
    sta API_FUNCTION
@wait_size:
    lda API_COMMAND
    bne @wait_size
    lda #API_GROUP_CONSOLE
    sta API_COMMAND
@wait_size_done:
    lda API_COMMAND
    bne @wait_size_done

    lda API_PARAMETERS + 0              ; console width in cells
    sec
    sbc #NES_VIEW_COLS
    lsr                                 ; (width - 32) / 2
    sta neo_col_offset

    stz last_frame_count + 0
    stz last_frame_count + 1
    stz last_frame_count + 2
    stz last_frame_count + 3

    jsr HAL_PPUInit
    jsr HAL_LoadTiles
    rts
.endproc

.proc HAL_WaitVblank
    ; --- wait for the frame counter to advance ------------------------------
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

    jsr HAL_FlushNametable
    rts
.endproc
