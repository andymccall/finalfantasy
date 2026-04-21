Draw2x2Sprite:
    LDY #0           ; zero Y (will be our index to the given buffer
    LDX sprindex     ; get the sprite index in X

    LDA spr_y        ; load up desired Y coord
    STA oam+$0, X    ;  set UL and UR sprite Y coords
    STA oam+$8, X
    CLC
    ADC #$08         ; add 8 to Y coord
    STA oam+$4, X    ;  set DL and DR Y coords
    STA oam+$C, X

    LDA spr_x        ; load up X coord
    STA oam+$3, X    ;  set UL and DL X coords
    STA oam+$7, X
    CLC
    ADC #$08         ; add 8
    STA oam+$B, X    ;  and set UR and DR X coords
    STA oam+$F, X

    LDA (tmp), Y     ; get UL tile from the buffer
    INY              ;  inc our buffer index
    CLC
    ADC tmp+2        ; add the tile offset to the tile ID
    STA oam+$1, X    ; write it to oam
    LDA (tmp), Y     ; get UL attribute byte from buffer
    INY              ;  inc buffer index
    STA oam+$2, X    ; write to oam

    LDA (tmp), Y     ; repeat this process again.. but for the DL sprite
    INY
    CLC
    ADC tmp+2
    STA oam+$5, X
    LDA (tmp), Y
    INY
    STA oam+$6, X

    LDA (tmp), Y     ; and again for the UR sprite
    INY
    CLC
    ADC tmp+2
    STA oam+$9, X
    LDA (tmp), Y
    INY
    STA oam+$A, X

    LDA (tmp), Y     ; and lastly for the DR sprite
    INY
    CLC
    ADC tmp+2
    STA oam+$D, X
    LDA (tmp), Y
    STA oam+$E, X

    LDA sprindex     ; now that all 4 sprites have been fully loaded
    CLC              ;  increment the sprite index by 16 (4 sprites)
    ADC #16
    STA sprindex
    RTS              ; and exit!
