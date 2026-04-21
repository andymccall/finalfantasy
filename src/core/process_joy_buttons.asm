ProcessJoyButtons:
    LDA joy         ; get joypad data
    AND #$03        ; check Left and Right button states
    BEQ :+          ; if either are pressed...
      LDX #$03      ;   X=$03, otherwise, X=$00
:   STX tmp+1       ; back that value up

    LDA joy         ; get joy data again
    AND #$0C        ; this time, check Up and Down buttons
    BEQ :+
      TXA           ; if either are pressed, OR previous value with $0C
      ORA #$0C      ;  tmp+1 is now a mask indicating which directional buttons we want to keep
      STA tmp+1     ;  directional buttons not included in the mask will be discarded

:   LDA joy         ; get joy data -- do some EOR magic
    EOR joy_ignore  ;  invert it with all the buttons to ignore.
    AND tmp+1       ;  mask out the directional buttons to keep
    EOR joy_ignore  ;  and re-invert, restoring ALL buttons *except* the directional we want to keep
    STA joy_ignore  ;  write back to ignore (so that these buttons will be ignored next time joy data is polled
    EOR joy         ; EOR again with current joy data.

   ; okay this requires a big explanation because it's insane.
   ; directional buttons (up/down/left/right) are treated seperately than other buttons (A/B/Select/Start)
   ;  The game creates a mask with those directional buttons so that the most recently pressed direction
   ;  is ignored, even after it's released.
   ;
   ; To illustrate this... imagine that joy buttons have 4 possible states:
   ;  lifted   (0 -> 0)
   ;  pressed  (0 -> 1)
   ;  held     (1 -> 1)
   ;  released (1 -> 0)
   ;
   ;   For directional buttons (U/D/L/R), the above code will produce the following results:
   ; lifted:   joy_ignore = 0      A = 0
   ; pressed:  joy_ignore = 1      A = 0
   ; held:     joy_ignore = 1      A = 0
   ; released: joy_ignore = 1      A = 0
   ;
   ;   For nondirectional buttons (A/B/Sel/Start), the above produces the following:
   ; lifted:   joy_ignore = 0      A = 0
   ; pressed:  joy_ignore = 0      A = 1
   ; held:     joy_ignore = 1      A = 0
   ; released: joy_ignore = 1      A = 1
   ;
   ;  Yes... it's very confusing.  But not a lot more I can do to explain it though  x_x
   ; Afterwards, A is the non-directioal buttons whose state has transitioned (either pressed or released)

    TAX            ; put transitioned buttons in X (temporary, to back them up)

    AND #$10        ; see if the Start button has transitioned
    BEQ @select     ;  if not... skip ahead to select button check
    LDA joy         ; get current joy
    AND #$10        ; see if start is being pressed (as opposed to released)
    BEQ :+          ;  if it is....
      INC joy_start ;   increment our joy_start var
:   LDA joy_ignore  ; then, toggle the ignore bit so that it will be ignored next time (if being pressed)
    EOR #$10        ;  or will no longer be ignored (if being released)
    STA joy_ignore  ;  the reason for the ignore is because you don't want a button to be pressed
                    ;  a million times as you hold it (like rapid-fire)

@select:
    TXA             ; restore the backed up transition byte
    AND #$20        ; and do all the same things... but with the select button
    BEQ @btn_b
    LDA joy
    AND #$20
    BEQ :+
      INC joy_select
:   LDA joy_ignore
    EOR #$20
    STA joy_ignore

@btn_b:
    TXA
    AND #$40
    BEQ @btn_a
    LDA joy
    AND #$40
    BEQ :+
      INC joy_b
:   LDA joy_ignore
    EOR #$40
    STA joy_ignore


@btn_a:
    TXA
    AND #$80
    BEQ @Exit
    LDA joy
    AND #$80
    BEQ :+
      INC joy_a
:   LDA joy_ignore
    EOR #$80
    STA joy_ignore

@Exit:
    RTS
