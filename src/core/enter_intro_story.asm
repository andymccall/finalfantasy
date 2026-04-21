EnterIntroStory:
    JSR IntroTitlePrepare      ; load CHR, start music, other prepwork

    LDA $2002           ; reset PPU toggle and set PPU address to $2000
    LDA #>$2000         ;   (start of nametable)
    STA $2006
    LDA #<$2000
    STA $2006

    LDX #($03C0 / 4)    ; Fill the nametable with tile $FF (blank space)
    LDA #$FF            ;  this loop does a full $03C0 writes
  @NTLoop:
      STA $2007
      STA $2007
      STA $2007
      STA $2007
      DEX
      BNE @NTLoop

    LDX #$40            ; Next, fill the attribute table so that all tiles use
    LDA #%01010101      ;  palette %01.  This palette will be used for fully
  @AttrLoop:            ;  faded-out text (ie:  text using this palette is
      STA $2007         ;  invisible)
      DEX
      BNE @AttrLoop

    LDA #$01            ; fill palettes %01 (faded out) and %10 (animating) with 
    STA cur_pal + $6    ;  $01 blue.
    STA cur_pal + $7
    STA cur_pal + $A
    STA cur_pal + $B

    ; now that the NT is cleared and palettes are prepped -- time to draw
    ;  the intro story text.  This is accomplished by drawing a single
    ;  Complex String

    LDA #<lut_IntroStoryText  ; load up the pointer to the intro story text
    STA text_ptr
    LDA #>lut_IntroStoryText
    STA text_ptr+1

    LDA #0               ; disable menu stalling (PPU is off)
    STA menustall

    LDA #BANK_INTROTEXT  ; select bank containing text
    STA cur_bank
    LDA #BANK_THIS       ; and record this bank to return to
    STA ret_bank

    LDA #3               ; draw text at coords 1,3
    STA dest_y
    LDA #1
    STA dest_x

    JSR DrawComplexString   ; draw intro story as a complex string!

    JSR TurnMenuScreenOn_ClearOAM  ; turn on the PPU
    JSR IntroStory_MainLoop        ; and run the main loop of the intro story

    LDA #0              ; once the intro story exits, shut off the PPU
    STA $4015
    STA respondrate     ; reset the respond rate
    RTS                 ;  and exit
