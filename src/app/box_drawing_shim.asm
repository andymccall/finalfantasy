; ---------------------------------------------------------------------------
; box_drawing_shim.asm - Translator wrapper for FF1 menu-box primitives.
; ---------------------------------------------------------------------------
; Bundles four verbatim extracts from bank_0F.asm behind one ca65 file so
; ca65 sees a single compilation unit with consistent imports/exports:
;
;   coord_to_nt_addr.inc  -- CoordToNTAddr (row/col -> ppu_dest)
;   nt_row_luts.inc       -- lut_NTRowStartLo / lut_NTRowStartHi (RODATA)
;   draw_box.inc          -- DrawBox + DrawBoxRow_Top/Mid/Bot
;   menu_cond_stall.inc   -- MenuCondStall (waits a frame if menustall != 0)
;
; The hook script rewrites every NES-port STA against $2000/$2005/$2006/
; $2007 into JSRs against the HAL; this shim pulls those hooks in. It
; also stubs CallMusicPlay -- which MenuCondStall JSRs into when
; menustall != 0, and which TitleScreen_Music JSRs every frame -- and
; exports it so title_screen_shim can reach the same stub. WaitForVBlank_L
; lives in title_screen_shim (since it's on the title loop's critical
; frame path there); MenuCondStall reaches it via that export.
;
; Segment switches around the nt_row_luts include keep the two 32-byte
; tables in RODATA while the rest stays in CODE.
; ---------------------------------------------------------------------------

.import HAL_PPU_2000_Write
.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write

.import box_x, box_y, box_wd, box_ht
.import dest_x, dest_y
.import ppu_dest
.importzp tmp
.import soft2000
.import menustall

.import WaitForVBlank_L                 ; provided by title_screen_shim

.export DrawBox
.export DrawBoxRow_Top
.export DrawBoxRow_Mid
.export DrawBoxRow_Bot
.export CoordToNTAddr
.export MenuCondStall
.export CallMusicPlay
.export lut_NTRowStartLo
.export lut_NTRowStartHi

.segment "CODE"

; Music driver stub -- reached via MenuCondStall (when menustall != 0) and
; every frame from TitleScreen_Music. No audio driver yet, so it's RTS.
CallMusicPlay:
    rts

.include "coord_to_nt_addr.inc"

.segment "RODATA"
.include "nt_row_luts.inc"

.segment "CODE"
.include "draw_box.inc"
.include "menu_cond_stall.inc"
