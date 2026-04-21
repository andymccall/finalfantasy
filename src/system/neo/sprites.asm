; ---------------------------------------------------------------------------
; sprites.asm - Neo6502 HAL sprite plane (stub).
; ---------------------------------------------------------------------------
; HAL_OAMFlush is the $4014 OAMDMA hook; real Neo implementation
; (via Group 6 "Sprite Set") lands in a later step. For now this is
; an RTS -- the cursor simply does not render on Neo until then.
; ---------------------------------------------------------------------------

.export HAL_OAMFlush

.segment "CODE"

.proc HAL_OAMFlush
    rts
.endproc
