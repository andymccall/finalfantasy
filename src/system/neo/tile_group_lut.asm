; ---------------------------------------------------------------------------
; tile_group_lut.asm - (tile_id, attr_group) -> Neo tile-slot lookup.
; ---------------------------------------------------------------------------
; ppu_flush.asm paints OW cells by reading an NES tile id out of the
; nametable mirror and an attribute group out of the attribute-table
; mirror. The Neo tile bake ships 128 per-(tile, group) variants, so the
; paint path needs to translate (tile_id, group) to a Neo tile slot.
;
; The LUT is built at scripts/chr_to_neo_gfx.py --mode map-groups time.
; It is 1 KB, indexed as (tile_id * 4 + group); entry value = Neo tile
; slot to Draw Image for that cell.
;
; Rare (tile, group) pairs that miss the top-128 bake are routed to a
; baked variant of the same tile in the nearest-luminance group. Tile
; ids that were dropped from the bake entirely (107 rarest OW tiles,
; ~0.1% of cells) are routed to slot 0, which is always the single
; most-used OW tile -- a least-surprising visible failure mode.
; ---------------------------------------------------------------------------

.export neo_tile_group_lut

.segment "RODATA"

neo_tile_group_lut:
    .incbin "tiles_ow_groups.lut"
neo_tile_group_lut_end:
