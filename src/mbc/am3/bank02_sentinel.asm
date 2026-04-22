; ---------------------------------------------------------------------------
; bank02_sentinel.asm - Single-byte payload for BANK02.
; ---------------------------------------------------------------------------
; Exists purely to give the BANKED_02 segment a byte of content so the
; linker emits it and the AM3 bank loader has something non-empty to copy.
; Remove this file (or shrink the .byte) once a real banked feature claims
; BANKED_02 -- the sentinel exists only to verify the loader plumbing.
;
; The byte value $A3 is the literal "AM3" initials in hex-ish form; a
; verification read after AM3_LoadBanks should return $A3 when the bank
; is selected.
; ---------------------------------------------------------------------------

.export am3_bank02_sentinel

.segment "BANKED_02"

am3_bank02_sentinel:
    .byte   $A3
