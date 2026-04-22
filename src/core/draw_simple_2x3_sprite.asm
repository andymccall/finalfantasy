; Verbatim extract: DrawSimple2x3Sprite (bank_0F.asm:10451-10506).
; lutClassBatSprPalette (bank_0F.asm:10537-10539) lives in a separate
; file so the shim can drop it into RODATA.
;
; DrawSimple2x3Sprite emits six NES OAM slots (24 bytes) starting at
; oam[sprindex] for a 2x3 class-portrait sprite. Used by PtyGen_DrawChars
; to draw each of the four party characters.
;
; IN:  tmp         = tile ID to start drawing from
;      tmp+1       = attributes (palette) for all tiles of this sprite
;      spr_x,spr_y = coords to draw sprite

DrawSimple2x3Sprite:
    LDX sprindex       ; put sprite index in X

    LDA spr_x          ; get X coord
    STA oam+$03, X     ;  write to UL, ML, and DL sprites
    STA oam+$0B, X
    STA oam+$13, X
    CLC
    ADC #$08           ; add 8 to X coord
    STA oam+$07, X     ;  write to UR, MR, and DR sprites
    STA oam+$0F, X
    STA oam+$17, X

    LDA spr_y          ; get Y coord
    STA oam+$00, X     ; write to UL, UR sprites
    STA oam+$04, X
    CLC
    ADC #$08           ; add 8
    STA oam+$08, X     ; write to ML, MR sprites
    STA oam+$0C, X
    CLC
    ADC #$08           ; add another 8
    STA oam+$10, X     ; write to DL, DR sprites
    STA oam+$14, X

    LDA tmp            ; get the tile ID to draw
    STA oam+$01, X     ; draw UL tile
    CLC
    ADC #$01           ; increment,
    STA oam+$05, X     ;  then draw UR
    CLC
    ADC #$01           ; inc again
    STA oam+$09, X     ;  then ML
    CLC
    ADC #$01
    STA oam+$0D, X     ;  then MR
    CLC
    ADC #$01
    STA oam+$11, X     ;  then DL
    CLC
    ADC #$01
    STA oam+$15, X     ;  then DR

    LDA tmp+1          ; get attribute byte
    STA oam+$02, X     ; and draw it to all 6 sprites
    STA oam+$06, X
    STA oam+$0A, X
    STA oam+$0E, X
    STA oam+$12, X
    STA oam+$16, X

    TXA                ; put sprite index in A
    CLC
    ADC #6*4           ; increment it by 6 sprites (4 bytes per sprite)
    STA sprindex       ; and write it back
    RTS
