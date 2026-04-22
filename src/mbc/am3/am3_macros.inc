; ---------------------------------------------------------------------------
; am3_macros.inc - Convenience macros wrapping the raw AM3 API.
; ---------------------------------------------------------------------------
; Expects am3.inc and am3_cfg.inc to be available via .include/.import so
; AM3_CallBanked and its symbol partners resolve at assembly time.
; ---------------------------------------------------------------------------

; CALL_BANKED routine
;
; Invoke a routine that lives in a banked segment. The linker resolves
; .bankbyte(routine) to the bank number assigned to that symbol's segment
; and the raw address resolves to the $A000-$BFFF window. Trashes A/X/Y
; as per the callee (plus what AM3_CallBanked itself consumes).
.macro CALL_BANKED routine
    lda     #.bankbyte(routine)
    ldx     #>routine
    ldy     #<routine
    jsr     AM3_CallBanked
.endmacro
