; ---------------------------------------------------------------------------
; draw_palette_shim.asm - Translator wrapper around verbatim FF1 DrawPalette.
; ---------------------------------------------------------------------------
; src/core/draw_palette.asm is a byte-for-byte extract of DrawPalette (and
; its tail _DrawPalette_Norm) from bank_0F.asm -- no ca65 directives, no
; imports/exports, so it stays aligned with the disassembly.
;
; The hook script rewrites the STA $2006 / STA $2007 writes into HAL JSRs,
; and the virtual PPU's palette trap routes the resulting $3F00..$3F1F
; stores into palette_ram / HAL_PalettePush. This shim supplies everything
; else ca65 needs to link that extract:
;
;   - .segment "CODE"
;   - .import for the HAL hooks the rewritten code now JSRs into
;   - .import for cur_pal (the 32-byte FF1 palette staging buffer)
;   - .export for DrawPalette so main.asm can call it
;
; The .include pulls in the hook-script output from build/core/.
; ---------------------------------------------------------------------------

.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write
.import cur_pal

.export DrawPalette

.segment "CODE"

.include "draw_palette.inc"
