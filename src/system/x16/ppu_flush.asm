; ---------------------------------------------------------------------------
; ppu_flush.asm - X16 HAL_FlushNametable implementation.
; ---------------------------------------------------------------------------
; Walks the 32x30 visible region of the NES nametable mirror and writes
; (tile_id, attr_byte) pairs into VERA layer-1's 64x32 tile map, landing
; NES col 0 at VERA map col 16 so the 32-col NES viewport sits in the
; middle of the 64-col map with 16 blank columns either side. HSCROLL
; is programmed so VERA's 40-col display window lines up with those
; central 32 columns plus a 4-col gutter each side; anything FF1 draws
; past its 32-col window (shouldn't happen, but scroll/wrap bugs do)
; lands in the blank gutter rather than wrapping around to the other
; edge of the visible image.
;
; VERA 4bpp tile-map entry (2 bytes per cell):
;   byte 0 : tile index (7:0)
;   byte 1 : palette_offset(3:0) | V-flip(1) | H-flip(1) | tile_idx(9:8)
;
; We use tile index 0..255, so tile_idx(9:8) = 0 and we never flip, leaving
; byte 1 = palette_offset << 4. palette_offset picks a 16-colour palette
; slice starting at VERA slot (palette_offset * 16), matching the NES
; attribute-group bits for that cell (group 0..3 -> VERA slots
; 0..15 / 16..31 / 32..47 / 48..63). palette.asm's splay() maps NES
; palette-RAM writes into the first four slots of each slice.
;
; NES attribute table (last 64 bytes of each nametable):
;   For a cell at (row, col) the group is attr >> shift & 3 where
;   shift = ((row & 2) << 1) | (col & 2)  -> 0, 2, 4, or 6.
;   Attr byte address within each NT = $3C0 + (row >> 2) * 8 + (col >> 2).
;
; Tile id mapping:
;   NES nametable byte $00..$7F -> VERA tile slot $00..$7F
;                                  (slot 0 = blank, rest unused by FF1)
;   NES nametable byte $80..$FF -> VERA tile slot $80..$FF (FF1 tiles)
;
; The mapping is a no-op: mirror byte goes straight out as the tile id.
; FF1's ClearNT fills the mirror with $00, which we render as the blank
; tile; everything else (box borders, glyphs) lands in $80..$FF and
; resolves via the tiles uploaded by HAL_LoadTiles.
;
; Layer 1's tile map lives at VRAM $1:B000. With 64 columns * 2 bytes per
; cell, row stride is 128 bytes (= $80), so row N starts at
; $1:B000 + N * $80. NES col 0 sits at map col 16, which is byte offset
; 32 (= $20) into each row. Each cell writes 2 consecutive bytes, so
; within a row we walk $20, $22, $24, ... up to $20 + 31*2 = $5E.
; ---------------------------------------------------------------------------

.import ppu_nt_mirror

.export HAL_FlushNametable

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

NT_COLS       = 32
NT_ROWS       = 30
TILEMAP_BASE_M = $B0                    ; VRAM $1:B000 mid byte
MAP_COL_OFFSET = 32                     ; byte offset for map col 16 (2 bytes per cell)
ATTR_OFFSET    = $3C0                   ; attribute table offset within NT0

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
    ; --- point VERA at ($1:B000 + row*$80 + MAP_COL_OFFSET) ----------------
    ; Row stride is $80 (64 cols * 2 bytes). As a 16-bit offset:
    ;   low byte  = ((row & 1) << 7) | MAP_COL_OFFSET
    ;   mid byte  = TILEMAP_BASE_M + (row >> 1)
    ; MAP_COL_OFFSET = 32 lands NES col 0 at map col 16 (= 16*2 bytes).
    lda flush_row
    lsr                                 ; C = (row & 1), A = row >> 1
    pha                                 ; save row >> 1
    lda #MAP_COL_OFFSET
    bcc @even_row
    ora #$80                            ; odd row: set bit 7 (row&1 in the $80 place)
@even_row:
    sta VERA_ADDR_L
    pla                                 ; A = row >> 1
    clc
    adc #TILEMAP_BASE_M
    sta VERA_ADDR_M
    lda #$11                            ; bank 1, stride +1
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

    ; --- write 32 (tile_id, attr) pairs for this row ------------------------
    ldy #0
@col_loop:
    ; --- byte 0: tile id = mirror byte directly -----------------------------
    lda (flush_ptr), y
    sta VERA_DATA0

    ; --- byte 1: palette_offset << 4 ---------------------------------------
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
    asl
    asl
    asl
    asl                                 ; group << 4 (palette offset field)
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
