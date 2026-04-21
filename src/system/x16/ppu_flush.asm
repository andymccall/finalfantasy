; ---------------------------------------------------------------------------
; ppu_flush.asm - X16 HAL_FlushNametable implementation.
; ---------------------------------------------------------------------------
; Copies the first 32x30 tile region of the nametable mirror (the NES
; visible screen area) to the VERA text layer at VRAM $1:B000. Each cell
; becomes two VRAM bytes: the mirror byte as the character, then a fixed
; attribute byte of $01 (white fg on black bg).
;
; The default X16 text layer has map width 128 tiles = 256 bytes per row,
; so row N starts at $1:B000 + N * $100.
; ---------------------------------------------------------------------------

.import ppu_nt_mirror

.export HAL_FlushNametable

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

NT_COLS       = 32
NT_ROWS       = 30
ROW_BASE_HI   = $B0                     ; VRAM $1:B000 mid byte
DEFAULT_ATTR  = $01                     ; white fg on black bg

.segment "ZEROPAGE"

flush_ptr: .res 2

.segment "BSS"

flush_row: .res 1

.segment "CODE"

.proc HAL_FlushNametable
    stz flush_row
@row_loop:
    ; --- point VERA at ($1:B000 + row*$100), auto-increment +1 ---------------
    stz VERA_ADDR_L
    lda flush_row
    clc
    adc #ROW_BASE_HI
    sta VERA_ADDR_M
    lda #$11
    sta VERA_ADDR_H

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
    ; --- write 32 (char, attr) pairs for this row ----------------------------
    ldy #0
@col_loop:
    lda (flush_ptr), y
    sta VERA_DATA0
    lda #DEFAULT_ATTR
    sta VERA_DATA0
    iny
    cpy #NT_COLS
    bne @col_loop

    inc flush_row
    lda flush_row
    cmp #NT_ROWS
    bne @row_loop
    rts
.endproc
