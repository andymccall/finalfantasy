; ---------------------------------------------------------------------------
; am3.inc - Public API declarations for AM3 (Andy McCall's Memory Mapper).
; ---------------------------------------------------------------------------
; Callers include this with `.include "mbc/am3/am3.inc"` to get the symbol
; import block. See docs/am3_mbc_design.md for the full contract of each
; entry point.
; ---------------------------------------------------------------------------

.import AM3_Init
.import AM3_LoadBanks
.import AM3_SwitchBank
.import AM3_RestoreBank
.import AM3_CallBanked
.import AM3_CopyFromBank

; ZP pointers used by AM3_CopyFromBank. Callers populate these before the
; call: am3_src_ptr -> source in $A000-$BFFF, am3_dst_ptr -> resident dst.
.importzp am3_src_ptr
.importzp am3_dst_ptr
