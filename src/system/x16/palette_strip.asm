; ---------------------------------------------------------------------------
; palette_strip.asm - X16 HAL_ShowPaletteStrip implementation.
; ---------------------------------------------------------------------------
; Paints 16 solid-colour cells on row 2 of the text layer (VRAM $1:B200..),
; one cell per VERA palette slot 0..15. Each cell uses character $20 (space,
; all-background glyph) with attribute (slot << 4) | 0, so the cell renders
; as a solid block of palette slot N.
;
; The default VERA text mode carries 4 bits of bg per attribute byte, so
; only slots 0..15 are directly reachable by a strip of this kind. Slots
; 16..31 go through the same HAL_UploadPalette codepath and can be verified
; on a platform that exposes them (Neo6502 shows all 32).
;
; Layer map stride in the default BASIC configuration is 128 tiles wide,
; so row 2 starts 2 * 128 * 2 = 512 bytes past $1:B000, i.e. $1:B200.
; ---------------------------------------------------------------------------

.export HAL_ShowPaletteStrip

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

STRIP_COUNT = 16

.segment "BSS"

strip_idx: .res 1

.segment "CODE"

.proc HAL_ShowPaletteStrip
    ; Point VERA at row 2 col 0 ($1:B200) with auto-increment +1.
    stz VERA_ADDR_L
    lda #$B2
    sta VERA_ADDR_M
    lda #$11                        ; bit16 = 1, stride = +1
    sta VERA_ADDR_H

    stz strip_idx
@loop:
    lda #$20                        ; space glyph
    sta VERA_DATA0

    lda strip_idx
    asl
    asl
    asl
    asl                             ; (slot << 4) -> bg nibble, fg = 0
    sta VERA_DATA0

    inc strip_idx
    lda strip_idx
    cmp #STRIP_COUNT
    bne @loop
    rts
.endproc
