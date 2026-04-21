TitleScreen_Copyright:
    JSR IntroTitlePrepare    ; clear NT, start music, etc
    BIT $2002                ;  reset PPU toggle

    LDX #0
    JSR @DrawString         ; JSR to the @DrawString to draw the first one
                            ;  then just let code flow into it to draw a second one (2 strings total)

  @DrawString:
    LDA @lut_Copyright+1, X ; get the Target PPU address from the LUT
    STA $2006
    LDA @lut_Copyright, X
    STA $2006
    INX                     ; move X past the address we just read
    INX

  @Loop:
    LDA @lut_Copyright, X   ; get the next character in the string
    BEQ @Exit               ;  if it's zero, exit (null terminator
    STA $2007               ; otherwise, draw the character
    INX                     ; INX to move to next character
    BNE @Loop               ; and keep looping (always branches)

  @Exit:
    INX                     ; INX to move X past the null terminator we just read
    RTS

 ;; LUT for the copyright text.  Simply a 2-byte target PPU address, followed by a
 ;;  null terminated string.  Two strings total.

@lut_Copyright:
  .WORD $2328
  .BYTE $8C,$FF,$81,$89,$88,$87,$FF,$9C,$9A,$9E,$8A,$9B,$8E,$FF,$FF,$00  ; "C 1987 SQUARE  "
  .WORD $2348
  .BYTE $8C,$FF,$81,$89,$89,$80,$FF,$97,$92,$97,$9D,$8E,$97,$8D,$98,$00  ; "C 1990 NINTENDO"
