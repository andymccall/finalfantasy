;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Menu Conditional Stall   [$E12E :: 0x3E13E]
;;
;;    This will conditionally stall (wait) a frame for some menu routines.
;;   For example, if a box is to draw more slowly (one row drawn per frame)
;;   This is important and should be done when you attempt to draw when the PPU is on
;;   because it ensures that drawing will occur in VBlank
;;
;;  IN:  menustall = the flag to indicate whether or not to stall (nonzero = stall)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MenuCondStall:
    LDA menustall          ; check stall flag
    BEQ @Exit              ; if zero, we're not to stall, so just exit

      LDA soft2000         ;  we're stalling... so reset the scroll
      STA $2000
      LDA #0
      STA $2005            ;  scroll inside menus is always 0
      STA $2005

      JSR CallMusicPlay    ;  Keep the music playing
      JSR WaitForVBlank_L  ; then wait a frame

@Exit:
    RTS
