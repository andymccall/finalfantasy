; ---------------------------------------------------------------------------
; tiles_load.asm - X16 HAL_LoadTiles implementation.
; ---------------------------------------------------------------------------
; Uploads the 128 converted FF1 tiles (VERA 4bpp packed, 32 bytes each =
; 4 KB total) into layer 1's tile base, populated such that NES nametable
; bytes $80..$FF index directly into VERA tile slots $80..$FF.
;
; Layer 1's tile base lives at VRAM $1:C000 (programmed in HAL_Init), so
; tile slot N starts at $1:C000 + N * 32. The FF1 tile upload therefore
; targets VRAM $1:C000 + $80 * 32 = $1:D000, running for 4 KB to cover
; slots $80..$FF.
;
; Tile slot 0 is explicitly zeroed (32 bytes of transparent pixels). The
; flush maps NES nametable byte $00 (FF1's ClearNT sentinel) to tile slot
; 0 so cleared cells render as blank over the host background. Slots
; $01..$7F are left at whatever the tile base contained before we took
; over; FF1 never emits those as nametable bytes, so it doesn't matter.
; ---------------------------------------------------------------------------

.export HAL_LoadTiles

VERA_ADDR_L   = $9F20
VERA_ADDR_M   = $9F21
VERA_ADDR_H   = $9F22
VERA_DATA0    = $9F23

; Tile slot 0 at VRAM $1:C000.
BLANK_L       = $00
BLANK_M       = $C0
BLANK_H       = $11                     ; bank 1, stride +1

; FF1 tile upload at VRAM $1:D000 (= slot $80, since slot stride is 32).
TILEBASE_L    = $00
TILEBASE_M    = $D0
TILEBASE_H    = $11                     ; bank 1, stride +1

.segment "ZEROPAGE"

font_ptr: .res 2

.segment "RODATA"

ff1_font:
    .incbin "font_converted.bin"
ff1_font_end:

FONT_SIZE_PAGES = (ff1_font_end - ff1_font) >> 8

.segment "CODE"

.proc HAL_LoadTiles
    ; --- zero tile slot 0 (32 bytes) ----------------------------------------
    lda #BLANK_L
    sta VERA_ADDR_L
    lda #BLANK_M
    sta VERA_ADDR_M
    lda #BLANK_H
    sta VERA_ADDR_H
    ldx #32
@blank_loop:
    stz VERA_DATA0
    dex
    bne @blank_loop

    ; --- point VERA at slot $80 and upload the FF1 tile CHR -----------------
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

    ldx #FONT_SIZE_PAGES                ; 4096 / 256 = 16 pages
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
