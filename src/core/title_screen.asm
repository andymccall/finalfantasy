EnterTitleScreen:
    JSR TitleScreen_Copyright     ; Do prepwork, and draw the copyright text

   ;; The rest of the title screen consists of 3 boxes, each containing a single
   ;;  complex string.  The game here simply draws each of those boxes and 
   ;;  the contained string in order.

    LDA #BANK_THIS   ; set current bank (containing text)
    STA cur_bank     ;  and ret bank (to return to) to this bank
    STA ret_bank     ;  see DrawComplexString for why this is needed

    LDA #11          ; first box is at 11,10  with dims 10x4
    STA box_x        ;  and contains "Continue" text
    LDA #10
    STA box_y
    LDA #4
    STA box_ht
    LDA #10
    STA box_wd
      JSR DrawBox
    LDA #<lut_TitleText_Continue
    STA text_ptr
    LDA #>lut_TitleText_Continue
    STA text_ptr+1
    LDA #0
    STA menustall    ; disable menu stalling (PPU is off)
     JSR DrawComplexString

    LDA #15          ; next box is same X pos and same dims, but at Y=15
    STA box_y        ;  and contains text "New Game"
      JSR DrawBox
    LDA #<lut_TitleText_NewGame
    STA text_ptr
    LDA #>lut_TitleText_NewGame
    STA text_ptr+1
      JSR DrawComplexString

    LDA #20          ; last box is moved left and down a bit (8,20)
    STA box_y        ;  and is a little fatter (wd=16)
    LDA #8           ; this box contains "Respond Rate"
    STA box_x
    LDA #16
    STA box_wd
      JSR DrawBox
    LDA #<lut_TitleText_RespondRate
    STA text_ptr
    LDA #>lut_TitleText_RespondRate
    STA text_ptr+1
      JSR DrawComplexString

    LDA #$0F                ; enable APU (isn't necessary, as the music driver
    STA $4015               ;   will do this automatically)
    JSR TurnMenuScreenOn_ClearOAM  ; turn on the screen and clear OAM
                                   ;  and continue on to the logic loop


  ;; This is the main logic loop for the Title screen.

  @Loop:
    JSR ClearOAM            ; Clear OAM

    LDX cursor              ; Draw the cursor sprite using a fixed X coord of $48
    LDA #$48                ;  and using the current cursor position to get the Y coord
    STA spr_x               ;  from a LUT
    LDA lut_TitleCursor_Y, X
    STA spr_y
    JSR DrawCursor

    JSR WaitForVBlank_L     ; Wait for VBlank
    LDA #>oam               ;  and do Sprite DMA
    STA $4014               ; Then redraw the respond rate
    JSR TitleScreen_DrawRespondRate

    JSR UpdateJoy           ; update joypad data
    LDA #BANK_THIS          ;  set cur_bank to this bank (for CallMusicPlay)
    STA cur_bank

    JSR TitleScreen_Music   ; call music playback, AND get joy_a (weird little routine)
    ORA joy_start           ; OR with joy_start to see if either A or Start pressed
    BNE @OptionChosen       ; if either pressed, a menu option was chosen.

    LDA joy                 ; otherwise mask out the directional buttons from the joy data
    AND #$0F
    CMP joy_prevdir         ; see if the state of any directional buttons changed
    BEQ @Loop               ; if not, keep looping

    STA joy_prevdir         ; otherwise, record changes to direction
    CMP #0                  ;  see if the change was buttons being pressed or lifted
    BEQ @Loop               ;  if buttons were being lifted, do nothing (keep looping)

    CMP #$04                ; see if they pressed up/down or left/right
    BCC @LeftRight

  @UpDown:
    LDA cursor              ; if up/down, simply toggle the cursor between New Game
    EOR #1                  ;  and continue
    STA cursor
    JSR PlaySFX_MenuSel     ; play a little sound effect (the sel sfx, not the move sfx like you
    JMP @Loop               ;  may expect).  Then resume the loop.

  @LeftRight:
    CMP #RIGHT              ; did they press Right?
    BNE @Left               ;  if not, they must've pressed Left
    LDA #1                  ; add +1 to rate if right
    BNE :+
       @Left:
         LDA #-1            ; or -1 if left
:   CLC
    ADC respondrate         ; add/subtract 1 from respond rate
    AND #7                  ; mask to wrap it from 0<->7
    STA respondrate

    JSR PlaySFX_MenuMove    ; play the move sound effect, and continue looping!
    JMP @Loop

@OptionChosen:              ; Jumps here when the player presses A or Start (selected an option)
    LDA cursor              ;  this CMP will set C if they selected option 1 (New Game)
    CMP #1                  ;  and will clear C if they selected option 0 (Continue)
    RTS                     ;  then exit!

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  IntroTitlePrepare  [$A219 :: 0x3A229]
;;
;;    Does various preparation things for the intro story and title screen.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IntroTitlePrepare:
    LDA #$08               ; set soft2000 so that sprites use right pattern
    STA soft2000           ;   table while BG uses left
    LDA #0
    STA $2001              ; turn off the PPU

    JSR LoadMenuCHRPal     ; Load necessary CHR and palettes

    LDA #$41
    STA music_track        ; Start up the crystal theme music

    LDA #0
    STA joy_a              ; clear A, B, Start button catchers
    STA joy_b
    STA joy_start
    STA cursor
    STA joy_prevdir        ; as well as resetting the cursor and previous joy direction

    JMP ClearNT            ; then wipe the nametable clean and exit


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  TitleScreen_DrawRespondRate  [$A238 :: 0x3A248]
;;
;;    Draws the respond rate on the title screen.  Called every frame
;;  because the respond rate can change via the user.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

TitleScreen_DrawRespondRate:
    LDA #>$22D6        ; Respond rate is drawn at address $22D6
    STA $2006
    LDA #<$22D6
    STA $2006

    LDA respondrate    ; get the current respond rate (which is zero based)
    CLC                ;  add $80+1 to it.  $80 to convert it to the coresponding tile
    ADC #$80+1         ;  for the desired digit to print, and +1 to convert it from zero
    STA $2007          ;  based to 1 based (so it's printed as 1-8 instead of 0-7)

    LDA #0             ; then reset the scroll.
    STA $2005
    STA $2005
    RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Pointerless strings for the title screen  [$A253 :: 0x3A263]
;;
;;    These are complex strings drawn onto the title screen.  They
;;  have no pointer table -- instead the drawing code points to the
;;  strings directly (hence why each string is labelled)

lut_TitleText_Continue:
  .BYTE $8C,$98,$97,$9D,$92,$97,$9E,$8E,$00

lut_TitleText_NewGame:
  .BYTE $97,$8E,$A0,$FF,$90,$8A,$96,$8E,$00

lut_TitleText_RespondRate:
  .BYTE $9B,$8E,$9C,$99,$98,$97,$8D,$FF,$9B,$8A,$9D,$8E,$00


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Small LUT for the Y position of the title screen cursor  [$A272 :: 0x3A282]

lut_TitleCursor_Y:
  .BYTE $58   ; to point at "Continue"
  .BYTE $80   ; to point at "New Game"
