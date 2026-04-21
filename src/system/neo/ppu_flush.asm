; ---------------------------------------------------------------------------
; ppu_flush.asm - Neo6502 HAL_FlushNametable implementation.
; ---------------------------------------------------------------------------
; Walks the first 32x30 tile region of the nametable mirror and pushes
; non-zero cells through the Neo's console:
;
;   1. SET_CURSOR_POS(col, row)    (group $02 function $07)
;   2. WriteCharacter(byte)        (KERNAL vector $FFF1)
;
; Zero bytes are skipped and treated as "transparent" -- the screen is
; cleared once at boot, so leaving those cells untouched keeps them blank
; without issuing one API call per empty cell every frame.
; ---------------------------------------------------------------------------

.import ppu_nt_mirror

.export HAL_FlushNametable

WriteCharacter      = $FFF1

ControlPort         = $FF00
API_COMMAND         = ControlPort + 0
API_FUNCTION        = ControlPort + 1
API_PARAMETERS      = ControlPort + 4

API_GROUP_CONSOLE   = $02
API_FN_SET_CURSOR_POS = $07

NT_COLS = 32
NT_ROWS = 30

.segment "ZEROPAGE"

flush_ptr: .res 2

.segment "BSS"

flush_row: .res 1
flush_col: .res 1

.segment "CODE"

.proc HAL_FlushNametable
    stz flush_row
@row_loop:
    ; --- build flush_ptr = ppu_nt_mirror + row * 32 (16-bit add) -------------
    lda flush_row
    lsr
    lsr
    lsr                                 ; row >> 3  (high byte of row*32)
    clc
    adc #>ppu_nt_mirror
    sta flush_ptr + 1

    lda flush_row
    asl
    asl
    asl
    asl
    asl                                 ; row << 5  (low byte of row*32)
    clc
    adc #<ppu_nt_mirror
    sta flush_ptr + 0
    bcc @row_ready
    inc flush_ptr + 1

@row_ready:
    stz flush_col
    ldy #0
@col_loop:
    lda (flush_ptr), y
    beq @next_col                       ; skip transparent/empty cells

    pha                                 ; save the byte across the API call

    ; --- SET_CURSOR_POS(col, row) -------------------------------------------
@wait_cursor:
    lda API_COMMAND
    bne @wait_cursor
    lda flush_col
    sta API_PARAMETERS + 0
    lda flush_row
    sta API_PARAMETERS + 1
    lda #API_FN_SET_CURSOR_POS
    sta API_FUNCTION
    lda #API_GROUP_CONSOLE
    sta API_COMMAND
@wait_cursor_done:
    lda API_COMMAND
    bne @wait_cursor_done

    ; --- WriteCharacter(byte) -----------------------------------------------
    pla
    jsr WriteCharacter

@next_col:
    iny
    inc flush_col
    lda flush_col
    cmp #NT_COLS
    bne @col_loop

    inc flush_row
    lda flush_row
    cmp #NT_ROWS
    bne @row_loop
    rts
.endproc
