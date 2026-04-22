; ---------------------------------------------------------------------------
; am3.asm - AM3 (Andy McCall's Memory Mapper) runtime.
; ---------------------------------------------------------------------------
; Exposes the Commander X16's banked-RAM window at $A000-$BFFF as a pool
; of 8KB banks that application code can switch between via a small
; save/restore API. See docs/am3_mbc_design.md for the full design.
;
; This is the initial scaffold: AM3_Init is real; the remaining entries
; are absent until the first banked caller needs them.
; ---------------------------------------------------------------------------

.include "mbc/am3/am3_cfg.inc"

.export AM3_Init

.segment "CODE"

; AM3_Init -------------------------------------------------------------------
; Initialise AM3 runtime state. Pins the bank register to AM3_RESIDENT_BANK
; (1 on X16 -- bank 0 is reserved by the KERNAL and bank-0 MAPDATA reads
; returned corrupt data even after writes, which broke overworld scroll).
; The resident bank is AM3's "default" bank: resident data segments
; (MAPDATA etc.) are linked into it, and AM3_RestoreBank returns here
; when the save-stack is empty. Must be called exactly once at program
; start, before any other AM3 call.
.proc AM3_Init
    lda     #AM3_RESIDENT_BANK
    sta     AM3_BANK_REGISTER
    rts
.endproc

; Other entry points (AM3_SwitchBank / AM3_RestoreBank / AM3_CallBanked /
; AM3_CopyFromBank) are not yet implemented -- they will be added as
; banked callers come online. Keeping them out of CODE avoids wasting
; resident RAM on brk stubs that nothing calls.
