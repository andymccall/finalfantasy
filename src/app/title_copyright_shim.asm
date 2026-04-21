; ---------------------------------------------------------------------------
; title_copyright_shim.asm - Translator wrapper around verbatim FF1 routine.
; ---------------------------------------------------------------------------
; The core file src/core/title_copyright.asm is a byte-for-byte extract of
; TitleScreen_Copyright from bank_0E.asm. It deliberately carries no ca65
; directives (no .segment, no .import/.export), because every addition would
; drift it from the disassembly. The hook script rewrites its PPU port
; writes into HAL JSRs; this shim supplies everything else ca65 needs to
; link that extract into our build:
;
;   - .segment "CODE" so the routine lands in the code bank
;   - .import for the HAL hooks the rewritten source now JSRs into
;   - .import for IntroTitlePrepare, which TitleScreen_Copyright JSRs into
;     and which now lives in title_screen_shim as a verbatim extract
;     (bank_0E.asm:3600)
;   - .export for TitleScreen_Copyright so other modules can call it
;
; The .include pulls in the hook-script output from build/core/.
; ---------------------------------------------------------------------------

.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write
.import IntroTitlePrepare

.export TitleScreen_Copyright

.segment "CODE"

.include "title_copyright.inc"
