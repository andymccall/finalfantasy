; ---------------------------------------------------------------------------
; sprites.asm - X16 HAL sprite plane (cursor + player mapman).
; ---------------------------------------------------------------------------
; FF1 builds sprite OAM in a page-aligned RAM buffer, then writes the
; buffer's page number to $4014 (OAMDMA) to upload it. On real hardware
; that DMAs 256 bytes to PPU OAM. We trap the $4014 write and call
; HAL_OAMFlush, which walks the first 32 bytes of oam (8 NES sprites --
; enough for a 2x2 cursor *or* a 2x2 mapman plus a little headroom) and
; pushes them into VERA sprite attribute memory.
;
; VERA sprites:
;   - Sprite attribute table: VRAM $1:FC00, 8 bytes per sprite, 128 max.
;   - Per-sprite attr layout (from the X16 Programmer's Reference):
;       +0/+1: sprite data VRAM address (shifted >> 5, so 32-byte granular)
;       +2/+3: X pos  (16-bit, sign-extended 10 bits)
;       +4/+5: Y pos
;       +6   : collision [7:4] | z-depth [3:2] | V-flip [1] | H-flip [0]
;       +7   : height [7:6] | width [5:4] | palette offset [3:0]
;
; VRAM layout we claim for sprite pixel data:
;   $13000..$1307F  cursor sprite tile data    (4 tiles * 32 bytes)
;   $13080..$1327F  mapman sprite tile data    (16 tiles * 32 bytes)
;   $14000..$15800  class sprite tile data     (192 tiles * 32 bytes)
;
; The data-addr field is VRAM bits 16:5 (tile = 32 bytes). For $13000
; the field value is $980 (byte +0 = $80, byte +1 = $09). Each following
; tile adds 1 to byte +0. Class CHR at $14000 -> field $A00 (byte +0 =
; $A0, byte +1 = $09) since $14000 >> 5 = $A00.
;
; NES sprite CHR is bank-swapped on the real NES, so the same tile ID
; means different pixels on the party-gen screen vs the overworld. We
; track a sprite_mode flag (0 = mapman, 1 = class) that HAL_SetSpriteMode
; flips. The tile-ID -> data-addr dispatch branches on it.
;
; Cursor tiles $F0..$F3 live at $13000 regardless of sprite_mode, so
; tile IDs >= $F0 always route to the cursor region. Class CHR spans
; $00..$BF, so the tighter $F0 threshold lets White Mage ($80) and the
; promoted classes (up to $160) read their CHR cleanly.
;
; NES tile ID -> VERA data addr dispatch:
;   sprite_mode = mapman (0):
;     $00..$0F (mapman) -> addr_lo = $84 + tile,  addr_hi = $09
;   sprite_mode = class (1):
;     $00..$BF (class)  -> addr_lo = tile,        addr_hi = $0A
;   Either mode, tile >= $80:
;     $F0..$F3 (cursor) -> addr_lo = tile - $70,  addr_hi = $09
; (bit 7 of addr_hi = Mode, 0 = 4bpp.)
;
; NES OAM attr byte -> VERA byte +6 / byte +7:
;   attr bit 0 (palette select 0/1) -> VERA byte +7 palette offset (4 or 5)
;   attr bit 6 (H-flip)              -> VERA byte +6 bit 0
;   attr bit 7 (V-flip)              -> VERA byte +6 bit 1
;   (sprite enabled at z-depth 3 via byte +6 bits 3:2 = %11 = $0C)
;
; Palettes:
;   Cursor + mapman both read NES sprite palette 0 at VERA slots $40..$43;
;   mapman also uses NES sprite palette 1 at VERA slots $50..$53 (attr
;   bit 0 = 1). palette.asm's splay() already maps NES sprite palette 0
;   and 1 into those VERA slots.
;
; NES-to-X16 coord map: NES (nx, ny) -> sprite (32 + nx, ny + 1). The +1
; undoes the NES convention that OAM Y stores "display_y - 1".
; ---------------------------------------------------------------------------

.import oam

.export HAL_SpritesInit
.export HAL_OAMFlush
.export HAL_SetSpriteMode

SPRITE_MODE_MAPMAN = 0
SPRITE_MODE_CLASS  = 1

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
VERA_CTRL   = $9F25
VERA_DC_VIDEO = $9F29

SPRITE_ATTR_L = $00                     ; $1FC00 bits 7:0
SPRITE_ATTR_M = $FC
SPRITE_ATTR_H = $11                     ; bank 1, stride +1

; Cursor tile data starts at VRAM $13000 -> data addr $980.
CURSOR_TILE_L = $00
CURSOR_TILE_M = $30
CURSOR_TILE_H = $11
CURSOR_DATA_ADDR_LO_BASE = $80
DATA_ADDR_HI             = $09          ; bit 7 = Mode = 0 = 4bpp
CLASS_DATA_ADDR_HI       = $0A          ; VRAM $14000 -> field $A00 (high nibble $0A)

; Mapman tile data starts at VRAM $13080 -> data addr $984.
MAPMAN_TILE_L = $80
MAPMAN_TILE_M = $30
MAPMAN_TILE_H = $11
MAPMAN_DATA_ADDR_LO_BASE = $84

; Class sprite tile data starts at VRAM $14000 -> data addr $A00.
CLASS_TILE_L = $00
CLASS_TILE_M = $40
CLASS_TILE_H = $11
CLASS_DATA_ADDR_LO_BASE = $00

; How many NES OAM slots HAL_OAMFlush walks. Party-gen draws 4 class
; sprites (4 * 6 = 24 slots) plus 4 cursor slots = 28. Mapman OW frames
; only touch 4..7 plus cursor $F0..$F3 at slots 0..3, which all fit.
OAM_SLOTS_WALKED = 28

; KERNAL APIs used for runtime mapman-pixel load.
;   SETLFS: A = logical file, X = device, Y = secondary addr
;   SETNAM: A = name length, X/Y = name ptr
;   LOAD:   A = 3 -> VRAM bank 1 ($10000 + XY), X/Y = VRAM offset
SETLFS = $FFBA
SETNAM = $FFBD
LOAD   = $FFD5

; mapman_vera.bin lives on the host FS next to FF.PRG. We load it once
; at boot straight into VRAM $13080 instead of shipping it in the PRG:
; 512 bytes of RODATA is enough to push BSS past $9F00 (the I/O gap),
; and cursor+mapman are our first two of many sprite assets. Runtime
; load is the pattern that scales.
MAPMAN_FILENAME_LEN = 15
CLASS_FILENAME_LEN  = 14

.segment "RODATA"

cursor_sprite_pixels:
    .incbin "cursor_vera.bin"
cursor_sprite_pixels_end:

CURSOR_PIXEL_BYTES = cursor_sprite_pixels_end - cursor_sprite_pixels

mapman_filename:
    .byte "MAPMAN_VERA.BIN"

class_filename:
    .byte "CLASS_VERA.BIN"

.segment "BSS"

sprite_mode: .res 1                     ; 0 = mapman, 1 = class

.segment "CODE"

; HAL_SpritesInit -----------------------------------------------------------
; One-shot at boot: upload cursor + mapman tile pixels, program 8 sprite
; attribute entries (all hidden), enable the sprite plane.
.proc HAL_SpritesInit
    ; --- upload cursor tile pixels to VRAM $13000 ---------------------------
    lda #CURSOR_TILE_L
    sta VERA_ADDR_L
    lda #CURSOR_TILE_M
    sta VERA_ADDR_M
    lda #CURSOR_TILE_H
    sta VERA_ADDR_H

    ldx #0
@cursor_pix:
    lda cursor_sprite_pixels, x
    sta VERA_DATA0
    inx
    cpx #CURSOR_PIXEL_BYTES
    bne @cursor_pix

    ; --- load mapman tile pixels straight from host FS into VRAM $13080 -----
    ; SETNAM -> filename; SETLFS with sa=2 -> headerless LOAD;
    ; LOAD with A=3 -> VRAM bank 1 (physical $10000 + XY).
    lda #MAPMAN_FILENAME_LEN
    ldx #<mapman_filename
    ldy #>mapman_filename
    jsr SETNAM

    lda #1                                  ; logical file
    ldx #8                                  ; device 8 (SD / host FS)
    ldy #2                                  ; secondary = 2 -> headerless
    jsr SETLFS

    lda #3                                  ; A=3 -> load into VRAM bank 1
    ldx #MAPMAN_TILE_L                      ; offset low  ($80)
    ldy #MAPMAN_TILE_M                      ; offset high ($30)
    jsr LOAD

    ; --- load class sprite tile pixels into VRAM $14000 --------------------
    lda #CLASS_FILENAME_LEN
    ldx #<class_filename
    ldy #>class_filename
    jsr SETNAM

    lda #2                                  ; logical file
    ldx #8                                  ; device 8
    ldy #2                                  ; headerless
    jsr SETLFS

    lda #3                                  ; VRAM bank 1
    ldx #CLASS_TILE_L                       ; offset low  ($00)
    ldy #CLASS_TILE_M                       ; offset high ($40)
    jsr LOAD

    ; --- default sprite mode = mapman --------------------------------------
    stz sprite_mode

    ; --- program sprite attributes, all hidden -----------------------------
    lda #SPRITE_ATTR_L
    sta VERA_ADDR_L
    lda #SPRITE_ATTR_M
    sta VERA_ADDR_M
    lda #SPRITE_ATTR_H
    sta VERA_ADDR_H

    ldx #0
@attr_loop:
    ; +0..+5 left as zero; HAL_OAMFlush rewrites them every frame.
    ; +6 = 0 -> z-depth 0 -> sprite off until first OAM push.
    ; +7 = palette offset. Defaults to 4 (NES sprite palette 0) -- the
    ; flush rewrites this per slot when it reprograms the attribute row.
    stz VERA_DATA0                      ; +0
    stz VERA_DATA0                      ; +1
    stz VERA_DATA0                      ; +2
    stz VERA_DATA0                      ; +3
    stz VERA_DATA0                      ; +4
    stz VERA_DATA0                      ; +5
    stz VERA_DATA0                      ; +6 = 0 -> disabled
    lda #$04
    sta VERA_DATA0                      ; +7 = palette offset 4
    inx
    cpx #OAM_SLOTS_WALKED
    bne @attr_loop

    ; --- enable sprite plane in DC_VIDEO -----------------------------------
    stz VERA_CTRL                       ; DCSEL=0
    lda VERA_DC_VIDEO
    ora #$40                            ; set bit 6 (sprites enable)
    sta VERA_DC_VIDEO
    rts
.endproc

; HAL_OAMFlush --------------------------------------------------------------
; Walk OAM_SLOTS_WALKED NES sprites, push each into its VERA attribute row.
;
; Registers:
;   X = sprite slot index (0..OAM_SLOTS_WALKED-1)
;   Y = walking index into oam[] (slot*4 + field)
;
.proc HAL_OAMFlush
    ldx #0
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
    tay                                 ; oam+0 (Y coord)

    ; --- hidden? (FF1 marks hidden sprites with Y >= $EF) -------------------
    lda oam, y
    cmp #$EF
    bcs @hide

    ; --- visible: +0/+1 data addr from NES tile ID --------------------------
    iny                                 ; oam+1 = tile ID
    lda oam, y
    cmp #$F0                            ; cursor tiles are $F0..$F3
    bcs @cursor_tile
    ; non-cursor: dispatch on sprite_mode (stash A, test, restore A)
    pha
    lda sprite_mode
    beq @mapman_lo
    ; class: $00..$BF -> addr_lo = tile, addr_hi = $0A
    pla
    sta VERA_DATA0                      ; attr +0 = tile (addr_lo)
    lda #CLASS_DATA_ADDR_HI
    sta VERA_DATA0                      ; attr +1 = mode 4bpp, addr hi = $0A
    bra @wrote_addr
@mapman_lo:
    pla
    clc
    adc #MAPMAN_DATA_ADDR_LO_BASE
    bra @wrote_lo
@cursor_tile:
    ; cursor: $F0..$F3 -> addr_lo = tile - $70
    sec
    sbc #$70
@wrote_lo:
    sta VERA_DATA0                      ; attr +0 = addr lo
    lda #DATA_ADDR_HI
    sta VERA_DATA0                      ; attr +1 = mode 4bpp, addr hi = $09
@wrote_addr:

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
    tay                                 ; oam+0
    lda oam, y
    clc
    adc #1
    sta VERA_DATA0                      ; attr +4 = Y low
    lda #0
    adc #0
    sta VERA_DATA0                      ; attr +5 = Y high

    ; --- +6: z-depth 3 + H/V flip from NES attr bits 6/7 --------------------
    iny
    iny                                 ; oam+2 = attr byte
    lda oam, y
    and #$C0                            ; keep flip bits
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                                 ; attr bits 7/6 -> bits 1/0
    ora #$0C                            ; z-depth 3 (%1100) in bits 3:2
    sta VERA_DATA0                      ; attr +6

    ; --- +7: palette offset from NES attr bits 1:0 -------------------------
    ; NES sprite attr bits 1:0 select one of 4 sprite palettes. splay()
    ; in palette.asm maps NES sprite palettes 0..3 to VERA palette slots
    ; $40/$50/$60/$70, so VERA palette offset = 4 + N.
    lda oam, y
    and #$03
    clc
    adc #$04
    sta VERA_DATA0                      ; attr +7
    bra @next

@hide:
    ; Write +0..+6 as zero -> z-depth 0 hides regardless of addr. Skip +7.
    stz VERA_DATA0                      ; +0
    stz VERA_DATA0                      ; +1
    stz VERA_DATA0                      ; +2
    stz VERA_DATA0                      ; +3
    stz VERA_DATA0                      ; +4
    stz VERA_DATA0                      ; +5
    stz VERA_DATA0                      ; +6 = 0 -> disabled
    stz VERA_DATA0                      ; +7 (palette offset, doesn't matter)

@next:
    inx
    cpx #OAM_SLOTS_WALKED
    beq @done
    jmp @slot
@done:
    rts
.endproc

; HAL_SetSpriteMode ---------------------------------------------------------
; A = 0 -> mapman tiles (OW), A = 1 -> class tiles (party-gen / battle).
; Flips the tile-ID -> VRAM address dispatch in HAL_OAMFlush. Cursor tiles
; always route to their own region regardless of mode.
.proc HAL_SetSpriteMode
    sta sprite_mode
    rts
.endproc
