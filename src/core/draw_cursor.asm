DrawCursor:
    LDA #<lutCursor2x2SpriteTable   ; load up the pointer to the cursor sprite
    STA tmp                         ; arrangement
    LDA #>lutCursor2x2SpriteTable   ; and store that pointer in (tmp)
    STA tmp+1
    LDA #$F0                        ; cursor tiles start at $F0
    STA tmp+2
    JMP Draw2x2Sprite               ; draw cursor as a 2x2 sprite, and exit
