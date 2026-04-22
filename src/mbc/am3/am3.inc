; ---------------------------------------------------------------------------
; am3.inc - Public API declarations for AM3 (Andy McCall's Memory Mapper).
; ---------------------------------------------------------------------------
; Callers include this with `.include "mbc/am3/am3.inc"` to get the symbol
; import block. See docs/am3_mbc_design.md for the full contract of each
; entry point.
; ---------------------------------------------------------------------------

.import AM3_Init
; Additional entries (AM3_SwitchBank / AM3_RestoreBank / AM3_CallBanked /
; AM3_CopyFromBank) will be added to this import block when their bodies
; land in am3.asm.
