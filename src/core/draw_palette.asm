; ---------------------------------------------------------------------------
; draw_palette.asm - FF1's DrawPalette with its hardware leaf amputated.
; ---------------------------------------------------------------------------
; Taken from bank_0F.asm of the FF1 disassembly:
;
;     DrawPalette:
;         LDA $2002       ; Reset PPU toggle
;         LDA #$3F        ; PPU Address := $3F00 (start of palettes)
;         STA $2006
;         LDA #$00
;         STA $2006
;         LDX #$00
;         JMP _DrawPalette_Norm
;     _DrawPalette_Norm:
;         LDA cur_pal, X
;         STA $2007
;         INX
;         CPX #$20
;         BCC _DrawPalette_Norm
;         ; ...trailing PPU address reset...
;         RTS
;
; The body walked cur_pal (32 NES colour indices) out to PPU registers
; $2006/$2007. On the host we cannot meaningfully intercept STA to those
; literal addresses, so the routine is treated as a HARDWARE LEAF: its
; body is removed and replaced with a call to the HAL. Callers in the
; FF1 source remain unaware -- they still see a routine named DrawPalette
; that pushes cur_pal to the display.
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.export DrawPalette

.segment "CODE"

.proc DrawPalette
    jsr HAL_UploadPalette
    rts
.endproc
