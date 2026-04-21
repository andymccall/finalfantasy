DrawPalette:
    LDA $2002       ; Reset PPU toggle
    LDA #$3F        ; set PPU Address to $3F00 (start of palettes)
    STA $2006
    LDA #$00
    STA $2006
    LDX #$00        ; set X to zero (our source index)
    JMP _DrawPalette_Norm   ; and copy the normal palette
_DrawPalette_Norm:
    LDA cur_pal, X     ; get normal palette
    STA $2007          ;  and draw it
    INX
    CPX #$20           ; loop until $20 colors have been drawn (full palette)
    BCC _DrawPalette_Norm

    LDA $2002          ; once done, do the weird thing NES games do
    LDA #$3F           ;  reset PPU address to start of palettes ($3F00)
    STA $2006          ;  and then to $0000.  Most I can figure is that they do this
    LDA #$00           ;  to avoid a weird color from being displayed when the PPU is off
    STA $2006
    STA $2006
    STA $2006
    RTS
