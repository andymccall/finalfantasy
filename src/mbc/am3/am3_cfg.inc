; ---------------------------------------------------------------------------
; am3_cfg.inc - Per-project AM3 configuration.
; ---------------------------------------------------------------------------
; The single file a project edits when adopting AM3. Change these constants
; to match the adopting project's bank layout and RAM/ROM register choice.
; Everything else in src/mbc/am3/ is meant to be dropped in unchanged.
; ---------------------------------------------------------------------------

; Total number of banks AM3 can address. The stock Commander X16 has 64
; banks of 8KB = 512KB banked RAM. The 2MB expansion gives 256 banks.
; FF is targeted at the 2MB config (see project_x16_memory_strategy
; memory entry).
AM3_BANK_COUNT     = 256

; Zero-page address of the RAM bank register. On the X16 this is fixed
; at $00 by the hardware; exposed as a constant for portability to
; other 65C02 systems that might use a different register.
AM3_BANK_REGISTER  = $00

; Maximum nesting depth for AM3_CallBanked. Each in-flight banked call
; consumes one slot in the saved-bank stack. Depth 4 is enough for
; typical game flow (e.g. main -> menu -> submenu -> inventory); raise
; if a caller hits the limit.
AM3_STACK_DEPTH    = 4

; First bank number that AM3 is allowed to hand out to switchable callers.
; Banks below this are "reserved" and always selected at AM3_Init time,
; so resident data pinned at $A000-$BFFF can live there undisturbed.
; FF reserves bank 0 for the MAPDATA row cache (see MAPAREA in x16.cfg).
AM3_FIRST_USER_BANK = 1
