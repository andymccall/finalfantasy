IntroStory_MainLoop:
    LDA #<$23C0                ; start animating blocks from the start of the attribute
    STA intro_ataddr           ; table ($23C0)

  @Loop:
    JSR IntroStory_AnimateBlock  ; animate a block

    LDA intro_ataddr             ; then add 8 to animate the next block (8 bytes of
    CLC                          ;   attribute per block)
    ADC #8
    STA intro_ataddr

    CMP #<$23F8                  ; and keep looping until all except for the very last block
    BCC @Loop                    ;  have been animated

     ; once all blocks have been animated, the entire intro story is now visible
     ;  simply keep doing frames in an endless loop.  IntroStory_Frame, will double-RTS
     ;  if the user presses A or B, which will break out of this loop.  It will also
     ;  escape this routine altogether if the user presses start, so this infinite
     ;  loop isn't really all that infinite.  See IntroStory_Frame for details.

  @InfiniteLoop:
    JSR IntroStory_Frame
    JMP @InfiniteLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  IntroStory_AnimateBlock  [$A28C :: 0x3A29C]
;;
;;    Animates a "block" (8 bytes of attribute data, 2 rows of text) for
;;  the intro story.  Not to be confused with the below _AnimateRow routine,
;;  which animates a single row within a block.
;;
;;    This routine updates intro_atbyte, which in turn updates onscreen
;;  attributes so that different rows of text become animated.
;;
;;    Note this routine calls IntroStory_Frame directly.. and with a JMP no less!
;;  IntroStory_Frame can double-RTS (see that routine for details), which means
;;  it is theoretically possible for the intro story to be prematurely exited
;;  if you happen to press A or B at *exactly* the wrong time (there's only a very
;;  slim 1 frame window where it could happen -- but still).  This could be considered
;;  BUGGED -- with the appropriate fix being to change the JMP IntroStory_Frame into
;;  JSR IntroStory_Frame, RTS.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IntroStory_AnimateBlock:
    LDA #%01011010          ; set desired attribute byte.  This sets the top row of the block to use
    STA intro_atbyte        ;  palette %10 (the animating palette), and the bottom row to use
                            ;  palette %01 (faded-out / invisible palette)
    JSR IntroStory_AnimateRow  ; animate the top row of text

    LDA intro_ataddr        ; Check to see if this is the very last block ($23F8).  If it is, there's
    CMP #<$23F8             ;  no bottom row to animate -- the last block is really only half a block
    BEQ @Done               ; so if last block .. just exit now
                            ; However since this routine never gets called for the last block -- this
                            ;  is pointless

    LDA #%10101111             ; otherwise, set attribute so that top row uses %11 (fully faded in)
    STA intro_atbyte           ;  and bottom row uses %10 (animating)
    JSR IntroStory_AnimateRow  ;  animate the bottom row

  @Done:
    LDA #%11111111          ; lastly, set attribute byte so that the entire block uses %11
    STA intro_atbyte        ;  this prevents the bottom row from animating further
    JMP IntroStory_Frame    ;  Do a frame to update the actual attribute tables, then exit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  IntroStory_AnimateRow  [$A2A7 :: 0x3A2B7]
;;
;;    Animates the palette to "fade in" a row of text.  It assumes the
;;  desired text is using the appropriate palette (palette 2:  $3F08-3F0B).
;;
;;    The palette animation simply alternates between the "main" color (grey), and
;;  another "sub" color that's one shade darker than it.  It switches between those colors
;;  every frame for 16 frames... then brightens the "main" color by one shade until it
;;  is fully white ($30).
;;
;;    The "main" color starts at the dark grey ($00), and increases in shade by adding
;;  $10 to it every frame.  The other color ("one shade darker") is simply the main color
;;  minus $10 -- unless the main color is $00, in which case the background color of $01 blue
;;  is used instead.
;;
;;    This produces the following pattern:
;;  00 01 00 01 ...
;;  10 00 10 00 ...
;;  20 10 20 10 ...
;;  30 20 30 20 ...
;;  -routine exits-
;;
;;    This routine calls IntroStory_Frame, which can double-RTS (see that routine for details)
;;  The result of a double-RTS here is that this routine exits mid-animation, which essentially
;;  makes the entire row fade in immediately.  This is why repeatedly pressing A or B during
;;  the intro story makes the text appear faster.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IntroStory_AnimateRow:
    LDA #$00
    STA intro_color        ; start the intro color at $00 grey

  @MainLoop:
    LDA intro_color        ; use the "main" intro color
    STA cur_pal + $B       ;   by copying it to the palette

  @SubLoop:
    JSR IntroStory_Frame   ; Do a frame
    INC framecounter       ; and update the frame counter

    LDA framecounter       ; see if we're on a 16th frame
    AND #$0F               ;  by masking out the low bits of the frame counter
    BNE @Alternate         ;  if not an even 16th frame, just alternate between main and sub colors

      LDA intro_color      ; ... if we are on an even 16th frame, brighten the main
      CLC                  ; color by adding $10 to it.
      ADC #$10
      STA intro_color
      CMP #$40             ; then check to see if we're done.  Done when the color was brightened
      BCC @MainLoop        ; from full white ($30) -- which would mean it's >= $40 after
      RTS                  ;  brightening.  If not done (< $40), continue loop.  Otherwise, exit

  @Alternate:
    LSR A                ; move the low bit of the frame counter into C to see if this is an even
    BCC @MainLoop        ;  or odd frame.  If even frame, use the main color next frame (@MainLoop)

    LDA cur_pal + $B     ; if an odd frame, get the previously used color (the main color)
    SEC                  ;  subtract $10 to make it one shade darker.
    SBC #$10
    BPL :+               ; if that caused it to wrap below 0
      LDA #$01           ;  use $01 blue instead
:   STA cur_pal + $B     ; and use this color (the sub color) next frame
    JMP @SubLoop         ; and continue looping

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  IntroStory_WriteAttr  [$A2DA :: 0x3A2EA]
;;
;;    Updates a row of attribute data for the intro story.  Writes
;;  8 bytes of attribute data to the given PPU address.
;;
;;  IN:  intro_ataddr = low byte of PPU address to write to
;;       intro_atbyte = attribute byte to write
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IntroStory_WriteAttr:
    LDA $2002            ; reset PPU toggle

    LDA #$23             ; set PPU addr to $23xx (where xx is intro_ataddr)
    STA $2006
    LDA intro_ataddr
    STA $2006

    LDX #$08
    LDA intro_atbyte     ; write intro_atbyte 8 times
  @Loop:
      STA $2007
      DEX
      BNE @Loop

    RTS                  ; then exit!


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  IntroStory_Frame  [$A2F2 :: 0x3A302]
;;
;;    Does a frame for the intro story.  It has a very strange way of returning
;;  control to the calling routine, though.
;;
;;    If A or B is pressed, it does a "double RTS" -- IE, not returning control
;;  to the the calling routine, but returning control to the routine that called
;;  the calling routine.
;;
;;    If Start is pressed, the routine doesn't exit at all, and instead, the game
;;  jumps back to GameStart (which brings up the title screen -- escaping the intro
;;  story).
;;
;;    If none of those buttons are pressed, the routine exits normally
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IntroStory_Frame:
    JSR WaitForVBlank_L        ; wait for VBlank
    JSR IntroStory_WriteAttr   ; then do the attribute updates
    JSR DrawPalette            ; and draw the animating palette

    LDA soft2000
    STA $2000
    LDA #0
    STA $2005
    STA $2005                  ; then reset the scroll to zero

    STA joy_a                  ; clear A and B button catchers
    STA joy_b

    LDA #BANK_THIS             ; set current bank (needed when calling CallMusicPlay from
    STA cur_bank               ;   a swappable bank)
    JSR CallMusicPlay          ; Then call music play to keep music playing!

    JSR IntroStory_Joy         ; update joypad

    LDA joy_a             ; check to see if either A
    ORA joy_b             ;  or B were pressed
    BNE :+                ; if not...
      RTS                 ; ... exit normally

:   PLA                   ; if either A or B pressed, PLA to drop the last
    PLA                   ;  return address, then exit (does a double-RTS)
    RTS
