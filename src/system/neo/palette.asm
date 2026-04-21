; ---------------------------------------------------------------------------
; palette.asm - Neo6502 palette HAL.
; ---------------------------------------------------------------------------
; Neo's graphics plane is 4bpp: tile/sprite pixels index a 16-slot palette.
; NES has 32 palette slots (16 background + 16 sprite), each pointing into
; a 64-colour master palette. Those don't fit 1:1, so we run a fixed
; 16-slot Neo palette shaped after FF1's menu/title palette:
;
;   Neo slot 0 : NES $0F -> black              (menu background / transparent)
;   Neo slot 1 : NES $00 -> mid-grey           (menu border shade A / font)
;   Neo slot 2 : NES $01 -> blue               (menu box fill / font background)
;   Neo slot 3 : NES $30 -> white              (menu border shade B)
;   Neo slot 4 : NES $10 -> light grey         (cursor highlight -- FF1
;                                              title-screen sprite palette
;                                              3 = $0F/$30/$10/$00)
;   Neo slot 5..15 : left at firmware default (unused for now)
;
; Tile pixels coming out of chr_to_neo_gfx.py pass through 2bpp values
; 0..3 unchanged, so a font glyph's foreground pixel naturally lands in
; Neo slot 1/3, menu box fill in Neo slot 2, and so on. No runtime
; reprogramming needed -- HAL_PalettePush, which fires on every write to
; $3F00..$3F1F, is kept as a no-op. If FF1 ever starts leaning on slots
; that this fixed palette doesn't cover (later screens, overworld,
; battles), we'll either expand the palette or turn HAL_PalettePush into
; a live-programmed Set Palette call and accept the lossy 32->16 mapping.
;
; Sprite palette: Neo currentPalette has 256 entries, indexed by the
; full 8-bit value in graphicsMemory. A tile pixel lands as $0X (high
; nibble 0), so we just need slots $00..$0F. A sprite pixel with value
; Y over any tile pixel X lands as $YX, so sprite colour Y -> 16 slots
; $Y0..$YF. To keep the cursor white regardless of what tile is under
; it, we mirror our tile slots 1..3 across all 16 columns of sprite
; rows 1..3 (and similarly slot 0 across row 0, which is already black
; by firmware default but we set it explicitly for sprite-transparent
; rendering). Rows $4..$F keep the firmware defaults; cursor never
; uses them.
;
; The four NES colours come from LoadBorderPalette_Blue (bank_0F.asm
; line 10200) and the title-screen background palette -- $0F/$00/$01/$30
; cover every border tile shade plus the glyph foreground. RGB values
; are quantised from the Nestopia reference palette, matching what the
; X16 HAL does (src/system/x16/palette.asm).
;
; Group 5 Function 32 "Set Palette" parameters:
;   P0      colour slot (0..15 for our purposes)
;   P1      red   (0..255)
;   P2      green (0..255)
;   P3      blue  (0..255)
; ---------------------------------------------------------------------------

.export HAL_PalettePush
.export HAL_PaletteInit

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_GRAPHICS   = $05
API_FN_SET_PALETTE   = $20              ; Function 32

.segment "RODATA"

; (R, G, B) triplets for Neo tile colours 0..3. Each triplet is also
; replicated across all 16 entries of the matching sprite row ($N0..$NF)
; at runtime -- see HAL_PaletteInit below.
palette_rgb:
    .byte $00, $00, $00                 ; 0 : NES $0F black
    .byte $75, $75, $75                 ; 1 : NES $00 mid-grey
    .byte $00, $00, $AB                 ; 2 : NES $01 dark blue
    .byte $FF, $FF, $FF                 ; 3 : NES $30 white
    .byte $BC, $BC, $BC                 ; 4 : NES $10 light grey
                                        ;     (cursor highlight -- title
                                        ;     screen's sprite palette 3 is
                                        ;     $0F/$30/$10/$00, see
                                        ;     LoadBattleSpritePalettes)

PALETTE_COLOURS = 5

.segment "BSS"

pal_row:   .res 1                       ; current colour row (0..3)
pal_col:   .res 1                       ; sprite-column iterator (0..15)
pal_slot:  .res 1                       ; composed slot byte

.segment "CODE"

; HAL_PaletteInit -----------------------------------------------------------
; For each of our 4 tile colours N:
;   - program tile slot $0N (= sprite-transparent path)
;   - program sprite slots $N0..$NF so sprite colour N renders correctly
;     regardless of what tile pixel sits underneath.
.proc HAL_PaletteInit
    stz pal_row
@row_loop:
    ; --- tile slot $0N ------------------------------------------------------
    lda pal_row                         ; slot = 0..3
    sta pal_slot
    jsr push_one

    ; --- sprite slots $N0..$NF ----------------------------------------------
    stz pal_col
@col_loop:
    lda pal_row
    asl
    asl
    asl
    asl                                 ; N << 4
    ora pal_col                         ; | column
    sta pal_slot
    jsr push_one
    inc pal_col
    lda pal_col
    cmp #16
    bne @col_loop

    inc pal_row
    lda pal_row
    cmp #PALETTE_COLOURS
    bne @row_loop
    rts
.endproc

; push_one ------------------------------------------------------------------
; Issue one Set Palette call: slot = pal_slot, RGB taken from palette_rgb
; indexed by pal_row * 3.
.proc push_one
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda pal_slot
    sta API_PARAMETERS + 0

    ; x = pal_row * 3  (0/3/6/9 for 4 rows)
    lda pal_row
    asl                                 ; *2
    clc
    adc pal_row                         ; *3
    tax
    lda palette_rgb + 0, x
    sta API_PARAMETERS + 1
    lda palette_rgb + 1, x
    sta API_PARAMETERS + 2
    lda palette_rgb + 2, x
    sta API_PARAMETERS + 3

    lda #API_FN_SET_PALETTE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done
    rts
.endproc

.proc HAL_PalettePush
    rts
.endproc
