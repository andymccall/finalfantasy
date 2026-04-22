; ---------------------------------------------------------------------------
; palette.asm - Neo6502 palette HAL.
; ---------------------------------------------------------------------------
; Neo currentPalette has 256 entries, indexed by the full 8-bit value in
; graphicsMemory. Tile pixels land as $0X (high nibble 0) -- the first 16
; entries $00..$0F are the "tile palette". Sprite pixels with value Y over
; a tile pixel X land as $YX, giving 16 rows of 16 sprite colours.
;
; BG tile-pixel encoding (Phase 2, group-aware)
; ---------------------------------------------
; The four OW BG palette groups (from load_map_pal) share black/green on
; colours 0/1 and differ on colours 2/3. We lay them out contiguously so
; a tile image's 4bpp nibble = (group << 2) | colour_within_group:
;
;   slot $00..$03  group 0 : $0F $1A $10 $30  (black / dk-green / lt-grey / white)
;   slot $04..$07  group 1 : $0F $1A $27 $37  (black / dk-green / orange / peach)
;   slot $08..$0B  group 2 : $0F $1A $31 $21  (black / dk-green / lt-blue / mid-blue)
;   slot $0C..$0F  group 3 : $0F $1A $29 $19  (black / dk-green / lt-green / mid-grn)
;
; chr_to_neo_gfx.py bakes each used (tile_id, group) pair as its own
; 16x16 image with nibbles aligned to the owning group. ppu_flush picks
; the correct variant per cell via a build-time lookup (see ppu_flush.asm).
;
; Sprite pixels
; -------------
; The cursor and mapman sprites keep their existing 8-slot palette in the
; high-row replication: for sprite colour N we program sprite rows $N0..$NF
; to the single RGB the sprite uses. The "sprite" colours (cursor highlight,
; skin-orange, light-red, opaque black) occupy sprite row indices 1..7 with
; the following fixed mapping, baked into the composer scripts:
;
;   sprite-nibble 0 : transparent (row $0X path uses tile slot $0X unchanged)
;   sprite-nibble 1 : opaque black                (mapman outline)
;   sprite-nibble 2 : NES $12 dark-blue-1         (mapman body palette 0)
;   sprite-nibble 3 : NES $30 white               (cursor shade)
;   sprite-nibble 4 : NES $10 light-grey          (cursor highlight)
;   sprite-nibble 5 : NES $27 skin-orange         (mapman body palette 1)
;   sprite-nibble 6 : NES $36 light-red           (mapman highlights / class pal-1 peach)
;   sprite-nibble 7 : NES $00 mid-grey            (cursor low)
;   sprite-nibble 8 : NES $28 yellow              (class palette 0 light)
;   sprite-nibble 9 : NES $18 dark-yellow         (class palette 0 dark)
;   sprite-nibble $A: NES $21 light-blue          (class palette 0 accent)
;   sprite-nibble $B: NES $16 red                 (class palette 1 dark)
;
; Rows 1..$B are each programmed with their RGB across all 16 columns so
; a sprite pixel renders the same regardless of which tile nibble sits
; beneath it.
;
; HAL_PalettePush
; ---------------
; The intro-story fade animates NES palette slot $0B (group 2 colour 3)
; from blue through grey to white. On Phase 2 we route that write into
; Neo slot $0B (group 2 colour 3) directly -- slot addressing now lines
; up with the NES. Writes to other colour-3 slots ($03/$07/$0F) are also
; forwarded to their matching Neo slots so pre-fade and post-fade steady
; states land in the right groups. This lets multiple groups hold
; different colour-3 values simultaneously, which flat-palette Phase 1
; couldn't do.
;
; Group 5 Function 32 "Set Palette" parameters:
;   P0      colour slot (0..255; we target $00..$0F + sprite rows $10..$7F)
;   P1      red   (0..255)
;   P2      green (0..255)
;   P3      blue  (0..255)
; ---------------------------------------------------------------------------

.export HAL_PalettePush
.export HAL_PaletteInit
.export HAL_PushBGSubpal
.export nes_bg_shadow
.export nes_to_rgb_lut

.import tile_mode                       ; 0 = menu, 1 = map (see tileset.asm)

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_GRAPHICS   = $05
API_FN_SET_PALETTE   = $20              ; Function 32

.segment "RODATA"

; Tile palette (R, G, B) triplets for Neo slots $00..$0F. Four OW BG
; groups laid out contiguously; colours 0/1 (black / dark green) are
; identical across groups, colours 2/3 differ. Nibble value in a tile
; image = (group << 2) | colour_within_group.
tile_palette_rgb:
    ; group 0  ($0F $1A $10 $30)
    .byte $00, $00, $00                 ; $00 : NES $0F black
    .byte $00, $AA, $00                 ; $01 : NES $1A dark green
    .byte $BB, $BB, $BB                 ; $02 : NES $10 light grey
    .byte $FF, $FF, $FF                 ; $03 : NES $30 white
    ; group 1  ($0F $1A $27 $37)
    .byte $00, $00, $00                 ; $04 : NES $0F black
    .byte $00, $AA, $00                 ; $05 : NES $1A dark green
    .byte $FF, $AA, $44                 ; $06 : NES $27 orange
    .byte $FF, $EE, $AA                 ; $07 : NES $37 peach
    ; group 2  ($0F $1A $31 $21)
    .byte $00, $00, $00                 ; $08 : NES $0F black
    .byte $00, $AA, $00                 ; $09 : NES $1A dark green
    .byte $AA, $EE, $FF                 ; $0A : NES $31 pale blue
    .byte $33, $BB, $FF                 ; $0B : NES $21 mid blue
    ; group 3  ($0F $1A $29 $19)
    .byte $00, $00, $00                 ; $0C : NES $0F black
    .byte $00, $AA, $00                 ; $0D : NES $1A dark green
    .byte $BB, $FF, $11                 ; $0E : NES $29 light green
    .byte $11, $99, $00                 ; $0F : NES $19 mid green

; Sprite palette (R, G, B) triplets for nibble values 1..7. Row 0 is
; the transparent path -- not programmed here, tile slot $0X shows
; through. Each row N is replicated across all 16 sprite columns
; $N0..$NF so sprite colour N renders identically regardless of the
; tile pixel underneath.
sprite_palette_rgb:
    .byte $00, $00, $00                 ; row 1 : opaque black (mapman outline)
    .byte $00, $55, $FF                 ; row 2 : NES $12 dark blue (mapman body pal0)
    .byte $FF, $FF, $FF                 ; row 3 : NES $30 white (cursor shade)
    .byte $BB, $BB, $BB                 ; row 4 : NES $10 light grey (cursor highlight)
    .byte $FF, $AA, $44                 ; row 5 : NES $27 orange (mapman body pal1)
    .byte $FF, $DD, $BB                 ; row 6 : NES $36 light peach (mapman highlights)
    .byte $75, $75, $75                 ; row 7 : NES $00 mid-grey (cursor low)
    .byte $FF, $BB, $00                 ; row 8 : NES $28 yellow (class pal0 light)
    .byte $AA, $77, $00                 ; row 9 : NES $18 dark yellow (class pal0 dark)
    .byte $33, $BB, $FF                 ; row $A: NES $21 light blue (class pal0 accent)
    .byte $FF, $33, $00                 ; row $B: NES $16 red (class pal1 dark)

TILE_COLOURS   = 16
SPRITE_COLOURS = 11

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

pal_slot:   .res 1                      ; Neo palette slot byte
pal_off:    .res 1                      ; byte offset into RGB source (triplet base)
pal_idx:    .res 1                      ; loop index (tile slot or sprite row)
pal_col:    .res 1                      ; sprite column 0..15
pal_colour: .res 1                      ; NES colour index for push_bg_slot

; NES BG palette shadow: 16 bytes tracking the last NES colour index (0..$3F)
; written to each of $3F00..$3F0F. ppu_flush reads this to rebuild Neo slots
; $00..$03 per cell group in map mode.
nes_bg_shadow: .res 16

.segment "CODE"

; HAL_PaletteInit -----------------------------------------------------------
; Phase 2 layout:
;   - program 16 tile slots $00..$0F from tile_palette_rgb (4 groups x 4).
;   - program 7 sprite rows 1..7, each replicated across all 16 columns,
;     from sprite_palette_rgb.
.proc HAL_PaletteInit
    ; --- tile slots $00..$0F ------------------------------------------------
    stz pal_idx
    stz pal_off
@tile_loop:
    lda pal_idx
    sta pal_slot
    ldx pal_off
    lda tile_palette_rgb + 0, x
    sta @r + 1
    lda tile_palette_rgb + 1, x
    sta @g + 1
    lda tile_palette_rgb + 2, x
    sta @b + 1
@r: lda #0
@g: ldy #0
@b: ldx #0
    jsr push_slot

    lda pal_off
    clc
    adc #3
    sta pal_off
    inc pal_idx
    lda pal_idx
    cmp #TILE_COLOURS
    bne @tile_loop

    ; --- sprite rows 1..7 (each replicated across 16 columns) ---------------
    lda #1
    sta pal_idx
    stz pal_off                         ; offset into sprite_palette_rgb
@row_loop:
    stz pal_col
    ldx pal_off
    lda sprite_palette_rgb + 0, x
    sta @sr + 1
    lda sprite_palette_rgb + 1, x
    sta @sg + 1
    lda sprite_palette_rgb + 2, x
    sta @sb + 1
@col_loop:
    lda pal_idx
    asl
    asl
    asl
    asl
    ora pal_col
    sta pal_slot
@sr: lda #0
@sg: ldy #0
@sb: ldx #0
    jsr push_slot

    inc pal_col
    lda pal_col
    cmp #16
    bne @col_loop

    lda pal_off
    clc
    adc #3
    sta pal_off
    inc pal_idx
    lda pal_idx
    cmp #(SPRITE_COLOURS + 1)
    bne @row_loop
    rts
.endproc

; push_slot -----------------------------------------------------------------
; Issue one Set Palette call.
;   pal_slot = target slot
;   A = red, Y = green, X = blue
.proc push_slot
    pha
    tya
    pha
    txa
    pha
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda pal_slot
    sta API_PARAMETERS + 0
    pla                                 ; blue
    sta API_PARAMETERS + 3
    pla                                 ; green
    sta API_PARAMETERS + 2
    pla                                 ; red
    sta API_PARAMETERS + 1

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
; Shadow: nes_bg_shadow[slot] = A for BG slots $00..$0F, consumed by
; ppu_flush to rebuild Neo slots $00..$03 when the painted cell's group
; changes.
;
; Neo slot forwarding rules:
;   Map mode  (tile_mode=1): forward NES $04..$0F -> Neo $04..$0F 1:1.
;                            Slots $00..$03 are owned by ppu_flush, it
;                            rewrites them per cell from the shadow.
;                            We skip forwarding NES $00..$03 so the
;                            flush's per-cell choice isn't fought.
;   Font mode (tile_mode=0): forward NES $0C..$0F -> Neo $00..$03 (the
;                            group-3 mirror: menu text sits in group-3
;                            attr regions, so colour-within-group values
;                            render from group 3 into the flat tile
;                            nibbles 0..3). All other BG writes drop,
;                            but the shadow is still updated -- ppu_flush
;                            can call HAL_PushBGSubpal to switch Neo
;                            $00..$03 to any group's colours when a cell
;                            with a non-group-3 attribute needs drawing
;                            (e.g. the party-gen name-input top box,
;                            which FF1 paints in group 0).
;
; Sprite-palette writes ($10..$1F) are filtered out -- sprite colours
; are baked at build-time into fixed Neo sprite rows.
.proc HAL_PalettePush
    phy
    phx
    pha

    sta pal_colour                      ; stash NES colour index for push_bg_slot

    txa
    and #$10
    beq @bg_write
    jmp @done                           ; sprite-palette slot ($10+) -> ignore
@bg_write:

    ; --- shadow update: nes_bg_shadow[slot & $0F] = colour ----------------
    txa
    and #$0F
    tay
    lda pal_colour
    sta nes_bg_shadow, y

    lda tile_mode
    bne @map_mode

    ; --- font mode: only forward NES $0C..$0F -> Neo $00..$03 -------------
    txa
    and #$0C
    cmp #$0C
    bne @done                           ; not group 3: drop
    txa
    and #$03
    sta pal_slot
    jsr push_bg_slot
    jmp @done

@map_mode:
    ; --- map mode: forward NES $04..$0F -> Neo $04..$0F; $00..$03 owned
    ; by ppu_flush so we skip them here.
    txa
    and #$0C
    beq @done                           ; group 0 ($00..$03): skip
    txa
    and #$0F
    sta pal_slot
    jsr push_bg_slot

@done:
    pla
    plx
    ply
    rts
.endproc

; push_bg_slot --------------------------------------------------------------
; Issue one Set Palette call.
;   pal_slot   = target Neo slot (0..$0F)
;   pal_colour = NES colour index (0..$3F)
; Clobbers A; preserves X, Y.
.proc push_bg_slot
    phx
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda pal_slot
    sta API_PARAMETERS + 0

    lda pal_colour
    and #$3F
    sta pal_slot                        ; scratch: n
    asl                                 ; *2
    clc
    adc pal_slot                        ; *3
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
    plx
    rts
.endproc

; HAL_PushBGSubpal ----------------------------------------------------------
; Reprogram Neo slots $00..$03 from one of the four NES BG attribute groups
; via push_bg_slot. Menu mode uses this to make per-cell group switching
; possible without re-baking font tiles for each group: the font tile
; pixel nibbles are 0..3, and Neo slots $00..$03 hold whichever group's
; colours we last pushed. ppu_flush menu-mode calls this whenever the
; current cell's attribute group differs from the group last programmed,
; then restores group 3 at the end of the flush so subsequent frames
; without any group-switch work still see the familiar menu palette.
;   On entry : A = NES attribute group 0..3
;   On exit  : Neo slots $00..$03 reprogrammed from
;              nes_bg_shadow[group*4 .. group*4 + 3]
;   Preserves : X, Y
;   Clobbers : A, pal_slot, pal_colour
.proc HAL_PushBGSubpal
    phy
    phx
    and #$03
    asl                                 ; group * 4 -> shadow base
    asl
    tay
    ldx #0
@loop:
    lda nes_bg_shadow, y
    sta pal_colour
    txa
    sta pal_slot                        ; target Neo slot 0..3
    jsr push_bg_slot
    iny
    inx
    cpx #4
    bne @loop
    plx
    ply
    rts
.endproc

