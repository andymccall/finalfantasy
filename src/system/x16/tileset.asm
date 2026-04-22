; ---------------------------------------------------------------------------
; tileset.asm - X16 HAL_LoadTileset + HAL_SetTileMode + map-tile upload.
; ---------------------------------------------------------------------------
; X16 has enough VRAM to keep both tilesets resident simultaneously. Font
; tiles occupy VERA slots $80..$FF (VRAM $1:D000, uploaded by tiles_load.asm)
; and map tiles occupy slots $00..$7F (VRAM $1:C000, uploaded here). So
; HAL_LoadTileset is a no-op at runtime -- the mode byte is what decides
; which slot range the nametable maps to, not which tileset is resident.
;
; HAL_UploadMapTiles runs once from HAL_Init (after HAL_LoadTiles) to push
; the converted overworld BG tiles into slots $00..$7F, leaving slot $00
; as the first map tile rather than blank. NES tile $00 on a map screen
; is the real map tile 0 (typically ocean or grass); ppu_flush will render
; it as slot $00 when tile_mode = 1.
;
; tile_mode semantics (consulted by ppu_flush):
;   0  menu : NES $00..$7F -> blank (zero tile-id in nametable map) or
;                             treated as ClearNT sentinel; $80..$FF ->
;                             VERA slot = byte (no offset).
;   1  map  : NES $00..$7F -> VERA slot = byte (map tiles in $00..$7F);
;             $80..$FF -> unused (render as blank).
;
; X16 ppu_flush currently writes `mirror_byte` directly as the VERA tile
; id (see ppu_flush.asm header). In menu mode today, ClearNT's $00 bytes
; render VERA slot 0 which tiles_load.asm explicitly zeroed (blank). Once
; we install map tiles at slot 0, menu mode needs to continue treating $00
; as blank -- ppu_flush reads tile_mode to decide whether to overwrite
; $00 with the blank-tile id (0 now becomes "map tile 0, ocean"). See
; ppu_flush.asm for the branch.
; ---------------------------------------------------------------------------

.export HAL_LoadTileset
.export HAL_SetTileMode
.export HAL_UploadMapTiles
.export tile_mode

VERA_ADDR_L   = $9F20
VERA_ADDR_M   = $9F21
VERA_ADDR_H   = $9F22
VERA_DATA0    = $9F23

; Map-tile VRAM region: slots $00..$7F at VRAM $1:C000, 128 tiles * 32 bytes
; = 4 KB.
MAPTILE_L     = $00
MAPTILE_M     = $C0
MAPTILE_H     = $11                     ; bank 1, stride +1

.segment "ZEROPAGE"

maptile_ptr: .res 2

.segment "RODATA"

maptiles_ow:
    .incbin "maptiles_ow.bin"
maptiles_ow_end:

MAPTILES_SIZE_PAGES = (maptiles_ow_end - maptiles_ow) >> 8

.segment "BSS"

tile_mode: .res 1                       ; 0 = menu, 1 = map

.segment "CODE"

; HAL_LoadTileset -----------------------------------------------------------
; A = tileset id (0 = font, 1 = OW map). No-op on X16 -- both tilesets
; are already uploaded at boot. Kept so the HAL contract is symmetric.
.proc HAL_LoadTileset
    rts
.endproc

; HAL_SetTileMode -----------------------------------------------------------
; A = 0 (menu) or 1 (map). Stashed for ppu_flush to consult per cell.
.proc HAL_SetTileMode
    sta tile_mode
    rts
.endproc

; HAL_UploadMapTiles --------------------------------------------------------
; Push the converted overworld BG tiles (4 KB, 128 VERA tiles) into VRAM
; slots $00..$7F. Called from HAL_Init at boot so map mode has the data
; ready whenever the app flips tile_mode to 1.
.proc HAL_UploadMapTiles
    lda #MAPTILE_L
    sta VERA_ADDR_L
    lda #MAPTILE_M
    sta VERA_ADDR_M
    lda #MAPTILE_H
    sta VERA_ADDR_H

    lda #<maptiles_ow
    sta maptile_ptr + 0
    lda #>maptiles_ow
    sta maptile_ptr + 1

    ldx #MAPTILES_SIZE_PAGES            ; 4096 / 256 = 16 pages
@page_loop:
    ldy #0
@byte_loop:
    lda (maptile_ptr), y
    sta VERA_DATA0
    iny
    bne @byte_loop
    inc maptile_ptr + 1
    dex
    bne @page_loop
    rts
.endproc
