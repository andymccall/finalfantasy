; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. HAL_Init brings
; the display up and uploads the FF1 font into host tile memory. We stage
; an authentic-ish FF1 title palette into cur_pal, then let the verbatim
; DrawPalette routine walk it out to the virtual PPU's $3F00 window; the
; palette trap converts each byte and pokes it into host palette hardware
; via HAL_PalettePush. Finally the verbatim TitleScreen_Copyright runs:
; its STA $2006 / $2007 writes (rewritten by scripts/hook_ppu.py) land
; strings in the nametable mirror. The vblank flush paints mirror + NES
; attribute table onto the host display, so the copyright text appears in
; the colours we just uploaded.
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.import cur_pal
.import DrawPalette
.import TitleScreen_Copyright

.export main

.segment "CODE"

.proc main
    jsr HAL_Init
    jsr load_title_palette
    jsr DrawPalette
    jsr TitleScreen_Copyright

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

; FF1 title-screen palette stand-in.
;   BG groups 0..3 (slots 0..15): dark-blue backdrop ($01), white fg ($30).
;   Sprite groups (slots 16..31): black backdrop ($0F), white fg ($30).
; Only BG groups are used by the text-mode flush; the sprite writes are
; staged here so the palette trap exercises the full $3F00..$3F1F range.
title_palette:
    .byte $01, $30, $30, $30
    .byte $01, $30, $30, $30
    .byte $01, $30, $30, $30
    .byte $01, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
