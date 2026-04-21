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
; also stubs CallMusicPlay and WaitForVBlank_L, which MenuCondStall JSRs
; into when menustall != 0. The application keeps menustall at 0 for the
; whole title screen (PPU is off -- no stall needed), so those stubs are
; never actually called; they only exist so the linker can resolve the
; symbols.
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
.import tmp
.import soft2000
.import menustall

.export DrawBox
.export DrawBoxRow_Top
.export DrawBoxRow_Mid
.export DrawBoxRow_Bot
.export CoordToNTAddr
.export MenuCondStall
.export lut_NTRowStartLo
.export lut_NTRowStartHi

.segment "CODE"

; Stubs for the two routines MenuCondStall jumps into when menustall != 0.
; On the title screen menustall is 0, so these are unreachable -- they
; only satisfy the linker. When audio / vblank support arrives, replace
; these with real implementations and delete the stubs.
CallMusicPlay:
    rts
WaitForVBlank_L:
    rts

.include "coord_to_nt_addr.inc"

.segment "RODATA"
.include "nt_row_luts.inc"

.segment "CODE"
.include "draw_box.inc"
.include "menu_cond_stall.inc"
