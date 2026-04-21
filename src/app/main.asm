; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. HAL_Init brings
; the display up and uploads the FF1 font into host tile memory. The demo
; then simulates an NES program that writes a single tile byte into the
; PPU nametable at address $2042 (row 2, column 2): FF1's internal code
; for 'A' is $8A (see table_standard.tbl in the disassembly), so that is
; what we deposit. The HAL traps the PPU register writes, stores the byte
; in the 2KB nametable mirror, and the vblank handler flushes the mirror
; to the host display each frame with FF1's own glyph data.
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.export main

FF1_CHAR_A = $8A                        ; FF1 encoding for 'A'

.segment "CODE"

.proc main
    jsr HAL_Init

    ; --- simulated NES code: STA to $2006/$2006/$2007 -----------------------
    lda #$20
    jsr HAL_PPU_2006_Write          ; PPU address high byte
    lda #$42
    jsr HAL_PPU_2006_Write          ; PPU address low byte -> $2042
    lda #FF1_CHAR_A
    jsr HAL_PPU_2007_Write          ; store tile byte; address auto-increments

@loop:
    jsr HAL_WaitVblank
    jmp @loop
.endproc
