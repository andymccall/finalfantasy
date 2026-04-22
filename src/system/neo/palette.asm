; ---------------------------------------------------------------------------
; palette.asm - Neo6502 palette HAL.
; ---------------------------------------------------------------------------
; Neo's graphics plane is 4bpp: every tile pixel indexes a single 16-slot
; palette (plus 16 additional rows used when a sprite pixel sits on top of
; a tile pixel -- see the sprite palette block further down).
;
; We don't have Neo's 16 slots per NES attribute group, so we run a flat
; 4-colour palette aligned to how FF1 uses group 3 (the "fully faded in"
; / border palette). The tile CHR produced by chr_to_neo_gfx.py stores
; pixels with nibble values 0..3 which index Neo slots 0..3 directly:
;
;   Neo slot 0 : black              (menu background / transparent)
;   Neo slot 1 : mid-grey           (menu border shade A / font)
;   Neo slot 2 : blue               (menu box fill / font background)
;   Neo slot 3 : white              (menu border shade B / glyph foreground)
;   Neo slot 4 : light grey         (cursor highlight -- FF1 title-screen
;                                    sprite palette 3 = $0F/$30/$10/$00)
;
; HAL_PalettePush is NOT a no-op: the intro-story fade animates
; cur_pal + $B (NES palette slot $0B = BG group 2 colour 3) from $01
; blue through grey shades to white, one step per frame. We hook those
; writes into Neo's Set Palette call so slot 3 tracks that colour. The
; tile glyphs rendered in pixel nibble 3 (foreground) then animate from
; blue through grey to white as FF1 expects. Group 2 is used for the
; currently-animating row on the NES; group 1 stays "hidden" (colour 3 =
; $01 blue = same as background); group 3 stays "visible" (colour 3 =
; $30 white). On Neo we have a single flat palette, so we can only
; carry ONE of those states at a time in slot 3 -- we carry whatever
; group 2 last wrote, which is fine during the intro (only one row
; animates at a time; the rest are gated off by ppu_flush reading the
; NES attr table). Colour writes to $03/$07/$0F (groups 0/1/3 colour 3)
; also land in slot 3 so the pre-faded state ($01 blue) is already live
; before the animation first writes to $0B, and the final $30 white
; sticks after the fade completes.
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
    .byte $CC, $77, $22                 ; 5 : NES $27 skin orange
                                        ;     (Fighter mapman face/legs,
                                        ;     OW sprite palette 1 colour 2)
    .byte $EE, $77, $77                 ; 6 : NES $36 light red
                                        ;     (Fighter mapman highlights,
                                        ;     OW sprite palettes 0+1 colour 3)
    .byte $00, $00, $00                 ; 7 : opaque black
                                        ;     (mapman outline -- slot 0 is
                                        ;     transparent for sprite nibble
                                        ;     0; pixel value 1 resolves here)

PALETTE_COLOURS = 8

; NES colour-index -> (R, G, B) lookup. Used by HAL_PalettePush to
; reprogram Neo slot 3 when FF1 writes a new value to any BG colour-3
; palette entry (the "foreground" colour slot the intro-story fade
; animates). 64 entries, 3 bytes each; values quantised from the
; Nestopia reference NTSC palette, mirroring the X16 HAL's 12-bit
; lookup scaled to 8 bits per channel.
;
; Blacks at $0D/$0E/$0F/$1D/$1E/$1F/$2E/$2F/$3E/$3F come out as $00
; -- those are the "off-the-colour-burst" slots the NES hardware
; blanks regardless of input.
nes_to_rgb_lut:
    .byte $75, $75, $75   ; $00 mid-grey
    .byte $00, $11, $99   ; $01 dark blue
    .byte $22, $22, $88   ; $02
    .byte $44, $22, $77   ; $03
    .byte $77, $00, $99   ; $04
    .byte $99, $00, $22   ; $05
    .byte $99, $11, $00   ; $06
    .byte $77, $11, $00   ; $07
    .byte $55, $33, $00   ; $08
    .byte $00, $66, $00   ; $09
    .byte $00, $66, $00   ; $0A
    .byte $00, $55, $11   ; $0B
    .byte $00, $44, $55   ; $0C
    .byte $00, $00, $00   ; $0D black
    .byte $00, $00, $00   ; $0E black
    .byte $00, $00, $00   ; $0F black
    .byte $BB, $BB, $BB   ; $10 light grey
    .byte $00, $77, $FF   ; $11
    .byte $00, $55, $FF   ; $12
    .byte $33, $66, $FF   ; $13
    .byte $CC, $00, $CC   ; $14
    .byte $EE, $33, $55   ; $15
    .byte $FF, $33, $00   ; $16
    .byte $EE, $55, $11   ; $17
    .byte $AA, $77, $00   ; $18
    .byte $11, $99, $00   ; $19
    .byte $00, $AA, $00   ; $1A
    .byte $11, $99, $44   ; $1B
    .byte $00, $88, $88   ; $1C
    .byte $00, $00, $00   ; $1D black
    .byte $00, $00, $00   ; $1E black
    .byte $00, $00, $00   ; $1F black
    .byte $FF, $FF, $FF   ; $20 white
    .byte $33, $BB, $FF   ; $21
    .byte $66, $88, $FF   ; $22
    .byte $99, $77, $FF   ; $23
    .byte $FF, $77, $FF   ; $24
    .byte $FF, $55, $99   ; $25
    .byte $FF, $77, $55   ; $26
    .byte $FF, $AA, $44   ; $27
    .byte $FF, $BB, $00   ; $28
    .byte $BB, $FF, $11   ; $29
    .byte $55, $DD, $55   ; $2A
    .byte $55, $FF, $99   ; $2B
    .byte $00, $EE, $DD   ; $2C
    .byte $77, $77, $77   ; $2D grey
    .byte $00, $00, $00   ; $2E black
    .byte $00, $00, $00   ; $2F black
    .byte $FF, $FF, $FF   ; $30 white
    .byte $AA, $EE, $FF   ; $31
    .byte $BB, $BB, $FF   ; $32
    .byte $DD, $BB, $FF   ; $33
    .byte $FF, $BB, $FF   ; $34
    .byte $FF, $AA, $CC   ; $35
    .byte $FF, $DD, $BB   ; $36 light peach
    .byte $FF, $EE, $AA   ; $37
    .byte $FF, $DD, $77   ; $38
    .byte $DD, $FF, $77   ; $39
    .byte $BB, $FF, $BB   ; $3A
    .byte $BB, $FF, $DD   ; $3B
    .byte $00, $FF, $FF   ; $3C
    .byte $FF, $DD, $FF   ; $3D
    .byte $00, $00, $00   ; $3E black
    .byte $00, $00, $00   ; $3F black

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

; HAL_PalettePush -----------------------------------------------------------
; Called from ppu.asm on every NES write to $3F00..$3F1F. Contract:
;   A = NES colour index (0..$3F)
;   X = NES palette slot (0..$1F; bit 4 = sprite, bits 3:2 = group,
;       bits 1:0 = colour within group)
;   Must preserve A, X, Y.
;
; We forward writes to any BG colour-3 slot ($03/$07/$0B/$0F) into Neo
; palette slot 3. During the intro-story fade, FF1 animates cur_pal+$B
; per frame (IntroStory_AnimateRow) and no other BG palette is touched,
; so Neo slot 3 tracks the grey cycle. On the title screen and in menus
; DrawPalette writes all 32 slots in order; slot $0F (group 3 colour 3)
; is written LAST and carries $30 white, so Neo slot 3 settles on white
; for post-fade steady state. Sprite-palette slots ($10+) are filtered
; out -- HAL_PaletteInit preloads Neo sprite rows with the cursor
; highlight.
;
; This is intentionally narrow: it makes the intro fade work without
; breaking anything else. Later screens may need more palette slots to
; flow through (battles, magic colour cycling); extend the filter when
; we hit those. Sprite palette writes ($10..$1F) are already ignored
; -- HAL_PaletteInit preloads Neo slot 4 with the cursor highlight,
; which is sufficient for the title-screen cursor.
;
; Implementation:
;   1. Save caller A/X/Y.
;   2. Early-exit unless X == $0B.
;   3. Look up (R, G, B) for NES colour A via nes_to_rgb_lut.
;   4. Issue Set Palette against Neo slot 3 with that RGB.
;   5. Restore A/X/Y.
.proc HAL_PalettePush
    phy
    phx
    pha

    ; --- slot filter: any NES BG colour-3 slot ($03/$07/$0B/$0F) -----------
    ; All four are "foreground" slots in their respective palette groups. On
    ; a real NES they carry different values per group (group 3 white, group
    ; 1 blue during fade, etc). We can only carry ONE of them in Neo slot 3,
    ; so we forward all four writes and let last-writer-win. During the
    ; intro-story fade only $0B is touched per-frame, so the slot tracks the
    ; grey-cycle as intended. On the title screen, DrawPalette writes all 32
    ; slots in order, so $0F (group 3 colour 3 = $30 white) lands LAST and
    ; Neo slot 3 settles at white -- which is what the menu text needs.
    txa
    and #$03                            ; isolate low 2 bits (colour within group)
    cmp #$03
    bne @done                           ; not a colour-3 slot -> ignore
    txa
    and #$10
    bne @done                           ; sprite-palette slot ($10+) -> ignore

    ; --- wait for API idle before we start scribbling parameters -----------
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    ; --- slot = Neo palette slot 3 -----------------------------------------
    lda #$03
    sta API_PARAMETERS + 0

    ; --- look up RGB from NES colour index (top of stack) -------------------
    pla                                 ; A = NES colour index
    pha                                 ; keep a copy for the restore
    and #$3F                            ; mask emphasis bits
    sta pal_slot                        ; reuse as scratch: n
    ; y = n * 3
    asl                                 ; n * 2
    clc
    adc pal_slot                        ; n * 3
    tax
    lda nes_to_rgb_lut + 0, x
    sta API_PARAMETERS + 1
    lda nes_to_rgb_lut + 1, x
    sta API_PARAMETERS + 2
    lda nes_to_rgb_lut + 2, x
    sta API_PARAMETERS + 3

    lda #API_FN_SET_PALETTE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done

@done:
    pla                                 ; restore caller's A
    plx                                 ; restore caller's X
    ply                                 ; restore caller's Y
    rts
.endproc
