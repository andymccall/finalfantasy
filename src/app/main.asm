; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. HAL_Init brings
; the display up and uploads the FF1 font into host tile memory. We stage
; an authentic-ish FF1 title palette into cur_pal, then let the verbatim
; DrawPalette routine walk it out to the virtual PPU's $3F00 window; the
; palette trap converts each byte and pokes it into host palette hardware
; via HAL_PalettePush. The verbatim TitleScreen_Copyright renders the
; two copyright lines; then we drive the verbatim DrawBox three times
; with the same box coordinates EnterTitleScreen uses -- M7b.1 is just
; the box outlines, the contained text gets wired in a later milestone.
; The vblank flush paints mirror + NES attribute table onto the host
; display each frame.
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.import cur_pal
.import box_x, box_y, box_wd, box_ht
.import menustall
.import text_ptr
.import cur_bank, ret_bank
.import DrawPalette
.import DrawBox
.import DrawComplexString
.import TitleScreen_Copyright

.export main

BANK_THIS = $00                         ; host is a flat address space; any value works

.segment "CODE"

.proc main
    jsr HAL_Init
    jsr load_title_palette
    jsr DrawPalette

    stz menustall                       ; PPU is off; no per-row stalling
    jsr TitleScreen_Copyright

    lda #BANK_THIS                      ; matches FF1's EnterTitleScreen
    sta cur_bank
    sta ret_bank

    ; --- three title-screen boxes (coords/strings from EnterTitleScreen) ---
    ; Box 1: "Continue" at (11, 10), 10 wide x 4 tall
    lda #11
    sta box_x
    lda #10
    sta box_y
    lda #10
    sta box_wd
    lda #4
    sta box_ht
    jsr DrawBox
    lda #<lut_TitleText_Continue
    sta text_ptr
    lda #>lut_TitleText_Continue
    sta text_ptr+1
    jsr DrawComplexString

    ; Box 2: "New Game" at (11, 15), same dims
    lda #15
    sta box_y
    jsr DrawBox
    lda #<lut_TitleText_NewGame
    sta text_ptr
    lda #>lut_TitleText_NewGame
    sta text_ptr+1
    jsr DrawComplexString

    ; Box 3: "Respond Rate" at (8, 20), 16 wide x 4 tall
    lda #8
    sta box_x
    lda #20
    sta box_y
    lda #16
    sta box_wd
    jsr DrawBox
    lda #<lut_TitleText_RespondRate
    sta text_ptr
    lda #>lut_TitleText_RespondRate
    sta text_ptr+1
    jsr DrawComplexString

@loop:
    jsr HAL_WaitVblank
    jmp @loop
.endproc

; Copy 32 NES colour indices from RODATA into FF1's cur_pal staging buffer.
; DrawPalette then reads cur_pal on behalf of the original game code.
.proc load_title_palette
    ldx #31
@copy:
    lda title_palette, x
    sta cur_pal, x
    dex
    bpl @copy
    rts
.endproc

.segment "RODATA"

; FF1 title-screen palette. On a real NES the menu/title screen uses a
; single shared palette group across the whole screen (ClearNT fills the
; attribute table with $FF -- i.e. every quadrant picks palette group 3),
; and the boxes look different because the box *tiles* themselves draw
; lighter/darker pixels using the group's slots 1..3. So group 3 is the
; one that actually drives every cell we render; the other groups are
; staged for palette-trap completeness and to match the NES behaviour of
; writing the full $3F00..$3F1F range.
;
; Slots 2/3 (the grey-highlight channel on real NES box tiles) can't be
; expressed in X16 text mode -- each text cell has one fg and one bg
; colour -- so we hold them at white. The grey outline detail comes back
; with the tile/bitmap renderer switch.
title_palette:
    .byte $0F, $30, $30, $30            ; group 0 (unused by title)
    .byte $0F, $30, $30, $30            ; group 1 (unused by title)
    .byte $0F, $30, $30, $30            ; group 2 (unused by title)
    .byte $01, $30, $30, $30            ; group 3: blue bg, white fg -- the title screen
    .byte $0F, $30, $30, $30            ; sprite groups (unused, staged only)
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30

; Pointerless FF1 title-screen strings (verbatim from bank_0E.asm:3654-3661).
; Every byte is >= $7A, so DrawComplexString skips all DTE and control-code
; paths and writes the bytes straight through as tile indices. $FF is the
; blank-space tile; $00 is the string terminator.
lut_TitleText_Continue:
    .byte $8C, $98, $97, $9D, $92, $97, $9E, $8E, $00
lut_TitleText_NewGame:
    .byte $97, $8E, $A0, $FF, $90, $8A, $96, $8E, $00
lut_TitleText_RespondRate:
    .byte $9B, $8E, $9C, $99, $98, $97, $8D, $FF, $9B, $8A, $9D, $8E, $00
