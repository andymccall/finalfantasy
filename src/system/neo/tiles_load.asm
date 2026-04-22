; ---------------------------------------------------------------------------
; tiles_load.asm - Neo6502 HAL_LoadTiles implementation.
; ---------------------------------------------------------------------------
; Loads the menu/font tileset (tiles_font.gfx) into the Neo's
; gfxObjectMemory in a single API call. The file holds 128 16x16 tile
; images (FF1 font slots $00..$7F packed upper-left of each) plus the
; 16x16 cursor sprite at the end; the build script chr_to_neo_gfx.py
; produces it from bank_09 data + cursor CHR.
;
; This is the boot-time load. Runtime tileset switching (e.g. to the
; overworld tiles) goes through HAL_LoadTileset in tileset.asm, which
; loads tiles_ow.gfx over the top of the same memory region.
;
; API pattern: Group $03 Function $02 "Load File". Parameters:
;   P0/P1  filename pointer (length-prefixed Pascal string)
;   P2/P3  destination address; $FFFF targets gfxObjectMemory
;
; gfxObjectMemory is the single shared graphics buffer used by tiles,
; 16x16 sprites and 32x32 sprites (the 256-byte header at offset 0
; declares the counts). So this one load also installs the cursor sprite
; used by sprites.asm -- HAL_SpritesInit is now a no-op.
; ---------------------------------------------------------------------------

.export HAL_LoadTiles

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_FILEIO     = $03
API_FN_LOAD_FILENAME = $02

.segment "RODATA"

tiles_filename:
    .byte 14
    .byte "tiles_font.gfx"

.segment "CODE"

.proc HAL_LoadTiles
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda #<tiles_filename
    sta API_PARAMETERS + 0
    lda #>tiles_filename
    sta API_PARAMETERS + 1
    lda #$FF
    sta API_PARAMETERS + 2
    sta API_PARAMETERS + 3

    lda #API_FN_LOAD_FILENAME
    sta API_FUNCTION
    lda #API_GROUP_FILEIO
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done
    rts
.endproc
