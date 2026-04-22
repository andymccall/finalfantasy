; ---------------------------------------------------------------------------
; map_test_shim.asm - Drive the verbatim DrawFullMap path + player mapman.
; ---------------------------------------------------------------------------
; After party-gen returns, EnterMapTest sets up the OW camera state
; (ow_scroll_x / ow_scroll_y / mapflags / facing), swaps in the OW tileset
; and palette, then calls DrawFullMap which paints the visible 16x15
; metatile window onto the host nametable.
;
; M2 camera model:
;   X16: player stays centred; camera scrolls smoothly (1 NES pixel per
;        frame) via VERA HSCROLL/VSCROLL (see HAL_SetCameraPixel). When
;        the sub-pixel offset wraps past a cell boundary, ow_scroll_x/y
;        advances by 1 NES tile and we repaint the full viewport.
;   Neo: screen-flip equivalent; no sub-pixel scroll. Cell-step cadence
;        gated by MOVE_PERIOD frames so walking doesn't blur on frame.
;        The straddle-aware ppu_flush now renders NT0/NT1 correctly,
;        so we step ow_scroll_x by 1 (not 32 as in M1) per cell.
;
; Milestone scope:
;   M1 (prior)          : joypad -> cell movement + full-viewport repaint,
;                         horizontal locked to 32-cell hops.
;   M2 (this shim)      : X16 sub-pixel smooth scroll; Neo 1-cell steps.
;   M3 (collision)      : read OW tileset terrain bits, block walls/water.
; ---------------------------------------------------------------------------

.import HAL_WaitVblank
.import HAL_LoadTileset
.import HAL_SetTileMode
.import HAL_APU_4014_Write
.import HAL_SetCameraPixel

.import cur_pal
.import DrawPalette
.import ClearNT

.import LoadOWTilesetData
.import load_map_pal

.import DrawFullMap
.import DrawPlayerMapmanSprite
.import ClearOAM
.import HAL_PollJoy

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

; NES joypad direction bits (NES layout produced by HAL_PollJoy):
;   $01 Right  $02 Left  $04 Down  $08 Up
JOY_R = $01
JOY_L = $02
JOY_D = $04
JOY_U = $08
JOY_DIR_MASK = JOY_R | JOY_L | JOY_D | JOY_U

; Movement model: advance sub_px by 1 per held-direction frame. When
; sub_px wraps past 16 (= 1 NES tile = half a metatile), commit a cell
; step (ow_scroll_* += 1) and repaint via DrawFullMap. That gives
; 16 frames per NES-tile = 32 frames per metatile at the native 60 Hz,
; a reasonable walking pace that also matches FF1's move_speed=1.
;
; X16 uses sub_px to drive VERA HSCROLL/VSCROLL for in-cell smoothness;
; Neo's HAL_SetCameraPixel is a no-op, so Neo players see a cell-step
; every 16 frames (~4 cells/sec horizontal, same vertical).
CELL_PIXELS = 16

.segment "BSS"

held_dir:  .res 1                           ; cached HAL_PollJoy direction bits
sub_px_x:  .res 1                           ; 0..15 sub-cell X offset
sub_px_y:  .res 1                           ; 0..15 sub-cell Y offset

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
    stz sub_px_x
    stz sub_px_y

@frame:
    jsr HAL_WaitVblank

    inc framecounter
    bne :+
    inc framecounter + 1
:
    inc move_ctr_x                          ; walk-cycle animator

    ; --- poll raw controller (HAL_PollJoy, not UpdateJoy: the NES engine's
    ; edge-detection clobbers `joy` on held directions).
    jsr HAL_PollJoy
    and #JOY_DIR_MASK
    sta held_dir                            ; 0 if no direction held

    ; --- horizontal axis --------------------------------------------------
    ; Priority: horizontal wins if both axes are pressed. Each branch sets
    ; `facing` to a single bit (matching FF1's facing encoding) and advances
    ; sub_px_x by 1. When sub_px_x wraps past $10 (= one NES tile), commit
    ; a cell step (ow_scroll_x +/- 1) and repaint via a shared tail.
    lda held_dir
    and #JOY_R
    beq @chk_left
      lda #JOY_R
      sta facing
      inc sub_px_x
      lda sub_px_x
      cmp #CELL_PIXELS
      bcc @h_done
        stz sub_px_x
        inc ow_scroll_x
        bra @repaint_h
@chk_left:
    lda held_dir
    and #JOY_L
    beq @h_done
      lda #JOY_L
      sta facing
      dec sub_px_x
      bpl @h_done                           ; wrapped to $FF if N set
        lda #CELL_PIXELS - 1
        sta sub_px_x
        dec ow_scroll_x
@repaint_h:
    jsr repaint_viewport
@h_done:

    ; --- vertical axis ----------------------------------------------------
    lda held_dir
    and #JOY_D
    beq @chk_up
      lda #JOY_D
      sta facing
      inc sub_px_y
      lda sub_px_y
      cmp #CELL_PIXELS
      bcc @v_done
        stz sub_px_y
        inc ow_scroll_y
        bra @repaint_v
@chk_up:
    lda held_dir
    and #JOY_U
    beq @v_done
      lda #JOY_U
      sta facing
      dec sub_px_y
      bpl @v_done                           ; wrapped to $FF if N set
        lda #CELL_PIXELS - 1
        sta sub_px_y
        dec ow_scroll_y
@repaint_v:
    jsr repaint_viewport
@v_done:

    ; --- push sub-pixel camera offset to HAL (X16 writes HSCROLL/VSCROLL;
    ; Neo is a no-op) --------------------------------------------------------
    lda sub_px_x
    ldx sub_px_y
    jsr HAL_SetCameraPixel

@draw:
    jsr ClearOAM
    lda vehicle
    tay
    jsr DrawPlayerMapmanSprite

    lda #$02
    jsr HAL_APU_4014_Write

    jmp @frame

; repaint_viewport ----------------------------------------------------------
; After a cell-step updates ow_scroll_x/y, wipe the NT mirror (so Neo's
; per-row dirty gate actually repaints) and re-run DrawFullMap to paint
; the 16x15 window at the new origin.
repaint_viewport:
    jsr ClearNT
    jsr DrawFullMap
    rts
