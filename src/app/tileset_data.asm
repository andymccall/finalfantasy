; ---------------------------------------------------------------------------
; tileset_data.asm - Overworld tileset-data staging.
; ---------------------------------------------------------------------------
; FF1 kept the active map's tileset composition in a $400-byte RAM buffer
; at $0400 because the source data lived in a swappable MMC1 bank and had
; to be copied somewhere always-resident. On this port the source blob is
; a 1 KB RODATA .incbin that is itself always resident, so the copy is
; redundant -- the aliases are pointed straight at the RODATA blob.
;
; Layout of the buffer (same 128 metatiles ids as the RLE map bytes):
;   $000..$0FF  tileset_prop  (2 bytes per tile -- passability, battle bits)
;   $100..$17F  tsa_ul        (NES tile id for the metatile's UL 8x8)
;   $180..$1FF  tsa_ur
;   $200..$27F  tsa_dl
;   $280..$2FF  tsa_dr
;   $300..$37F  tsa_attr      (2-bit palette group packed x4, always uniform)
;   $380..$3AF  load_map_pal  (48 bytes of palette seed data)
;
; No callers write to any of these aliases -- they are read-only lookup
; tables used by map_draw and the palette seed path. If a future feature
; needs mutable tileset state (e.g. tileset swap at runtime), reintroduce
; a RAM buffer and reinstate the copy path.
;
; Exports:
;   LoadOWTilesetData  - no-op kept for caller compatibility.
;   tileset_data       - base of the 1 KB RODATA blob.
;   tsa_ul/ur/dl/dr/attr - convenience labels pointing into tileset_data.
;   tileset_prop       - alias for tileset_data.
; ---------------------------------------------------------------------------

.export LoadOWTilesetData
.export tileset_data
.export tileset_prop
.export tsa_ul, tsa_ur, tsa_dl, tsa_dr, tsa_attr
.export load_map_pal

.segment "RODATA"

tileset_data:
    .incbin "lut_ow_tileset.dat"

tileset_prop = tileset_data + $000
tsa_ul       = tileset_data + $100
tsa_ur       = tileset_data + $180
tsa_dl       = tileset_data + $200
tsa_dr       = tileset_data + $280
tsa_attr     = tileset_data + $300
load_map_pal = tileset_data + $380

.segment "CODE"

; LoadOWTilesetData -------------------------------------------------------
; No-op. The buffer is aliased directly onto the RODATA blob above, so
; there is nothing to copy. Kept as an entry point so existing callers
; (e.g. EnterMapTest) don't need to change when this file does.
.proc LoadOWTilesetData
    rts
.endproc
