IntroStory_Joy:
    LDA #0                ; reset the respond rate to zero
    STA a:respondrate     ;  (why do this here?  Very out of place)

    JSR UpdateJoy         ; Update joypad data
    LDA joy
    AND #BTN_START        ; see if start was pressed
    BNE :+                ;  if not, just exit
      RTS
:   JMP GameStart_L       ; if it was pressed, restart game (brings up title screen)
