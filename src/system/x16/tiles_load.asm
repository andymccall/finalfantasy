; ---------------------------------------------------------------------------
; tiles_load.asm - X16 HAL_LoadTiles implementation.
; ---------------------------------------------------------------------------
; Uploads the converted FF1 font (128 glyphs, 1bpp, 8 bytes per tile) into
; VERA character memory. The X16 boot default places layer 1's tile base at
; VRAM $1F000, so tile slot N starts at $1F000 + N * 8.
;
; We write the 128 glyphs contiguously starting at slot $80, so tile slot
; $80 = FF1 tile $80 (digit '0'), ..., tile slot $8A = FF1 tile $8A ('A'),
; ..., tile slot $FF = FF1 tile $FF. The Kernal-supplied PETSCII font for
; slots $01-$7F is left intact -- FF1 never references those slots -- but
; slot $00 gets its 8 bytes of pixel data zeroed so cells that the virtual
; PPU leaves at $00 render as a blank. (PETSCII $00 is '@', which would
; otherwise bleed through every untouched nametable cell.)
;
; Source byte count is 128 * 8 = 1024 = four full pages, so the FF1
; upload uses a simple 4-page outer loop with no partial-page tail.
; ---------------------------------------------------------------------------

.export HAL_LoadTiles

VERA_ADDR_L   = $9F20
VERA_ADDR_M   = $9F21
VERA_ADDR_H   = $9F22
VERA_DATA0    = $9F23
VERA_L1_TBASE = $9F36                   ; bits 7:2 = VRAM[16:11]; bits 1:0 = tile size

; Pin layer 1's tile base to VRAM $1F000 (value $F8: bits 7:2 = %111110,
; bits 1:0 = 0 for 8x8 tiles) regardless of what the Kernal left behind.
L1_TBASE_VAL  = $F8

TILEBASE_L    = $00                     ; upload start = $1F000 + $80 * 8 = $1F400
TILEBASE_M    = $F4
TILEBASE_H    = $11                     ; bank 1, stride +1

.segment "ZEROPAGE"

font_ptr: .res 2

.segment "RODATA"

ff1_font:
    .incbin "font_converted.bin"
ff1_font_end:

FONT_SIZE = ff1_font_end - ff1_font

.segment "CODE"

.proc HAL_LoadTiles
    lda #L1_TBASE_VAL
    sta VERA_L1_TBASE

    ; --- blank VRAM slot $00 (VRAM $1F000, 8 bytes) -------------------------
    stz VERA_ADDR_L
    lda #$F0
    sta VERA_ADDR_M
    lda #$11                            ; bank 1, stride +1
    sta VERA_ADDR_H
    ldx #8
@blank_loop:
    stz VERA_DATA0
    dex
    bne @blank_loop

    ; --- point VERA at slot $80 and upload the FF1 font ---------------------
    lda #TILEBASE_L
    sta VERA_ADDR_L
    lda #TILEBASE_M
    sta VERA_ADDR_M
    lda #TILEBASE_H
    sta VERA_ADDR_H

    lda #<ff1_font
    sta font_ptr + 0
    lda #>ff1_font
    sta font_ptr + 1

    ldx #>FONT_SIZE                     ; page count (exactly 4 pages)
@page_loop:
    ldy #0
@byte_loop:
    lda (font_ptr), y
    sta VERA_DATA0
    iny
    bne @byte_loop
    inc font_ptr + 1
    dex
    bne @page_loop
    rts
.endproc
