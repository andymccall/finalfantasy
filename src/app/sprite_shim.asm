; ---------------------------------------------------------------------------
; sprite_shim.asm - Translator wrapper for Draw2x2Sprite + DrawCursor.
; ---------------------------------------------------------------------------
; Bundles three verbatim extracts:
;
;   draw_2x2_sprite.inc              -- Draw2x2Sprite       (bank_0F.asm:8460-8519)
;   draw_cursor.inc                  -- DrawCursor          (bank_0F.asm:10516-10523)
;   lut_cursor_2x2_sprite_table.inc  -- lutCursor2x2...     (bank_0F.asm:10549-10553)
;
; Draw2x2Sprite writes four NES sprite slots (16 bytes) into the oam
; buffer starting at oam[sprindex], pulling UL/DL/UR/DR tile+attribute
; pairs through (tmp),Y. DrawCursor loads tmp with lutCursor2x2... and
; tail-calls Draw2x2Sprite. Neither touches a PPU port -- the actual
; upload lands in the OAMDMA ($4014) hook, routed to HAL_OAMFlush.
;
; EnterTitleScreen's per-frame loop does:
;     ClearOAM                 ; zero oam[], reset sprindex
;     DrawCursor               ; build 4 sprite slots at oam[0..15]
;     STA $4014 (= JSR HAL_APU_4014_Write -> HAL_OAMFlush)
; So the sprite plane tracks the NES OAM buffer exactly.
; ---------------------------------------------------------------------------

.importzp tmp
.import oam
.import spr_x, spr_y, sprindex

.export Draw2x2Sprite
.export DrawCursor

.segment "RODATA"

.include "lut_cursor_2x2_sprite_table.inc"

.segment "CODE"

.include "draw_2x2_sprite.inc"

.include "draw_cursor.inc"
