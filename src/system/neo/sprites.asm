; ---------------------------------------------------------------------------
; sprites.asm - Neo6502 HAL sprite plane (cursor only, for now).
; ---------------------------------------------------------------------------
; FF1 builds sprite OAM in a page-aligned RAM buffer, then writes that
; buffer's page number to $4014 (OAMDMA). Our NES-port shim traps the
; $4014 write and tail-calls HAL_OAMFlush, which on Neo drives Group 6
; Sprite Set / Sprite Hide for a single 16x16 sprite representing the
; 2x2 cursor.
;
; Why a single 16x16: the Neo Group 6 sprite plane supports only 16x16
; and 32x32 images. The FF1 cursor is a 2x2 tile block = 16x16 pixels,
; so the four NES OAM entries collapse into one Neo sprite. We read
; oam[0..3] (upper-left corner) to drive position and visibility.
;
; Graphics / sprite compositing: the Neo graphics plane is 320x240,
; stored as packed 4bpp in graphicsMemory. Tiles occupy the low nibble
; and sprites occupy the high nibble when SPRSpritesInUse() is true
; (see GFXPlotPixel: sprAnd = pixelAnd | 0xF0). Console CLS, when
; sprites are in use, masks only the low nibble -- so our per-flush
; tile clear in ppu_flush preserves the cursor automatically without
; any Sprite Reset trick.
;
; Cursor image source: the combined build/neo/tiles.gfx loaded by
; HAL_LoadTiles declares 128 tiles + 1 sprite. Sprite index 0 is the
; cursor; Draw Image uses Neo "sprite id" $80 to address that slot,
; but Sprite Set's P5 parameter is an image index into the sprite
; pool only (0 = first 16x16 sprite), so P5 = 0 here.
;
; Sprite Set parameters (Group $06, Function $02):
;   P0        sprite number (0..63, we use 0)
;   P1/P2     X coord (16-bit, screen pixels)
;   P3/P4     Y coord (16-bit)
;   P5        image index (0 = first 16x16 sprite in tiles.gfx)
;   P6        flip (bit 0 = H-flip, bit 1 = V-flip; 0 = no flip)
;   P7        anchor (0..9; 0 = *centre*, 7 = top-left. Firmware
;             offsets the draw position by anchorX/Y * size/2, so
;             anchor=0 renders a 16x16 sprite at (X,Y) from (X-8,Y-8).
;             FF1 feeds us top-left NES coords, so we pick anchor 7.)
;
; Note: the BASIC docs describe P6 as "Flip and Anchor and Flags" but
; the firmware (sprites.cpp SPRUpdate) reads flip from paramData[6]
; and anchor from paramData[7]. Size (16 vs 32) comes from bit 6 of
; P5 (imageSize), not a separate flags byte.
;
; Sprite Hide parameters (Group $06, Function $03):
;   P0        sprite number
;
; Coord math: the 32x30 NES viewport sits inside the 320x240 plane with
; a 32-pixel horizontal gutter (see ppu_flush.asm). NES sprite Y stores
; (display_y - 1) and NES X is pixel-direct.
; ---------------------------------------------------------------------------

.import oam

.export HAL_SpritesInit
.export HAL_OAMFlush

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_SPRITES    = $06
API_FN_SPRITE_SET    = $02
API_FN_SPRITE_HIDE   = $03

CURSOR_SPRITE_NUM    = 0
GUTTER_X             = 32               ; must match ppu_flush.asm

.segment "CODE"

; HAL_SpritesInit -----------------------------------------------------------
; The cursor sprite image is packed into the end of tiles.gfx and loaded
; by HAL_LoadTiles, so nothing else needs to happen here. Kept as a
; stub so hal.asm's explicit JSR is still valid if re-added later.
.proc HAL_SpritesInit
    rts
.endproc

; HAL_OAMFlush --------------------------------------------------------------
; Walk oam[0..3] (the upper-left cursor tile). FF1 marks hidden sprites
; with Y >= $EF (ClearOAM writes $F8).
.proc HAL_OAMFlush
    lda oam + 0                         ; NES Y (stored as display_y - 1)
    cmp #$EF
    bcs @hide

@wait_idle_set:
    lda API_COMMAND
    bne @wait_idle_set

    lda #CURSOR_SPRITE_NUM
    sta API_PARAMETERS + 0

    ; X = GUTTER_X + NES X (oam+3); 32 + 255 = 287, may carry.
    lda oam + 3
    clc
    adc #GUTTER_X
    sta API_PARAMETERS + 1
    lda #0
    adc #0
    sta API_PARAMETERS + 2

    ; Y = 1 + NES Y (oam+0)
    lda oam + 0
    clc
    adc #1
    sta API_PARAMETERS + 3
    lda #0
    adc #0
    sta API_PARAMETERS + 4

    stz API_PARAMETERS + 5              ; image index 0 (first 16x16 sprite)
    stz API_PARAMETERS + 6              ; flip = 0 (no H/V flip)
    lda #7                              ; anchor = top-left (see header)
    sta API_PARAMETERS + 7

    lda #API_FN_SPRITE_SET
    sta API_FUNCTION
    lda #API_GROUP_SPRITES
    sta API_COMMAND
@wait_set_done:
    lda API_COMMAND
    bne @wait_set_done
    rts

@hide:
@wait_idle_hide:
    lda API_COMMAND
    bne @wait_idle_hide
    lda #CURSOR_SPRITE_NUM
    sta API_PARAMETERS + 0
    lda #API_FN_SPRITE_HIDE
    sta API_FUNCTION
    lda #API_GROUP_SPRITES
    sta API_COMMAND
@wait_hide_done:
    lda API_COMMAND
    bne @wait_hide_done
    rts
.endproc
