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


DoNameInput:
    LDA #$00                ; Turn off the PPU (for drawing)
    STA $2001

    STA menustall           ; zero a bunch of misc vars being used here
    STA joy_a
    STA joy_b
    STA joy
    STA joy_prevdir

    STA cursor              ; letter of the name we're inputting (0-3)
    STA namecurs_x          ; X position of letter selection cursor (0-9)
    STA namecurs_y          ; Y position (0-6)

    ; Some local temp vars
                @cursoradd      = name_cursoradd
                @selectedtile   = name_selectedtile

    JSR ClearNT
    JSR DrawNameInputScreen

    LDX char_index          ; wipe this character's name
    LDA #$FF
    STA ptygen_name, X
    STA ptygen_name+1, X
    STA ptygen_name+2, X
    STA ptygen_name+3, X

    JSR TurnMenuScreenOn_ClearOAM   ; now that everything is drawn, turn the screen on

    LDA #$01                ; Set menustall, as future drawing will
    STA menustall           ;  be with the PPU on

  @MainLoop:
    JSR CharName_Frame      ; Do a frame & get input

    LDA joy_a
    BNE @A_Pressed          ; Check if A or B pressed
    LDA joy_b
    BNE @B_Pressed

    LDA joy                 ; Otherwise see if D-pad state has changed
    AND #$0F
    CMP joy_prevdir
    BEQ @MainLoop           ; no change?  Jump back
    STA joy_prevdir

       ; D-pad state has changed, see what it changed to
    CMP #$00
    BEQ @MainLoop           ; if released, do nothing and loop

    CMP #$04
    BCC @Left_Or_Right      ; if < 4, L or R pressed

    CMP #$08                ; otherwise, if == 8, Up pressed
    BNE @Down               ; otherwise, if != 8, Down pressed

  @Up:
    DEC namecurs_y          ; DEC cursor Y position
    BPL @MainLoop
    LDA #$06                ; wrap 0->6
    STA namecurs_y
    JMP @MainLoop

  @Down:
    INC namecurs_y          ; INC cursor Y position
    LDA namecurs_y
    CMP #$07                ; wrap 6->0
    BCC @MainLoop
    LDA #$00
    STA namecurs_y
    JMP @MainLoop

  @Left_Or_Right:
    CMP #$02                ; if D-pad state == 2, Left pressed
    BNE @Right              ; else, Right pressed

  @Left:
    DEC namecurs_x          ; DEC cursor X position
    BPL @MainLoop
    LDA #$09                ; wrap 0->9
    STA namecurs_x
    JMP @MainLoop

  @Right:
    INC namecurs_x          ; INC cursor X position
    LDA namecurs_x
    CMP #$0A                ; wrap 9->0
    BCC @MainLoop
    LDA #$00
    STA namecurs_x
    JMP @MainLoop

    ;;;;;;;;;;;;;;;;;;
  @B_Pressed:
    LDA #$FF                ; if B was pressed, erase the previous tile
    STA @selectedtile       ;   by setting selectedtile to be a space

    LDA cursor              ; then by pre-emptively moving the cursor back
    SEC                     ;   so @SetTile will overwrite the prev char
    SBC #$01                ;   instead of the next one
    BMI :+                  ; (clip at 0)
      STA cursor

  : LDA #$00                ; set cursoradd to 0 so @SetTile doesn't change
    STA @cursoradd          ; the cursor
    STA joy_b               ; clear joy_b as well

    BEQ @SetTile            ; (always branches)

    ;;;;;;;;;;;;;;;;;;
  @A_Pressed:
    LDX namecurs_y                  ; when A is pressed, clear joy_a
    LDA #$00
    STA joy_a                       ; Then get the tile they selected by first
    LDA lut_NameInputRowStart, X    ;  running the Y cursor through a row lut
    CLC
    ADC namecurs_x                  ; add X cursor
    ASL A                           ; and multiply by 2 -- since there are spaces between tiles
    TAX                             ; use that value as an index to the lut_NameInput
    BCC :+                          ; This will always branch, as C will always be clear
        LDA lut_NameInput+$100, X       ; I can only guess this was used in the Japanese version, where the NameInput table might have been bigger than
        JMP :++                         ; 256 bytes -- even though that seems very unlikely.

  : LDA lut_NameInput, X
  : STA @selectedtile               ; record selected tile
    LDA #$01
    STA @cursoradd                  ; set cursoradd to 1 to indicate we want @SetTile to move the cursor forward

    LDA cursor                      ; check current cursor position
    CMP #$04                        ;  If we've already input 4 letters for this name....
    BCS @Done                       ;  .. then we're done.  Branch ahead
                                    ; Otherwise, fall through to SetTile

  @SetTile:
    LDA cursor                  ; use cursor and char_index to access the appropriate
    CLC                         ;   letter in this character's name
    ADC char_index
    TAX
    LDA @selectedtile
    STA ptygen_name, X          ; and write the selected tile

    JSR NameInput_DrawName      ; Redraw the name as it appears on-screen

    LDA cursor                  ; Then add to our cursor
    CLC
    ADC @cursoradd
    BPL :+                      ; clipping at 0 (if subtracting -- although this never happens)
      LDA #$00
  : STA cursor

    JMP @MainLoop               ; And keep going!

  @Done:
    CLC                 ; CLC to indicate name was successfully input
    RTS


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


CharName_Frame:
    JSR ClearOAM           ; wipe OAM then draw the cursor
    JSR CharName_DrawCursor

    JSR WaitForVBlank_L    ; VBlank and DMA
    LDA #>oam
    STA $4014

    LDA soft2000           ; reset the scroll to zero.
    STA $2000
    LDA #0
    STA $2005
    STA $2005

    LDA #BANK_THIS         ; keep playing music
    STA cur_bank
    JSR CallMusicPlay

      ; then update joy by running seamlessly into PtyGen_Joy
    JMP PtyGen_Joy


CharName_DrawCursor:
    LDA namecurs_x      ; X position = (cursx * 16) + $20
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #$20
    STA spr_x

    LDA namecurs_y      ; Y position = (cursy * 16) + $50
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #$50
    STA spr_y

    JMP DrawCursor


NameInput_DrawName:
            @buf  = name_buf     ; local - buffer to hold the name for printing

    LDX char_index          ; copy the character's name to our temp @buf
    LDA ptygen_name, X
    STA @buf
    LDA ptygen_name+1, X
    STA @buf+1
    LDA ptygen_name+2, X
    STA @buf+2
    LDA ptygen_name+3, X
    STA @buf+3              ; The code assumes @buf+4 is 0

    LDA #>@buf              ; Set the text pointer
    STA text_ptr+1
    LDA #<@buf
    STA text_ptr

    LDA #BANK_THIS          ; set cur/ret banks
    STA cur_bank
    STA ret_bank

    LDA #$0E                ; set X/Y positions for the name to be printed
    STA dest_x
    LDA #$04
    STA dest_y

    LDA #$01                ; drawing while PPU is on, so set menustall
    STA menustall

    JMP DrawComplexString   ; Then draw the name and exit!


DrawNameInputScreen:
    LDA $2002               ; clear PPU toggle

    LDA #>$23C0             ; set PPU addr to the attribute table
    STA $2006
    LDA #<$23C0
    STA $2006

    LDA #$00                ; set $10 bytes of the attribute table to use palette 0
    LDX #$10                ;  $10 bytes = 8 rows of tiles (32 pixels)
    : STA $2007             ; This makes the top box the orangish color instead of the normal blue
      DEX
      BNE :-

    LDA #0
    STA menustall           ; no menustall (PPU is off at this point)

    LDA #$04                ; Draw the big box containing input
    STA box_x
    LDA #$08
    STA box_y
    LDA #$17
    STA box_wd
    LDA #$14
    STA box_ht
    JSR DrawBox

    LDA #$0D                ; Draw the small top box containing the player's name
    STA box_x
    LDA #$02
    STA box_y
    LDA #$06
    STA box_wd
    LDA #$04
    STA box_ht
    JSR DrawBox

    LDA #<lut_NameInput     ; Print the NameInput lut as a string.  This will fill
    STA text_ptr            ;  the bottom box with the characters the user can select.
    LDA #>lut_NameInput
    STA text_ptr+1
    LDA #$06
    STA dest_x
    LDA #$0A
    STA dest_y
    LDA #BANK_THIS
    STA cur_bank
    STA ret_bank
    JMP DrawComplexString


lut_NameInputRowStart:
  .BYTE  0, 10, 20, 30, 40, 50, 60

lut_NameInput:
  .BYTE $8A, $FF, $8B, $FF, $8C, $FF, $8D, $FF, $8E, $FF, $8F, $FF, $90, $FF, $91, $FF, $92, $FF, $93, $01  ; A - J
  .BYTE $94, $FF, $95, $FF, $96, $FF, $97, $FF, $98, $FF, $99, $FF, $9A, $FF, $9B, $FF, $9C, $FF, $9D, $01  ; K - T
  .BYTE $9E, $FF, $9F, $FF, $A0, $FF, $A1, $FF, $A2, $FF, $A3, $FF, $BE, $FF, $BF, $FF, $C0, $FF, $FF, $01  ; U - Z ; , . <space>
  .BYTE $80, $FF, $81, $FF, $82, $FF, $83, $FF, $84, $FF, $85, $FF, $86, $FF, $87, $FF, $88, $FF, $89, $01  ; 0 - 9
  .BYTE $A4, $FF, $A5, $FF, $A6, $FF, $A7, $FF, $A8, $FF, $A9, $FF, $AA, $FF, $AB, $FF, $AC, $FF, $AD, $01  ; a - j
  .BYTE $AE, $FF, $AF, $FF, $B0, $FF, $B1, $FF, $B2, $FF, $B3, $FF, $B4, $FF, $B5, $FF, $B6, $FF, $B7, $01  ; k - t
  .BYTE $B8, $FF, $B9, $FF, $BA, $FF, $BB, $FF, $BC, $FF, $BD, $FF, $C2, $FF, $C3, $FF, $C4, $FF, $C5, $01  ; u - z - .. ! ?
  .BYTE $01
  .BYTE $FF, $FF, $FF, $9C, $8E, $95, $8E, $8C, $9D, $FF, $FF, $97, $8A, $96, $8E, $00                      ;   SELECT  NAME


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
