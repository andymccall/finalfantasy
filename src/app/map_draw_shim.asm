; ---------------------------------------------------------------------------
; map_draw_shim.asm - Wrapper for verbatim map-draw routines.
; ---------------------------------------------------------------------------
; map_draw.inc carries the verbatim extracts (from bank_0F.asm):
;
;   DrawFullMap        (3821-3864)
;   StartMapMove       (3879-4028)
;   ScrollUpOneRow     (4082-4109)
;   PrepRowCol         (4392-4473)
;   DrawMapRowCol      (4508-4681)
;   PrepAttributePos   (4709-4778)
;   DrawMapAttributes  (4822-4852)
;   lut_2xNTRowStartLo / lut_2xNTRowStartHi
;
; PrepRowCol has a PrepSMRowCol branch we don't cover yet; the JMP target
; is imported as a stub that just RTS's. OW always branches the other way
; (mapflags bit 0 = 0), so the stub is never taken on this path.
; ---------------------------------------------------------------------------

.import HAL_PPU_2000_Write
.import HAL_PPU_2001_Write
.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2006_Write_X
.import HAL_PPU_2006_Write_Y
.import HAL_PPU_2007_Write
.import HAL_PPU_2007_Write_X
.import HAL_PPU_2007_Write_Y
.import HAL_PPU_2007_Read

.importzp tmp
.import mapflags, mapdraw_x, mapdraw_y, mapdraw_ntx, mapdraw_nty, mapdraw_job
.import facing, move_speed, scroll_y
.import ow_scroll_x, ow_scroll_y, sm_scroll_x, sm_scroll_y
.import sm_player_x, sm_player_y, vehicle
.import draw_buf_ul, draw_buf_ur, draw_buf_dl, draw_buf_dr, draw_buf_attr
.import draw_buf_at_hi, draw_buf_at_lo, draw_buf_at_msk
.import mapdata

.import tsa_ul, tsa_ur, tsa_dl, tsa_dr, tsa_attr
.import LoadOWMapRow
.import PrepSMRowCol

.export DrawFullMap
.export StartMapMove
.export ScrollUpOneRow
.export PrepRowCol
.export DrawMapRowCol
.export PrepAttributePos
.export DrawMapAttributes

.segment "CODE"

.include "map_draw.inc"
