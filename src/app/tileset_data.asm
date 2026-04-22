; ---------------------------------------------------------------------------
; tileset_data.asm - Overworld tileset-data staging.
; ---------------------------------------------------------------------------
; FF1 keeps the active map's tileset composition in a $400-byte RAM buffer
; at $0400 (see variables.inc). LoadOWTilesetData in bank_0F.asm:645 is a
; straight memcpy from `lut_OWTileset` in BANK_OWINFO into that buffer.
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
; On the port we keep the same buffer semantics but ship the source blob
; as a 1 KB RODATA .incbin (build/.../lut_ow_tileset.dat). LoadOWTilesetData
; copies from there at runtime. Later milestones add support for the
; standard-map tilesets (BANK_TILESETS); those will be a second .incbin and
; LoadOWTilesetData will select between them.
;
; Exports:
;   LoadOWTilesetData  - populate the RAM buffer from the RODATA blob.
;   tileset_data       - base of the 1 KB RAM buffer.
;   tsa_ul/ur/dl/dr/attr - convenience labels pointing into tileset_data.
;   tileset_prop       - alias for tileset_data.
; ---------------------------------------------------------------------------

.export LoadOWTilesetData
.export tileset_data
.export tileset_prop
.export tsa_ul, tsa_ur, tsa_dl, tsa_dr, tsa_attr
.export load_map_pal

.segment "BSS"

tileset_data:   .res $400

tileset_prop = tileset_data + $000
tsa_ul       = tileset_data + $100
tsa_ur       = tileset_data + $180
tsa_dl       = tileset_data + $200
tsa_dr       = tileset_data + $280
tsa_attr     = tileset_data + $300
load_map_pal = tileset_data + $380

.segment "RODATA"

ow_tileset_rom:
    .incbin "lut_ow_tileset.dat"
ow_tileset_rom_end:

.segment "CODE"

; LoadOWTilesetData -------------------------------------------------------
; Copy the 1 KB OW tileset blob from RODATA into tileset_data. The FF1
; original uses (zp),Y indirection with a $400 iteration counter; we're
; copying a fixed, known-size blob from RODATA, so four unrolled 256-byte
; loops are simpler and just as fast in practice.
.proc LoadOWTilesetData
    ldx #0
@page0:
    lda ow_tileset_rom + $000, x
    sta tileset_data + $000, x
    lda ow_tileset_rom + $100, x
    sta tileset_data + $100, x
    lda ow_tileset_rom + $200, x
    sta tileset_data + $200, x
    lda ow_tileset_rom + $300, x
    sta tileset_data + $300, x
    inx
    bne @page0
    rts
.endproc
