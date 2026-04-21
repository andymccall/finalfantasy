; ---------------------------------------------------------------------------
; joy.asm - Commander X16 joypad HAL.
; ---------------------------------------------------------------------------
; Assembles an NES-style 8-bit button mask from the PS/2 keyboard. The
; X16 KERNAL exposes a non-blocking keystroke queue via GETIN ($FFE4):
; it returns PETSCII in A, or 0 if no key is waiting. We drain everything
; currently in the queue into a sticky mask that HAL_PollJoy returns.
;
; The NES bit layout (contract in hal.inc / ReadJoypadData in bank_0F):
;   bit 0 Right   bit 4 Start
;   bit 1 Left    bit 5 Select
;   bit 2 Down    bit 6 B
;   bit 3 Up      bit 7 A
;
; Key mapping:
;   Arrow keys -> Up/Down/Left/Right  (PS/2 translated by KERNAL)
;   Return     -> Start
;   Space      -> Select
;   X          -> A
;   Z          -> B
;
; GETIN returns arrow keys as the PETSCII cursor codes $11 (down),
; $91 (up), $1D (right), $9D (left). RETURN is $0D, SPACE is $20.
;
; Because GETIN is edge-driven (you only see a key once per press, no
; auto-repeat signal), ProcessJoyButtons's press-transition logic would
; never see a "held" state. To keep the game's ignore/held model happy,
; HAL_PollJoy latches bits on receipt and clears them only when the key
; is seen again as a release -- but PS/2 GETIN doesn't report releases.
; So as a practical first cut, bits persist for one poll: we return the
; mask assembled since the last call, then clear it. ProcessJoyButtons
; sees a press transition each poll the key is tapped, which is exactly
; the title-screen loop's expectation for Up/Down/A/Start.
; ---------------------------------------------------------------------------

.export HAL_PollJoy

KERNAL_GETIN = $FFE4

PETSCII_RETURN = $0D
PETSCII_SPACE  = $20
PETSCII_DOWN   = $11
PETSCII_UP     = $91
PETSCII_RIGHT  = $1D
PETSCII_LEFT   = $9D

NES_RIGHT  = $01
NES_LEFT   = $02
NES_DOWN   = $04
NES_UP     = $08
NES_START  = $10
NES_SELECT = $20
NES_B      = $40
NES_A      = $80

.segment "BSS"

joy_accum: .res 1

.segment "CODE"

.proc HAL_PollJoy
@drain:
    jsr KERNAL_GETIN
    cmp #0
    beq @done                           ; queue empty
    jsr map_key
    ora joy_accum
    sta joy_accum
    bra @drain
@done:
    lda joy_accum
    stz joy_accum                       ; one-shot: consumed on read
    rts
.endproc

; Translate a PETSCII byte in A to an NES-button mask. Unknown keys
; return 0 so they OR cleanly into joy_accum.
.proc map_key
    cmp #PETSCII_RETURN
    bne :+
    lda #NES_START
    rts
:   cmp #PETSCII_SPACE
    bne :+
    lda #NES_SELECT
    rts
:   cmp #PETSCII_UP
    bne :+
    lda #NES_UP
    rts
:   cmp #PETSCII_DOWN
    bne :+
    lda #NES_DOWN
    rts
:   cmp #PETSCII_LEFT
    bne :+
    lda #NES_LEFT
    rts
:   cmp #PETSCII_RIGHT
    bne :+
    lda #NES_RIGHT
    rts
:   cmp #'X'
    beq @btn_a
    cmp #'x'
    beq @btn_a
    cmp #'Z'
    beq @btn_b
    cmp #'z'
    beq @btn_b
    lda #0
    rts
@btn_a:
    lda #NES_A
    rts
@btn_b:
    lda #NES_B
    rts
.endproc
