; ---------------------------------------------------------------------------
; tileset.asm - Neo6502 HAL_LoadTileset + HAL_SetTileMode.
; ---------------------------------------------------------------------------
; Neo's gfxObjectMemory only has 128 16x16 tile slots total, so the font
; and map tilesets can't coexist -- HAL_LoadTileset swaps the resident
; file at runtime. The .gfx files are built by scripts/chr_to_neo_gfx.py
; and must be present on the Neo storage (Makefile `run-neo` stages them).
;
; Tileset id -> filename:
;   0  tiles_font.gfx   menu/font + cursor sprite (loaded at boot)
;   1  tiles_ow.gfx     overworld BG tiles + cursor sprite
;
; Each file carries the cursor sprite in its sprite section so the cursor
; image survives every swap.
;
; HAL_SetTileMode stashes the mode byte for ppu_flush to read. Mode 0
; (menu) preserves today's behaviour. Mode 1 (map) flips the nametable
; -> tile-id mapping and disables the attribute-group gating used by the
; intro-story fade.
; ---------------------------------------------------------------------------

.export HAL_LoadTileset
.export HAL_SetTileMode
.export tile_mode

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_FILEIO     = $03
API_FN_LOAD_FILENAME = $02

.segment "RODATA"

fname_font:
    .byte 14
    .byte "tiles_font.gfx"

fname_ow:
    .byte 12
    .byte "tiles_ow.gfx"

; Filename pointer table indexed by tileset id (2 bytes per entry).
fname_tbl:
    .word fname_font                    ; id 0
    .word fname_ow                      ; id 1

.segment "BSS"

tile_mode: .res 1                       ; 0 = menu, 1 = map

.segment "CODE"

; HAL_LoadTileset -----------------------------------------------------------
; A = tileset id. Looks up the filename, fires a Load File call into
; gfxObjectMemory ($FFFF target), waits for completion. The cursor sprite
; inside the loaded .gfx overwrites whatever cursor was there previously
; (identical bytes in both files, so no visible change).
.proc HAL_LoadTileset
    asl                                 ; id * 2 -> table index
    tax

@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda fname_tbl, x
    sta API_PARAMETERS + 0
    lda fname_tbl + 1, x
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

; HAL_SetTileMode -----------------------------------------------------------
; A = 0 (menu) or 1 (map). Stashed for ppu_flush to consult.
.proc HAL_SetTileMode
    sta tile_mode
    rts
.endproc
