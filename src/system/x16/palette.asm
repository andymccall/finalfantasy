; ---------------------------------------------------------------------------
; palette.asm - Commander X16 HAL_PalettePush implementation.
; ---------------------------------------------------------------------------
; Called by the virtual PPU every time FF1 writes a byte in the $3F00..$3F1F
; palette window. Translates the NES colour index in A to a VERA 12-bit RGB
; word via a fixed 64-entry LUT, and pokes it into VERA palette RAM at
; $1FA00 + X*2 (so slot X ends up at VERA palette index X, matching the
; NES's 0..31 slot layout).
;
; VERA palette RAM format: two bytes per colour, little-endian, $0RGB
; (high nibble of byte 0 = G, low nibble of byte 0 = B, low nibble of
; byte 1 = R).
;
; Contract: A = NES colour index (0..$3F), X = slot (0..31). A/X/Y must be
; preserved -- the PPU trap calls this mid-instruction and surrounding
; NES code assumes STA $2007 doesn't clobber registers.
;
; Conversion is LUT-driven rather than arithmetic because the NES palette
; is NTSC-phase-based and has no clean RGB formula.
; ---------------------------------------------------------------------------

.export HAL_PalettePush

; --- VERA registers --------------------------------------------------------
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_PalettePush
    phx                                 ; save caller's X (palette slot)
    phy                                 ; save caller's Y
    pha                                 ; save caller's A (NES colour)

    ; --- point VERA at $1FA00 + slot*2, auto-increment +1 ------------------
    txa
    asl                                 ; slot * 2
    sta VERA_ADDR_L
    lda #$FA
    sta VERA_ADDR_M
    lda #$11                            ; bit16=1, stride=+1
    sta VERA_ADDR_H

    ; --- look up VERA RGB word and write both bytes ------------------------
    pla                                 ; A = NES colour
    pha                                 ; keep a copy for the caller
    and #$3F                            ; mask NES emphasis bits
    asl                                 ; * 2 (two bytes per LUT entry)
    tax
    lda nes_to_vera_lut, x              ; low byte  (GB)
    sta VERA_DATA0
    lda nes_to_vera_lut+1, x            ; high byte (0R)
    sta VERA_DATA0

    pla                                 ; restore caller's A
    ply                                 ; restore caller's Y
    plx                                 ; restore caller's X
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
