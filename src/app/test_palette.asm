; ---------------------------------------------------------------------------
; test_palette.asm - Populates cur_pal with a vivid 32-byte NES palette so
;                    HAL_UploadPalette has visible data to push to the
;                    host display.
; ---------------------------------------------------------------------------
; The 32 bytes below are eight NES sub-palettes of four colour indices
; each -- the same shape FF1 uses for its own cur_pal buffer. Values were
; chosen to cover the width of the NES colour space (whites, pastels,
; saturated primaries, dark shades) so an incorrect NES->host LUT is
; obvious on inspection rather than silently plausible.
; ---------------------------------------------------------------------------

.import cur_pal

.export LoadTestPalette

.segment "CODE"

.proc LoadTestPalette
    ldx #31
@loop:
    lda test_palette, x
    sta cur_pal, x
    dex
    bpl @loop
    rts
.endproc

.segment "RODATA"

test_palette:
    .byte $0F, $30, $27, $12    ; black, white,     light orange, blue
    .byte $0F, $26, $16, $06    ; black, pink,      red,          dark red
    .byte $0F, $2A, $1A, $0A    ; black, lt green,  green,        dk green
    .byte $0F, $24, $14, $04    ; black, lt purple, purple,       dk purple
    .byte $0F, $31, $21, $11    ; black, lt blue,   med blue,     blue
    .byte $0F, $38, $28, $18    ; black, lt yellow, yellow,       olive
    .byte $0F, $3C, $2C, $1C    ; black, lt cyan,   cyan,         dk cyan
    .byte $0F, $20, $10, $00    ; black, white,     light grey,   grey
