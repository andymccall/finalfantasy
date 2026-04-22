; ---------------------------------------------------------------------------
; map_test_shim.asm - Drive the verbatim DrawFullMap path + player mapman.
; ---------------------------------------------------------------------------
; After party-gen returns, EnterMapTest sets up the OW camera state
; (ow_scroll_x / ow_scroll_y / mapflags / facing), swaps in the OW tileset
; and palette, then calls DrawFullMap which paints the visible 16x15
; metatile window onto the host nametable via StartMapMove -> PrepRowCol
; -> DrawMapRowCol -> PrepAttributePos -> DrawMapAttributes -> ScrollUpOneRow.
;
; Once the map is painted we enter a per-frame loop that:
;   - increments framecounter (drives animation on vehicles that need it);
;   - advances move_ctr_x so the walk-cycle LSB toggles every few frames;
;   - rotates `facing` so all four directions are exercised in turn;
;   - ClearOAM / DrawPlayerMapmanSprite / STA $4014 each vblank to push
;     the OAM buffer through HAL_OAMFlush -> VERA sprite attribute RAM.
;
; The palette copy runs AFTER DrawFullMap so the palette swap lands on
; the same flush as the freshly-painted NT, avoiding the one-frame
; orange-text-on-green flash we saw on both platforms. We copy all 32
; slots (BG + sprite halves of load_map_pal) so sprite palette 0/1 end
; up initialised before the first mapman draw.
; ---------------------------------------------------------------------------

.import HAL_WaitVblank
.import HAL_LoadTileset
.import HAL_SetTileMode
.import HAL_APU_4014_Write

.import cur_pal
.import DrawPalette
.import ClearNT

.import LoadOWTilesetData
.import load_map_pal

.import DrawFullMap
.import DrawPlayerMapmanSprite
.import ClearOAM

.import mapflags, mapdraw_job, facing, move_speed, vehicle, cur_map
.import ow_scroll_x, ow_scroll_y
.import move_ctr_x, move_ctr_y
.import framecounter

.export EnterMapTest

; --- Map viewport origin --------------------------------------------------
; DrawFullMap paints the 16x15 metatile window whose top-left is at
; (ow_scroll_x, ow_scroll_y + 15 - 15) = (ow_scroll_x, ow_scroll_y).
; Coneria sits near (col 152, row 164); these values place it roughly
; centred in the visible window.
MAP_START_ROW = 150
MAP_START_COL = 128

; Direction-rotation period, in frames. Every FACING_PERIOD frames we
; shift `facing` to the next direction (R -> L -> D -> U -> ...) so the
; walk cycle is visible in every direction without needing joypad input.
FACING_PERIOD = 64

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
    lda #1
    sta vehicle                             ; on foot (vehicle=1 takes the on-foot branch)
    stz cur_map

    ; --- paint the whole viewport via FF1's verbatim routine --------------
    jsr DrawFullMap

    ; --- push the full OW palette (BG + sprite halves) --------------------
    ; Same timing reason as before: pushing palette earlier means the next
    ; vblank paints cur_pal while the NT mirror still holds the party-gen
    ; box tiles, so the user sees one frame of orange text on green. We
    ; now copy 32 bytes (not 16) so NES sprite palette 0/1 are initialised
    ; before DrawPlayerMapmanSprite causes sprite attr rows to reference
    ; those VERA slots.
    ldx #31
@pal_copy:
    lda load_map_pal, x
    sta cur_pal, x
    dex
    bpl @pal_copy
    jsr DrawPalette

    ; --- seed mapman state -------------------------------------------------
    lda #$01                                ; facing = R, frame 0
    sta facing
    stz move_ctr_x
    stz move_ctr_y
    stz framecounter
    stz framecounter + 1

@frame:
    jsr HAL_WaitVblank

    ; Advance animation + facing rotation.
    inc framecounter
    bne :+
    inc framecounter + 1
:
    ; move_ctr_x ticks +1 per frame. DrawPlayerMapmanSprite tests bit 3,
    ; so toggling the LSB every frame isn't enough -- but a monotonically
    ; incrementing counter means bit 3 flips every 8 frames, which is
    ; exactly the NES walk-cycle cadence when `move_speed` is 1.
    inc move_ctr_x

    ; Rotate `facing` once every FACING_PERIOD frames. facing bits:
    ; 1=R, 2=L, 4=D, 8=U -- so the rotation sequence we want is
    ; $01, $02, $04, $08 (R, L, D, U), looping.
    lda framecounter
    and #(FACING_PERIOD - 1)                ; mod FACING_PERIOD (must be POT)
    bne @draw
    ; At each boundary, cycle facing through 1,2,4,8.
    lda facing
    asl
    cmp #$10
    bne :+
    lda #$01
:
    sta facing

@draw:
    jsr ClearOAM
    lda vehicle                             ; Y = current vehicle (for Draw2x2Vehicle path)
    tay
    jsr DrawPlayerMapmanSprite

    ; Trigger the OAMDMA hook -> HAL_OAMFlush.
    lda #$02                                ; any value; $4014 hook doesn't read it on host
    jsr HAL_APU_4014_Write

    bra @frame
