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
;   - .export for TitleScreen_Copyright so app/main.asm can call it
;   - a minimal IntroTitlePrepare stub (the real one lives elsewhere in
;     bank_0E and isn't in scope yet) -- an RTS is safe because the virtual
;     PPU starts with a cleared nametable, so the only thing we skip is
;     music start and scroll reset.
;
; The .include pulls in the hook-script output from build/core/.
; ---------------------------------------------------------------------------

.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write

.export TitleScreen_Copyright

.segment "CODE"

IntroTitlePrepare:
    rts

.include "title_copyright.inc"
