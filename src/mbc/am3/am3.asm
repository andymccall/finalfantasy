; ---------------------------------------------------------------------------
; am3.asm - AM3 (Andy McCall's Memory Mapper) runtime.
; ---------------------------------------------------------------------------
; Exposes the Commander X16's banked-RAM window at $A000-$BFFF as a pool
; of 8KB banks that application code can switch between via a small
; save/restore API. See docs/am3_mbc_design.md for the full design.
;
; This is the initial scaffold: AM3_Init is real; the remaining entries
; are stubbed until the first banked caller needs them. Stubs fail loudly
; by design (brk) so accidental use is caught during development.
; ---------------------------------------------------------------------------

.include "mbc/am3/am3_cfg.inc"

.export AM3_Init

.segment "CODE"

; AM3_Init -------------------------------------------------------------------
; Initialise AM3 runtime state. Pins the bank register to 0, which is the
; reserved "resident data" bank -- any data segment linked into bank 0 is
; live in $A000-$BFFF from this point on and is the default bank that
; AM3_RestoreBank falls back to. Must be called exactly once at program
; start, before any other AM3 call.
.proc AM3_Init
    lda     #0
    sta     AM3_BANK_REGISTER
    rts
.endproc

; Other entry points (AM3_SwitchBank / AM3_RestoreBank / AM3_CallBanked /
; AM3_CopyFromBank) are not yet implemented -- they will be added as
; banked callers come online. Keeping them out of CODE avoids wasting
; resident RAM on brk stubs that nothing calls.
