; ---------------------------------------------------------------------------
; palette.asm - Commander X16 HAL_PalettePush implementation.
; ---------------------------------------------------------------------------
; Called by the virtual PPU every time FF1 writes a byte in the $3F00..$3F1F
; palette window. Translates the NES colour index in A to a VERA 12-bit RGB
; word via a fixed 64-entry LUT, and pokes it into a VERA palette slot
; derived from the NES slot number.
;
; NES-slot -> VERA-slot splay:
;   The NES slot number X is a 5-bit value SNNCC where S is the BG/sprite
;   flag (bit 4: 0 = BG, 1 = sprite), NN is the attribute group (0..3),
;   and CC is the colour within that group (0..3). VERA's 4bpp tile
;   renderer uses the tile-map "palette offset" field to pick a 16-colour
;   palette slice (slots N*16 + 0..15). We need NES group N's four
;   colours to land at VERA slots N*16 + 0..3 so a tile pixel with NES
;   colour-index value CC resolves to the right colour after VERA adds
;   palette_offset * 16. Sprites get the same treatment but reserve the
;   upper half of the palette so BG and sprite writes don't collide.
;
;   splay(X) = ((X & $10) << 2) | ((X & $0C) << 2) | (X & $03)
;     X = %000SNNCC  ->  VERA slot = %0SNN00CC
;
;   NES slot $00..$03 -> VERA $00..$03  (bg palette 0)
;   NES slot $04..$07 -> VERA $10..$13  (bg palette 1)
;   NES slot $08..$0B -> VERA $20..$23  (bg palette 2)
;   NES slot $0C..$0F -> VERA $30..$33  (bg palette 3)
;   NES slot $10..$13 -> VERA $40..$43  (sprite palette 0)
;   NES slot $14..$17 -> VERA $50..$53  (sprite palette 1)
;   NES slot $18..$1B -> VERA $60..$63  (sprite palette 2)
;   NES slot $1C..$1F -> VERA $70..$73  (sprite palette 3)
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

.segment "BSS"

pal_splay_lo: .res 1                    ; scratch for splay() colour-bits half
pal_splay_hi: .res 1                    ; scratch for splay() BG/sprite bit

.segment "CODE"

.proc HAL_PalettePush
    phx                                 ; save caller's X (palette slot)
    phy                                 ; save caller's Y
    pha                                 ; save caller's A (NES colour)

    ; --- splay NES slot X (%000SNNCC) -> VERA slot (%0SNN00CC), then *2 -----
    ; S = bit 4 (0 = BG, 1 = sprite); NN = bits 3:2 (attribute group 0..3);
    ; CC = bits 1:0 (colour within group). The mapping puts BG groups 0..3
    ; at VERA slot bases $00/$10/$20/$30 and sprite groups 0..3 at
    ; $40/$50/$60/$70, so each VERA 16-slot slice holds one NES group's
    ; four colours at offsets 0..3. Without propagating S, sprite palette
    ; writes would collide with the BG slots.
    txa
    and #$03                            ; A = %00000CC (low 2 bits)
    sta pal_splay_lo
    txa
    and #$10                            ; A = %000S0000 (BG/sprite flag)
    asl
    asl                                 ; A = %0S000000 (into bit 6)
    sta pal_splay_hi
    txa
    and #$0C                            ; A = %0000NN00
    asl
    asl                                 ; A = %00NN0000
    ora pal_splay_hi                    ; A = %0SNN0000
    ora pal_splay_lo                    ; A = %0SNN00CC  (splayed slot)
    asl                                 ; A = splayed slot * 2 (VERA byte addr)
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
