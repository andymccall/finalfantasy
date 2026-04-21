; ---------------------------------------------------------------------------
; palette.asm - Commander X16 HAL_UploadPalette implementation.
; ---------------------------------------------------------------------------
; cur_pal holds 32 bytes of NES colour indices (one per logical palette
; slot). Each index is translated to a VERA 12-bit RGB word via a fixed
; 64-entry LUT, then written to VERA palette RAM at $1FA00 (colours 0-31).
;
; VERA palette RAM format: two bytes per colour, little-endian, $0RGB
; (high nibble of byte 0 = G, low nibble of byte 0 = B, low nibble of
; byte 1 = R). Auto-increment is enabled so successive stores to $9F23
; walk the palette cursor for us.
;
; Conversion is LUT-driven rather than arithmetic because the NES palette
; is NTSC-phase-based and has no clean RGB formula; on-the-fly maths in
; a 6502 vblank would also be ruinously slow.
; ---------------------------------------------------------------------------

.import cur_pal

.export HAL_UploadPalette

; --- VERA registers --------------------------------------------------------
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_UploadPalette
    ; Point VERA at $1FA00 with auto-increment of 1.
    stz VERA_ADDR_L             ; $00
    lda #$FA                    ; $FA
    sta VERA_ADDR_M
    lda #$11                    ; bit16=1, increment=1
    sta VERA_ADDR_H

    ldy #0                      ; cur_pal walker
@loop:
    lda cur_pal, y              ; NES colour index (0..$3F)
    and #$3F                    ; mask off NES "emphasis" bits if present
    asl a                       ; index * 2 (two bytes per LUT entry)
    tax
    lda nes_to_vera_lut, x      ; low byte  (GB)
    sta VERA_DATA0
    lda nes_to_vera_lut+1, x    ; high byte (0R)
    sta VERA_DATA0
    iny
    cpy #32
    bne @loop
    rts
.endproc

; ---------------------------------------------------------------------------
; NES -> VERA 12-bit RGB lookup.
; ---------------------------------------------------------------------------
; 64 entries, 2 bytes each. Values derived from the Nestopia NTSC reference
; palette, quantised from 24-bit RGB down to 4-bit per channel. Blacks at
; $0D/$0E/$0F/$1D/$1E/$1F/$2E/$2F/$3E/$3F are the "off-the-colour-burst"
; slots that the NES hardware treats as black regardless of input.
; ---------------------------------------------------------------------------

.segment "RODATA"

nes_to_vera_lut:
    .word $0777, $0019, $0028, $0427   ; $00-$03
    .word $0709, $0902, $0910, $0710   ; $04-$07
    .word $0530, $0060, $0060, $0051   ; $08-$0B
    .word $0045, $0000, $0000, $0000   ; $0C-$0F
    .word $0BBB, $007F, $005F, $036F   ; $10-$13
    .word $0C0C, $0E35, $0F30, $0E51   ; $14-$17
    .word $0A70, $0190, $00A0, $0194   ; $18-$1B
    .word $0088, $0000, $0000, $0000   ; $1C-$1F
    .word $0FFF, $03BF, $068F, $097F   ; $20-$23
    .word $0F7F, $0F59, $0F75, $0FA4   ; $24-$27
    .word $0FB0, $0BF1, $05D5, $05F9   ; $28-$2B
    .word $00ED, $0777, $0000, $0000   ; $2C-$2F
    .word $0FFF, $0AEF, $0BBF, $0DBF   ; $30-$33
    .word $0FBF, $0FAC, $0FDB, $0FEA   ; $34-$37
    .word $0FD7, $0DF7, $0BFB, $0BFD   ; $38-$3B
    .word $00FF, $0FDF, $0000, $0000   ; $3C-$3F
