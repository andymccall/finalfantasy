NewGamePartyGeneration:
    LDA #$00                ; turn off the PPU
    STA $2001
    LDA #$0F                ; turn ON the audio (it should already be on, though
    STA $4015               ;  so this is kind of pointless)

    JSR LoadNewGameCHRPal   ; Load up all the CHR and palettes necessary for the New Game menus

    LDA cur_pal+$D          ; Do some palette finagling
    STA cur_pal+$1          ;  Though... these palettes are never drawn, so this seems entirely pointless
    LDA cur_pal+$F
    STA cur_pal+$3
    LDA #$16
    STA cur_pal+$2

    LDX #$3F                ; Initialize the ptygen buffer!
    : LDA lut_PtyGenBuf, X  ;  all $40 bytes!  ($10 bytes per character)
      STA ptygen, X
      DEX
      BPL :-

  @Char_0:                      ; To Character generation for each of the 4 characters
    LDA #$00                    ;   branching back to the previous char if the user
    STA char_index              ;   cancelled by pressing B
    JSR DoPartyGen_OnCharacter
    BCS @Char_0
  @Char_1:
    LDA #$10
    STA char_index
    JSR DoPartyGen_OnCharacter
    BCS @Char_0
  @Char_2:
    LDA #$20
    STA char_index
    JSR DoPartyGen_OnCharacter
    BCS @Char_1
  @Char_3:
    LDA #$30
    STA char_index
    JSR DoPartyGen_OnCharacter
    BCS @Char_2

    RTS


DoPartyGen_OnCharacter:
    JSR PtyGen_DrawScreen           ; Draw the Party generation screen

    ; Then enter the main logic loop
  @MainLoop:
      JSR PtyGen_Frame              ; Do a frame and update joypad input
      LDA joy_a
      BNE DoNameInput               ; if A was pressed, do name input
      LDA joy_b
      BEQ :+
        ; if B pressed -- just SEC and exit
        SEC
        RTS

      ; Code reaches here if A/B were not pressed
    : LDA joy
      AND #$0F
      CMP joy_prevdir
      BEQ @MainLoop             ; if there was no change in directional input, loop to another frame

      STA joy_prevdir           ; otherwise, record new directional input as prevdir
      CMP #$00                  ; if directional input released (rather than pressed)
      BEQ @MainLoop             ;   loop to another frame.

     ; Otherwise, if any direction was pressed:
      LDX char_index
      CLC
      LDA ptygen_class, X       ; Add 1 to the class ID of the current character.
      ADC #1
      CMP #6
      BCC :+
        LDA #0                  ; wrap 5->0
    : STA ptygen_class, X

      LDA #$01                  ; set menustall (drawing while PPU is on)
      STA menustall
      LDX char_index            ; then update the on-screen class name
      JSR PtyGen_DrawOneText
      JMP @MainLoop


PtyGen_Frame:
    JSR ClearOAM           ; wipe OAM then draw all sprites
    JSR PtyGen_DrawChars
    JSR PtyGen_DrawCursor

    JSR WaitForVBlank_L    ; VBlank and DMA
    LDA #>oam
    STA $4014

    LDA #BANK_THIS         ; then keep playing music
    STA cur_bank
    JSR CallMusicPlay

    JMP PtyGen_Joy         ; and update joy data!


PtyGen_Joy:
    LDA joy
    AND #$0F
    STA tmp+7            ; put old directional buttons in tmp+7 for now

    JSR UpdateJoy        ; then update joypad data

    LDA joy_a            ; if either A or B pressed...
    ORA joy_b
    BEQ :+
      JMP PlaySFX_MenuSel ; play the Selection SFX, and exit

:   LDA joy              ; otherwise, check new directional buttons
    AND #$0F
    BEQ @Exit            ; if none pressed, exit
    CMP tmp+7            ; if they match the old buttons (no new buttons pressed)
    BEQ @Exit            ;   exit
    JMP PlaySFX_MenuMove ; .. otherwise, play the Move sound effect
  @Exit:
    RTS


PtyGen_DrawCursor:
    LDX char_index          ; use the current index to get the cursor
    LDA ptygen_curs_x, X    ;  coords from the ptygen buffer.
    STA spr_x
    LDA ptygen_curs_y, X
    STA spr_y
    JMP DrawCursor          ; and draw the cursor there


PtyGen_DrawScreen:
    LDA #$08
    STA soft2000          ; set BG/Spr pattern table assignments
    LDA #0
    STA $2001             ; turn off PPU
    STA joy_a             ;  clear various joypad catchers
    STA joy_b
    STA joy
    STA joy_prevdir

    JSR ClearNT             ; wipe the screen clean
    JSR PtyGen_DrawBoxes    ;  draw the boxes
    JSR PtyGen_DrawText     ;  and the text in those boxes
    JMP TurnMenuScreenOn_ClearOAM   ; then clear OAM and turn the PPU On


PtyGen_DrawBoxes:
    LDA #0
    STA tmp+15       ; reset loop counter to zero

  @Loop:
      JSR @Box       ; then loop 4 times, each time, drawing the next
      LDA tmp+15     ; character's box
      CLC
      ADC #$10       ; incrementing by $10 each time (indexes ptygen buffer)
      STA tmp+15
      CMP #$40
      BCC @Loop
    RTS

 @Box:
    LDX tmp+15           ; get ptygen index in X

    LDA ptygen_box_x, X  ; get X,Y coords from ptygen buffer
    STA box_x
    LDA ptygen_box_y, X
    STA box_y

    LDA #10              ; fixed width/height of 10
    STA box_wd
    STA box_ht

    LDA #0
    STA menustall        ; disable menustalling (PPU is off)
    JMP DrawBox          ;  draw the box, and exit


PtyGen_DrawText:
    LDA #0             ; start loop counter at zero
  @MainLoop:
     PHA                ; push loop counter to back it up
     JSR @DrawOne       ; draw one character's strings
     PLA                ;  pull loop counter
     CLC                ; and increase it to point to next character's data
     ADC #$10           ;  ($10 bytes per char in 'ptygen')
     CMP #$40
     BCC @MainLoop      ;  loop until all 4 chars drawn
    RTS

  @DrawOne:
    TAX                 ; put the ptygen index in X for upcoming routine

      ; no JMP or RTS -- code flows seamlessly into PtyGen_DrawOneText


PtyGen_DrawOneText:
    LDA ptygen_class_x, X   ; get X,Y coords where we're going to place
    STA dest_x              ;  the class name
    LDA ptygen_class_y, X
    STA dest_y

    LDA ptygen_class, X     ; get the selected class
    CLC
    ADC #$F0                ; add $F0 to select the class' "item name"
    STA format_buf-1        ;  store that as 2nd byte in format string
    LDA #$02                ; first byte in string is $02 -- the control code to
    STA format_buf-2        ;  print an item name

    LDA #<(format_buf-2)    ; set the text pointer to point to the start of the 2-byte
    STA text_ptr            ;  string we just constructed
    LDA #>(format_buf-2)
    STA text_ptr+1

    LDA #BANK_THIS          ; set cur and ret banks (see DrawComplexString for why)
    STA cur_bank
    STA ret_bank

    TXA                     ; back up our index (DrawComplexString will corrupt it)
    PHA
    JSR DrawComplexString   ; draw the string
    PLA
    TAX                     ; and restore our index

    LDA ptygen_name, X      ; next, copy over the 4-byte name of the character
    STA format_buf-4        ;  over to the format buffer
    LDA ptygen_name+1, X
    STA format_buf-3
    LDA ptygen_name+2, X
    STA format_buf-2
    LDA ptygen_name+3, X
    STA format_buf-1

    LDA ptygen_name_x, X    ; set destination coords appropriately
    STA dest_x
    LDA ptygen_name_y, X
    STA dest_y

    LDA #<(format_buf-4)    ; set pointer to start of 4-byte string
    STA text_ptr
    LDA #>(format_buf-4)
    STA text_ptr+1

    LDA #BANK_THIS          ; set banks again (not necessary as they haven't changed from above
    STA cur_bank            ;   but oh well)
    STA ret_bank

    JMP DrawComplexString   ; then draw another complex string -- and exit!


lut_PtyGenBuf:
  .BYTE $00,$00,$FF,$FF,$FF,$FF,$07,$0C,$05,$06,$40,$40,$04,$04,$30,$40
  .BYTE $01,$00,$FF,$FF,$FF,$FF,$15,$0C,$13,$06,$B0,$40,$12,$04,$A0,$40
  .BYTE $02,$00,$FF,$FF,$FF,$FF,$07,$18,$05,$12,$40,$A0,$04,$10,$30,$A0
  .BYTE $03,$00,$FF,$FF,$FF,$FF,$15,$18,$13,$12,$B0,$A0,$12,$10,$A0,$A0
