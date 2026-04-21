; ---------------------------------------------------------------------------
; ppu_flush.asm - X16 HAL_FlushNametable implementation.
; ---------------------------------------------------------------------------
; Copies the 32x30 visible region of the nametable mirror to the VERA text
; layer at VRAM $1:B000. Each cell becomes two VRAM bytes: the mirror byte
; as the character, then a VERA text attribute byte decoded from the
; matching NES attribute table entry.
;
; NES attribute table:
;   Last 64 bytes of each nametable ($23C0..$23FF for NT0) -- one byte per
;   4x4-tile region. Each byte packs four 2-bit palette group indices
;   (one per 2x2-tile quadrant):
;       bits 0-1: top-left        bits 4-5: bottom-left
;       bits 2-3: top-right       bits 6-7: bottom-right
;   For a tile at (row, col) the group is attr >> shift & 3 where
;   shift = ((row & 2) << 1) | (col & 2)  -> 0, 2, 4, or 6.
;
; VERA text mode attribute byte: (bg << 4) | fg, 4-bit indices into VERA
; palette slots 0-15. FF1 uses four palette groups (slots 0-3, 4-7, 8-11,
; 12-15), each with the universal backdrop at slot+0 and foreground at
; slot+1, so group G -> VERA attr byte (G*4 << 4) | (G*4 + 1):
;   group 0 -> $01    group 2 -> $89
;   group 1 -> $45    group 3 -> $CD
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
ATTR_OFFSET   = $3C0                    ; attribute table offset within NT0

.segment "ZEROPAGE"

flush_ptr: .res 2
attr_ptr:  .res 2

.segment "BSS"

flush_row:       .res 1
flush_row_shift: .res 1                 ; (row & 2) << 1: 0 or 4

.segment "CODE"

.proc HAL_FlushNametable
    stz flush_row
@row_loop:
    ; --- point VERA at ($1:B000 + row*$100), auto-increment +1 --------------
    stz VERA_ADDR_L
    lda flush_row
    clc
    adc #ROW_BASE_HI
    sta VERA_ADDR_M
    lda #$11
    sta VERA_ADDR_H

    ; --- build flush_ptr = ppu_nt_mirror + row * 32 (16-bit add) ------------
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
    bcc @attr_setup
    inc flush_ptr + 1

@attr_setup:
    ; --- attr_ptr = ppu_nt_mirror + $3C0 + (row >> 2) * 8 -------------------
    lda flush_row
    lsr
    lsr                                 ; row >> 2 (0..7)
    asl
    asl
    asl                                 ; * 8  (0..56), fits in one byte
    clc
    adc #<(ppu_nt_mirror + ATTR_OFFSET)
    sta attr_ptr + 0
    lda #>(ppu_nt_mirror + ATTR_OFFSET)
    adc #0                              ; pick up carry if any
    sta attr_ptr + 1

    ; --- flush_row_shift = (row & 2) << 1 -----------------------------------
    lda flush_row
    and #$02
    asl
    sta flush_row_shift

    ; --- write 32 (char, attr) pairs for this row ---------------------------
    ldy #0
@col_loop:
    lda (flush_ptr), y                  ; tile byte
    sta VERA_DATA0

    ; Fetch the attribute byte covering this cell. attr_col = col >> 2.
    phy                                 ; save NT column index
    tya
    lsr
    lsr                                 ; col >> 2 (0..7)
    tay
    lda (attr_ptr), y
    ply                                 ; restore NT column index

    ; Shift right by flush_row_shift + (col & 2) -> 0, 2, 4, or 6.
    pha                                 ; save attr byte
    tya
    and #$02
    ora flush_row_shift
    tax                                 ; X = shift count
    pla                                 ; attr byte back in A
@shift_loop:
    cpx #0
    beq @shift_done
    lsr
    lsr
    dex
    dex
    bra @shift_loop
@shift_done:
    and #$03                            ; group 0..3
    tax
    lda attr_lut, x
    sta VERA_DATA0

    iny
    cpy #NT_COLS
    bne @col_loop

    inc flush_row
    lda flush_row
    cmp #NT_ROWS
    beq @done                           ; short branch out; the loop back
    jmp @row_loop                       ; needs a long jump now that the
@done:                                  ; body exceeds the -128 branch range
    rts
.endproc

.segment "RODATA"

; Palette group -> VERA text attribute byte. bg = group*4, fg = group*4+1.
attr_lut:
    .byte $01, $45, $89, $CD
