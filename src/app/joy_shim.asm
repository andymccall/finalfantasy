; ---------------------------------------------------------------------------
; joy_shim.asm - Translator wrapper for the joypad input path.
; ---------------------------------------------------------------------------
; The verbatim ReadJoypadData in bank_0F.asm strobes $4016 and shifts 8
; bits out of the NES controller shift register. Our host platforms don't
; have that hardware, so instead of porting the strobe-and-shift loop we
; ask the HAL for the already-assembled NES-button byte (HAL_PollJoy) and
; drop it straight into 'joy'. The edge-detection that follows -- the
; weird EOR/mask dance that turns per-frame joypad levels into
; press-transition counters -- is identical on any 6502, so
; ProcessJoyButtons is pulled in verbatim from bank_0F.asm:5747-5845.
;
; UpdateJoy is the one FF1 routine callers reach for; the NES version
; chains ReadJoypadData into ProcessJoyButtons, and ours does the same
; with HAL_PollJoy standing in for the NES-specific read.
;
; The previous RTS stub in title_screen_shim is now removed -- this
; export is the real thing, and title_screen_shim's .import UpdateJoy
; resolves here instead.
; ---------------------------------------------------------------------------

.import HAL_PollJoy

.import joy, joy_a, joy_b, joy_start, joy_select, joy_ignore
.importzp tmp

.export UpdateJoy

.segment "CODE"

.proc UpdateJoy
    jsr HAL_PollJoy
    sta joy
    jmp ProcessJoyButtons               ; tail-call; returns through our RTS
.endproc

.include "process_joy_buttons.inc"
