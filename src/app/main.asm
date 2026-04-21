; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. Initialises the
; HAL, then simulates an NES program that writes a single tile byte into
; the PPU nametable at address $2042 (row 2, column 2). The HAL intercepts
; the PPU register writes, stores the byte in the 2KB nametable mirror,
; and the vblank handler flushes the mirror to the host display each frame.
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.export main

.segment "CODE"

.proc main
    jsr HAL_Init

    ; --- simulated NES code: STA to $2006/$2006/$2007 -----------------------
    lda #$20
    jsr HAL_PPU_2006_Write          ; PPU address high byte
    lda #$42
    jsr HAL_PPU_2006_Write          ; PPU address low byte -> $2042
    lda #'A'
    jsr HAL_PPU_2007_Write          ; store tile byte; address auto-increments

@loop:
    jsr HAL_WaitVblank
    jmp @loop
.endproc
