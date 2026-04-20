; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. Initialises the
; HAL, then runs the main game loop (one iteration per vertical blank).
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.export main

.segment "CODE"

.proc main
    jsr HAL_Init
@loop:
    jsr HAL_WaitVblank
    jmp @loop
.endproc
