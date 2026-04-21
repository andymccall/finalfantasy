; ---------------------------------------------------------------------------
; ff_ram.asm - FF1 RAM buffers allocated for host-side re-hosting.
; ---------------------------------------------------------------------------

.export cur_pal

.segment "BSS"

cur_pal:          .res 32       ; FF1 "current palette" -- 32 NES colour indices
