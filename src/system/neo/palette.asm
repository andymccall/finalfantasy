; ---------------------------------------------------------------------------
; palette.asm - Neo6502 HAL_PalettePush stub.
; ---------------------------------------------------------------------------
; The Neo console mode renders through a fixed firmware font/palette, so a
; per-slot NES -> Neo colour translation has no hardware to push at in this
; milestone. The stub accepts the call (A = NES colour, X = slot) and
; returns immediately with all registers preserved, keeping the HAL
; contract satisfied while later work decides whether to switch to
; graphics mode or a custom tile renderer.
; ---------------------------------------------------------------------------

.export HAL_PalettePush

.segment "CODE"

.proc HAL_PalettePush
    rts
.endproc
