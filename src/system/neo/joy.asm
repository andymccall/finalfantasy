; ---------------------------------------------------------------------------
; joy.asm - Neo6502 joypad HAL.
; ---------------------------------------------------------------------------
; Uses Group 7 / Function 1 "Read Default Controller" -- a compatibility
; API that exposes the base controller (WASD+OPKL or arrow keys+ZXCV on
; the keyboard, or a real gamepad if attached) as a single 8-bit level
; byte. Unlike the console keyboard queue, this returns real-time
; button *state* (not edge events) and doesn't echo or defer, so the
; NES-style ProcessJoyButtons edge detector gets the held/released model
; it was written for.
;
; Neo bit layout (Group 7 Function 1 result):
;   bit 0 Left    bit 4 A
;   bit 1 Right   bit 5 B
;   bit 2 Up      bit 6 X
;   bit 3 Down    bit 7 Y
;
; NES bit layout (contract in hal.inc / ReadJoypadData in bank_0F):
;   bit 0 Right   bit 4 Start
;   bit 1 Left    bit 5 Select
;   bit 2 Down    bit 6 B
;   bit 3 Up      bit 7 A
;
; Mapping via a 256-entry translation LUT at boot would be overkill. We
; rebuild the byte bit-by-bit: d-pad needs bit re-ordering (Left/Right
; and Up/Down swap pairs) and the face buttons need re-homing. Neo X
; doubles as NES Start so the title screen's A-or-Start exit path works
; off a button keyboard users can reach easily (X on the physical
; gamepad, or 'P' on the keyboard per the firmware's default binding).
; ---------------------------------------------------------------------------

.export HAL_PollJoy

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_CONTROLLER = $07
API_FN_READ_CONTROLLER = $01

NEO_LEFT  = $01
NEO_RIGHT = $02
NEO_UP    = $04
NEO_DOWN  = $08
NEO_A     = $10
NEO_B     = $20
NEO_X     = $40
NEO_Y     = $80

NES_RIGHT  = $01
NES_LEFT   = $02
NES_DOWN   = $04
NES_UP     = $08
NES_START  = $10
NES_SELECT = $20
NES_B      = $40
NES_A      = $80

.segment "CODE"

.proc HAL_PollJoy
    lda #API_FN_READ_CONTROLLER
    sta API_FUNCTION
@wait_idle:
    lda API_COMMAND
    bne @wait_idle
    lda #API_GROUP_CONTROLLER
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done

    ; A = Neo controller byte; translate bit-by-bit into NES layout.
    lda API_PARAMETERS + 0
    tax                                 ; keep raw Neo byte in X
    lda #0                              ; accumulator for NES byte

    cpx #0
    beq @done

    pha
    txa
    and #NEO_LEFT
    beq :+
    pla
    ora #NES_LEFT
    pha
:   txa
    and #NEO_RIGHT
    beq :+
    pla
    ora #NES_RIGHT
    pha
:   txa
    and #NEO_UP
    beq :+
    pla
    ora #NES_UP
    pha
:   txa
    and #NEO_DOWN
    beq :+
    pla
    ora #NES_DOWN
    pha
:   txa
    and #NEO_A
    beq :+
    pla
    ora #NES_A
    pha
:   txa
    and #NEO_B
    beq :+
    pla
    ora #NES_B
    pha
:   txa
    and #NEO_X
    beq :+
    pla
    ora #NES_START
    pha
:   txa
    and #NEO_Y
    beq :+
    pla
    ora #NES_SELECT
    pha
:   pla
@done:
    rts
.endproc
