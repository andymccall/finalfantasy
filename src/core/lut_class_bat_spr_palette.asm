; Verbatim extract: lutClassBatSprPalette (bank_0F.asm:10537-10539).
;
; Attribute byte for each class's battle sprite. 01 = white/red palette
; (fighter etc), 00 = blue/brown palette (thief etc).

lutClassBatSprPalette:
    .BYTE $01,$00,$00,$01,$01,$00    ; unpromoted classes
    .BYTE $01,$01,$00,$01,$01,$00    ; promoted classes
