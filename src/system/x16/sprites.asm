; ---------------------------------------------------------------------------
; sprites.asm - X16 HAL sprite plane (cursor only, for now).
; ---------------------------------------------------------------------------
; FF1 builds sprite OAM in a page-aligned RAM buffer, then writes the
; buffer's page number to $4014 (OAMDMA) to upload it. On real hardware
; that DMAs 256 bytes to PPU OAM. We trap the $4014 write and call
; HAL_OAMFlush, which on X16 walks the first 16 bytes of oam (four
; sprites -- the 2x2 cursor) and pushes them into VERA sprite attribute
; memory.
;
; VERA sprites:
;   - Sprite attribute table:  VRAM $1:FC00, 8 bytes per sprite, 128 max.
;   - Per-sprite attr layout (from the X16 Programmer's Reference):
;       +0/+1: sprite data VRAM address bits 4:16 (bit-shifted >> 5)
;       +2/+3: X pos (16-bit, sign-extended 10 bits)
;       +4/+5: Y pos
;       +6   : collision mask [7:4] | z-depth [3:2] | V-flip [1] | H-flip [0]
;       +7   : height [7:6] | width [5:4] | palette offset [3:0]
;   - Each sprite here is 8x8, so bytes +6/+7 are set once at init and
;     left alone; only X/Y and the "hide offscreen" Y-trick change per
;     frame.
;   - Sprites are enabled in DC_VIDEO ($9F29, DCSEL=0) bit 6.
;
; VRAM layout we claim:
;   $1:3000..$1:307F  cursor sprite tile data (4 tiles * 32 bytes, 4bpp 8x8)
;   Sprite data address is a 12-bit field covering VRAM bits 16:5
;   (32-byte granularity). For VRAM $13000 (17 bits: 1_0011_0000_0000_0000):
;       byte +0 = bits 12:5 = %10000000 = $80
;       byte +1 = bits 16:13 (low nibble) | Mode bit (bit 7 = 0 -> 4bpp)
;                 = %0000_1001 = $09
;   Each successive tile is +32 bytes in VRAM = +1 in the 12-bit field,
;   so sprite N data addr lo = $80 + N (stays in byte +0, byte +1 = $09).
;
; NES-to-X16 coord map: VERA sprite X/Y live in the 320x240 source
; coordinate space (DC_HSCALE/VSCALE scale the composited output, not
; the source). Text layer cells are 8x8 in the same 320x240 space, so
; NES cell (col, row) lands at source (col*8, row*8). The text layer
; is additionally shifted right by 32 source pixels via L1 HSCROLL to
; centre the 256-wide NES viewport in 320 source pixels; sprites don't
; follow HSCROLL, so we add the same 32-pixel gutter explicitly.
;
; Mapping: NES (nx, ny) -> sprite (32 + nx, ny + 1). The +1 undoes the
; NES convention that OAM Y stores "display_y - 1".
;
; Palette: sprites use VERA palette slots 16..31 (offset 1 in the
; 16-colour granularity). We plant the cursor foreground (white) at
; slot 17 so a 2bpp nibble value of 1 renders as white. Slot 16 is
; transparent by VERA convention (nibble 0 = transparent on sprites).
; ---------------------------------------------------------------------------

.import oam

.export HAL_SpritesInit
.export HAL_OAMFlush

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
VERA_CTRL   = $9F25
VERA_DC_VIDEO = $9F29                   ; DCSEL=0

SPRITE_ATTR_L = $00                     ; $1FC00 bits 7:0
SPRITE_ATTR_M = $FC
SPRITE_ATTR_H = $11                     ; bank 1, stride +1

SPRITE_TILE_L = $00                     ; $13000 bits 7:0
SPRITE_TILE_M = $30
SPRITE_TILE_H = $11                     ; bank 1, stride +1

; VRAM $13000. Byte +0 holds address bits 12:5; byte +1 holds bits
; 16:13 in its low nibble (bit 7 of the byte is the Mode flag: 0=4bpp).
; $13000 = 0b1_0011_00000_0000_0000 => bits 16:13 = %1001 = $9,
; bits 12:5 = %10000000 = $80.
SPRITE_DATA_ADDR_L = $80
SPRITE_DATA_ADDR_H = $09

; Sprite palette. The cursor CHR uses nibble values 1/2/3 for hand body
; (most pixels), edge highlight, and outline respectively. With palette
; offset 1 in byte +7, those nibbles index VERA palette slots 17/18/19
; (at VRAM $1:FA22 / $1:FA24 / $1:FA26 -- two bytes per slot, GB then R).
; We paint all three white for now; finer cursor shading lands with the
; full NES-palette mapping. Slot 16 (nibble 0) is transparent as usual.
SPRITE_PAL_ADDR_L = $22                 ; slot 17 * 2 = $22
SPRITE_PAL_ADDR_M = $FA
SPRITE_PAL_ADDR_H = $11

.segment "RODATA"

cursor_sprite_pixels:
    .incbin "cursor_vera.bin"
cursor_sprite_pixels_end:

CURSOR_PIXEL_BYTES = cursor_sprite_pixels_end - cursor_sprite_pixels

.segment "CODE"

; HAL_SpritesInit -----------------------------------------------------------
; One-shot at boot: upload cursor tile pixels, set palette slot 17 to
; white, program the 4 sprite attribute entries' static fields, enable
; the sprite plane.
.proc HAL_SpritesInit
    ; --- upload cursor tile pixels to VRAM $13000 ---------------------------
    lda #SPRITE_TILE_L
    sta VERA_ADDR_L
    lda #SPRITE_TILE_M
    sta VERA_ADDR_M
    lda #SPRITE_TILE_H
    sta VERA_ADDR_H

    ldx #0
@pix_loop:
    lda cursor_sprite_pixels, x
    sta VERA_DATA0
    inx
    cpx #CURSOR_PIXEL_BYTES
    bne @pix_loop

    ; --- sprite palette slots 17/18/19 all = white ($0FFF) ------------------
    ; 2 bytes per slot: low byte = GB nibbles, high byte = 0R nibbles.
    lda #SPRITE_PAL_ADDR_L
    sta VERA_ADDR_L
    lda #SPRITE_PAL_ADDR_M
    sta VERA_ADDR_M
    lda #SPRITE_PAL_ADDR_H
    sta VERA_ADDR_H
    ldx #3
@pal_loop:
    lda #$FF                            ; GB = $FF
    sta VERA_DATA0
    lda #$0F                            ; 0R = $0F
    sta VERA_DATA0
    dex
    bne @pal_loop

    ; --- program 4 sprite attributes, all hidden (y = $3FF) -----------------
    ; Sprite slot 0..3 at $1FC00, $1FC08, $1FC10, $1FC18.
    lda #SPRITE_ATTR_L
    sta VERA_ADDR_L
    lda #SPRITE_ATTR_M
    sta VERA_ADDR_M
    lda #SPRITE_ATTR_H
    sta VERA_ADDR_H

    ldx #0
@attr_loop:
    ; +0/+1: data addr (bits 16:5 of VRAM). Each successive tile is +32
    ; bytes, which in the shifted-by-5 encoding is +1 in the low byte.
    ; Byte +1 bit 7 is the Mode flag (0 = 4bpp); the top nibble of the
    ; byte carries address bits 16:13, which is 0 for our $13000 base.
    txa                                 ; sprite index 0..3
    clc
    adc #SPRITE_DATA_ADDR_L
    sta VERA_DATA0
    lda #SPRITE_DATA_ADDR_H
    sta VERA_DATA0
    ; +2/+3: X = 0
    stz VERA_DATA0
    stz VERA_DATA0
    ; +4/+5: Y = 0
    stz VERA_DATA0
    stz VERA_DATA0
    ; +6: z-depth = 0 (sprite disabled), no flip, no collision. The
    ; OAMDMA hook re-enables (z=3) each frame for slots with visible
    ; NES OAM entries and disables the rest.
    stz VERA_DATA0
    ; +7: size 8x8 (height=0, width=0), palette offset 1 (slots 16..31)
    lda #$01
    sta VERA_DATA0
    inx
    cpx #4
    bne @attr_loop

    ; --- enable sprite plane in DC_VIDEO -----------------------------------
    stz VERA_CTRL                       ; DCSEL=0
    lda VERA_DC_VIDEO
    ora #$40                            ; set bit 6 (sprites enable)
    sta VERA_DC_VIDEO
    rts
.endproc

; HAL_OAMFlush --------------------------------------------------------------
; Called on every NES $4014 OAMDMA write. Walks oam[0..15] (the 2x2
; cursor: 4 sprites of 4 bytes each), translates each to VERA sprite
; attribute coords, and writes bytes +2..+5 of each attribute entry.
; The static fields (+0/+1/+6/+7) are left alone from init.
;
; NES OAM entry: byte 0 = Y, 1 = tile, 2 = attr, 3 = X.
; NES Y stores (display_y - 1), so +1 to the Y we read.
; Hide sprite: if nes_y >= $EF (real NES off-screen marker is $F0+; FF1
; uses $FF in ClearOAM), write Y=$3FF.
; The NES OAM tile ID lets any sprite slot reference any tile, so we
; must translate per slot -- the cursor LUT, for instance, puts UL in
; slot 0 but DL in slot 1. Our CHR lays tiles out in linear NES order
; starting at VRAM $13000, so for NES tile $F0+N the data-addr field
; bits 16:5 = $980 + N: byte +0 = $80 + N = T - $70, byte +1 = $09
; (valid only for T in $F0..$F3; extending to other sprite tiles is a
; later step).
.proc HAL_OAMFlush
    ldx #0                              ; sprite index 0..3
@slot:
    ; --- point VERA at attr +0 of sprite[x] ($1FC00 + x*8) ------------------
    txa
    asl
    asl
    asl                                 ; x * 8
    clc
    adc #SPRITE_ATTR_L
    sta VERA_ADDR_L
    lda #SPRITE_ATTR_M
    sta VERA_ADDR_M
    lda #SPRITE_ATTR_H
    sta VERA_ADDR_H

    ; --- OAM entry base = x * 4 ---------------------------------------------
    txa
    asl
    asl                                 ; x * 4
    tay                                 ; oam byte index for oam+0 (Y)

    ; --- hidden? (FF1 marks hidden sprites with Y >= $EF) -------------------
    lda oam, y
    cmp #$EF
    bcs @hide

    ; --- visible: +0/+1 data addr from NES tile ID --------------------------
    iny                                 ; oam+1 = tile ID
    lda oam, y
    sec
    sbc #$70                            ; T - $70 = $80 + (T - $F0)
    sta VERA_DATA0                      ; attr +0 = addr lo
    lda #SPRITE_DATA_ADDR_H
    sta VERA_DATA0                      ; attr +1 = mode 4bpp (bit 7 = 0), addr hi = $09

    ; --- +2/+3: X = 32 + NES X (oam+3) --------------------------------------
    iny
    iny                                 ; oam+3
    lda oam, y
    clc
    adc #32
    sta VERA_DATA0                      ; attr +2 = X low
    lda #0
    adc #0
    sta VERA_DATA0                      ; attr +3 = X high

    ; --- +4/+5: Y = 1 + NES Y (oam+0) ---------------------------------------
    txa
    asl
    asl
    tay
    lda oam, y
    clc
    adc #1
    sta VERA_DATA0                      ; attr +4 = Y low
    lda #0
    adc #0
    sta VERA_DATA0                      ; attr +5 = Y high
    ; +6: enable at z-depth 3 (front of both layers).
    lda #$0C
    sta VERA_DATA0
    bra @next

@hide:
    ; Skip +0/+1 (keep whatever addr is there) and write +2..+6 with
    ; everything zero -> z-depth=0 disables the sprite regardless.
    ; We still need to advance the VERA address through +0/+1 first;
    ; STZ two bytes there as a no-op rewrite.
    stz VERA_DATA0                      ; attr +0
    stz VERA_DATA0                      ; attr +1
    stz VERA_DATA0                      ; attr +2
    stz VERA_DATA0                      ; attr +3
    stz VERA_DATA0                      ; attr +4
    stz VERA_DATA0                      ; attr +5
    stz VERA_DATA0                      ; attr +6 = 0 -> z-depth=0

@next:
    inx
    cpx #4
    bne @slot
    rts
.endproc
