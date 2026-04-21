; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. Initialises the
; HAL, pushes a test palette to the display via the FF1 DrawPalette leaf,
; then runs the main game loop (one iteration per vertical blank).
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.import LoadTestPalette
.import DrawPalette

.export main

.segment "CODE"

.proc main
    jsr HAL_Init
    jsr LoadTestPalette         ; stage 32 NES colour indices in cur_pal
    jsr DrawPalette             ; FF1 leaf -> HAL_UploadPalette
    jsr HAL_ShowPaletteStrip    ; visual verification of NES->host mapping
@loop:
    jsr HAL_WaitVblank
    jmp @loop
.endproc
