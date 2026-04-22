; ---------------------------------------------------------------------------
; ow_player_sprite_shim.asm - Translator wrapper for DrawPlayerMapmanSprite.
; ---------------------------------------------------------------------------
; Bundles two verbatim extracts:
;
;   ow_player_sprite.inc       -- DrawPlayerMapmanSprite      (bank_0F.asm:8263-8424)
;   lut_ow_player_sprite.inc   -- lut_VehicleSprY,
;                                 lut_VehicleFacingSprTblOffset,
;                                 lut_PlayerMapmanSprTbl       (bank_0F.asm:8527/8736/8751)
;
; The verbatim core still branches to DrawMMV_Ship / DrawMMV_Canoe / the
; airship path via Draw2x2Vehicle / Draw2x2Vehicle_Set, even though the
; first milestone only exercises the on-foot branch (vehicle = 1). Those
; paths are stubbed here as RTS so the link resolves -- they'll grow
; real bodies when we wire vehicle graphics later.
; ---------------------------------------------------------------------------

.importzp tmp
.import spr_x, spr_y, sprindex
.import oam
.import facing, vehicle
.import move_ctr_x, move_ctr_y
.import framecounter

.import Draw2x2Sprite

.export DrawPlayerMapmanSprite

.segment "RODATA"

.include "lut_ow_player_sprite.inc"

.segment "CODE"

.include "ow_player_sprite.inc"

; --- Vehicle draw stubs ----------------------------------------------------
; Referenced by the verbatim DrawPlayerMapmanSprite fall-throughs for the
; canoe / ship / airship vehicles. The on-foot test path (vehicle = 1)
; never reaches any of these, so an RTS is enough to resolve the link.
; Proper bodies (with a VehicleSprTbl LUT and matching CHR uploads) will
; land in a separate milestone.
.proc Draw2x2Vehicle
    rts
.endproc

.proc Draw2x2Vehicle_Set
    rts
.endproc
