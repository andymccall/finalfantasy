; ---------------------------------------------------------------------------
; map_test_shim.asm - Drive the verbatim DrawFullMap path.
; ---------------------------------------------------------------------------
; After party-gen returns, EnterMapTest sets up the OW camera state
; (ow_scroll_x / ow_scroll_y / mapflags / facing), swaps in the OW tileset
; and palette, then calls DrawFullMap which paints the visible 16x15
; metatile window onto the host nametable via StartMapMove -> PrepRowCol
; -> DrawMapRowCol -> PrepAttributePos -> DrawMapAttributes -> ScrollUpOneRow.
;
; The palette copy is pushed AFTER DrawFullMap so the palette swap lands on
; the same flush as the freshly-painted NT, avoiding the one-frame
; orange-text-on-green flash we saw on both platforms.
; ---------------------------------------------------------------------------

.import HAL_WaitVblank
.import HAL_LoadTileset
.import HAL_SetTileMode

.import cur_pal
.import DrawPalette
.import ClearNT

.import LoadOWTilesetData
.import load_map_pal

.import DrawFullMap
.import mapflags, mapdraw_job, facing, move_speed, vehicle, cur_map
.import ow_scroll_x, ow_scroll_y

.export EnterMapTest

; --- Map viewport origin --------------------------------------------------
; DrawFullMap paints the 16x15 metatile window whose top-left is at
; (ow_scroll_x, ow_scroll_y + 15 - 15) = (ow_scroll_x, ow_scroll_y).
; Coneria sits near (col 152, row 164); these values place it roughly
; centred in the visible window.
MAP_START_ROW = 150
MAP_START_COL = 128

.segment "CODE"

EnterMapTest:
    ; --- swap in the OW tileset -------------------------------------------
    lda #1                                  ; tileset id 1 = tiles_ow.gfx
    jsr HAL_LoadTileset
    lda #1                                  ; tile mode 1 = map
    jsr HAL_SetTileMode

    ; --- populate tsa_ul/ur/dl/dr/attr + load_map_pal from the RODATA blob
    jsr LoadOWTilesetData

    ; --- wipe the NT mirror so Neo's per-row dirty gate repaints every cell
    jsr ClearNT

    ; --- seed OW camera state ---------------------------------------------
    stz mapflags                            ; OW, row-draw
    lda #MAP_START_COL
    sta ow_scroll_x
    lda #MAP_START_ROW
    sta ow_scroll_y
    stz facing                              ; DrawFullMap seeds facing = $08 itself
    stz mapdraw_job
    stz move_speed
    stz vehicle                             ; on foot
    stz cur_map

    ; --- paint the whole viewport via FF1's verbatim routine --------------
    jsr DrawFullMap

    ; --- push the OW palette *after* the NT writes have landed ------------
    ; Same reason as before: doing this earlier means the next vblank
    ; paints cur_pal (green grass colours) while the NT mirror still holds
    ; the party-gen box tiles, so the user sees one frame of orange text
    ; on green before the map appears.
    ldx #15
@pal_copy:
    lda load_map_pal, x
    sta cur_pal, x
    dex
    bpl @pal_copy
    jsr DrawPalette

@spin:
    jsr HAL_WaitVblank
    bra @spin
