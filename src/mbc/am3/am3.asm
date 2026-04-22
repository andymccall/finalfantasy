; ---------------------------------------------------------------------------
; am3.asm - AM3 (Andy McCall's Memory Mapper) runtime.
; ---------------------------------------------------------------------------
; Exposes the Commander X16's banked-RAM window at $A000-$BFFF as a pool
; of 8KB banks that application code can switch between via a small
; save/restore API. See docs/am3_mbc_design.md for the full design.
;
; Save-slot model: a single-slot save is used rather than a stack. This
; is enough for the current call pattern (resident -> banked -> resident)
; and can be grown into a stack later without changing the public API.
; If nested banked calls are attempted today the inner call will clobber
; the outer slot; assertions / a real stack are a future upgrade.
; ---------------------------------------------------------------------------

.include "mbc/am3/am3_cfg.inc"

.export AM3_Init
.export AM3_SwitchBank
.export AM3_RestoreBank
.export AM3_CallBanked
.export AM3_CopyFromBank
.export AM3_LoadBanks

; Linker-defined symbols for the BANKED_02 segment (load = MAIN, run = BANK02).
; AM3_LoadBanks reads BANKED_02 from its MAIN load address and writes it to
; $A000 with bank 2 selected.
.import __BANKED_02_LOAD__
.import __BANKED_02_SIZE__

; AM3_CopyFromBank uses a pair of ZP pointers for src ($A000-$BFFF) and
; dst (resident). Kept local to this module so adopters don't have to
; carve zeropage elsewhere.
.segment "ZEROPAGE"
am3_src_ptr: .res 2
am3_dst_ptr: .res 2

; Single-slot save for the previous bank value. Written by AM3_SwitchBank,
; consumed by AM3_RestoreBank. Not a stack: nested banked calls clobber.
.segment "BSS"
am3_saved_bank: .res 1

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
    sta     am3_saved_bank          ; make RestoreBank a safe no-op before
                                    ; any SwitchBank has run
    rts
.endproc

; AM3_SwitchBank -------------------------------------------------------------
; A = target bank. Saves the current bank into am3_saved_bank and writes
; A to the bank register. Preserves X and Y.
.proc AM3_SwitchBank
    pha                             ; stash target
    lda     AM3_BANK_REGISTER
    sta     am3_saved_bank
    pla
    sta     AM3_BANK_REGISTER
    rts
.endproc

; AM3_RestoreBank ------------------------------------------------------------
; Restore the bank saved by the most recent AM3_SwitchBank. Preserves X/Y.
; Clobbers A.
.proc AM3_RestoreBank
    lda     am3_saved_bank
    sta     AM3_BANK_REGISTER
    rts
.endproc

; AM3_CallBanked -------------------------------------------------------------
; A = target bank, X = target address high, Y = target address low.
; Switches to bank A, JSRs to the target (which must live at $A000-$BFFF
; in that bank), then restores the previous bank.
;
; The JSR is indirect via a small RAM trampoline: we store "jsr $XXXX"
; where $XXXX comes from X:Y into a 3-byte code buffer here in CODE and
; execute it. ca65 can't assemble a direct JSR to a runtime address, so
; this trampoline trick is standard.
.proc AM3_CallBanked
    pha                             ; stash bank
    stx     am3_call + 2            ; target hi
    sty     am3_call + 1            ; target lo
    pla
    jsr     AM3_SwitchBank
am3_call:
    jsr     $FFFF                   ; patched above with X:Y
    jmp     AM3_RestoreBank         ; tail-call; RestoreBank rts returns to caller
.endproc

; AM3_CopyFromBank -----------------------------------------------------------
; Bulk-copy (count) bytes from (bank A, src $A000+offset) to (resident dst),
; then restore the previous bank.
; Inputs:
;   A                = source bank number
;   am3_src_ptr      = source address in $A000-$BFFF
;   am3_dst_ptr      = destination address (anywhere outside the window)
;   X                = byte count (1..255; zero would copy 256)
; Clobbers A, Y. Preserves X's value on exit is not guaranteed.
.proc AM3_CopyFromBank
    jsr     AM3_SwitchBank          ; after this $A000-$BFFF maps to bank A
    ldy     #0
@copy:
    lda     (am3_src_ptr), y
    sta     (am3_dst_ptr), y
    iny
    dex
    bne     @copy
    jmp     AM3_RestoreBank         ; tail-call
.endproc

; AM3_LoadBanks --------------------------------------------------------------
; One-shot boot loader: copies the BANKED_02 image from its MAIN load address
; to $A000 with bank 2 selected. Call exactly once, after AM3_Init, before
; any banked code/data is referenced. Returns with the resident bank
; (AM3_RESIDENT_BANK) selected so subsequent code sees the normal window.
;
; Uses a 16-bit counter so the full 8KB bank can be copied if BANKED_02 grows.
; Clobbers A, X, Y, am3_src_ptr, am3_dst_ptr, am3_saved_bank.
.proc AM3_LoadBanks
    ; src = __BANKED_02_LOAD__ (in MAIN), dst = $A000 (banked window).
    lda     #<__BANKED_02_LOAD__
    sta     am3_src_ptr
    lda     #>__BANKED_02_LOAD__
    sta     am3_src_ptr + 1
    lda     #$00
    sta     am3_dst_ptr
    lda     #$A0
    sta     am3_dst_ptr + 1

    lda     #AM3_FIRST_USER_BANK        ; bank 2
    jsr     AM3_SwitchBank              ; $A000-$BFFF now maps to bank 2

    ; Copy whole pages first (X = page count = high byte of size), then the
    ; tail bytes (low byte of size). Y walks 0..255 inside each page.
    ldx     #>__BANKED_02_SIZE__
    beq     @tail                       ; size < 256 bytes: skip page loop
    ldy     #0
@page_loop:
    lda     (am3_src_ptr), y
    sta     (am3_dst_ptr), y
    iny
    bne     @page_loop
    inc     am3_src_ptr + 1
    inc     am3_dst_ptr + 1
    dex
    bne     @page_loop
@tail:
    ldx     #<__BANKED_02_SIZE__
    beq     @done                       ; size was an exact page multiple
    ldy     #0
@tail_loop:
    lda     (am3_src_ptr), y
    sta     (am3_dst_ptr), y
    iny
    dex
    bne     @tail_loop
@done:
    jmp     AM3_RestoreBank             ; tail-call back to resident bank
.endproc
