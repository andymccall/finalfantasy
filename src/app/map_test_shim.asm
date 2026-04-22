; ---------------------------------------------------------------------------
; map_test_shim.asm - Drive the verbatim DrawFullMap path + player mapman.
; ---------------------------------------------------------------------------
; After party-gen returns, EnterMapTest sets up the OW camera state
; (ow_scroll_x / ow_scroll_y / mapflags / facing), swaps in the OW tileset
; and palette, then calls DrawFullMap which paints the visible 16x15
; metatile window onto the host nametable.
;
; Per-frame loop:
;   - poll joypad;
;   - on a fresh directional press, set `facing` and step the camera by
;     one metatile cell (player stays centred), then repaint the whole
;     viewport via DrawFullMap. No tile collision yet -- every cell is
;     walkable. No smooth scroll on either target yet either;
;   - advance move_ctr_x (drives the mapman walk-cycle pic toggle);
;   - ClearOAM / DrawPlayerMapmanSprite / STA $4014 to push the sprite.
;
; Milestone scope:
;   M1 (this shim)      : joypad -> cell movement + full-viewport repaint.
;   M2 (camera)         : X16 smooth scroll; Neo screen-flip navigation.
;   M3 (collision)      : read OW tileset terrain bits, block walls/water.
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

; Movement cadence. One cell step per MOVE_PERIOD frames while a
; direction is held. Also the minimum gap between step repaints so
; DrawFullMap isn't called every vblank.
MOVE_PERIOD = 8

.segment "BSS"

held_dir: .res 1                            ; cached HAL_PollJoy direction bits

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

    inc framecounter
    bne :+
    inc framecounter + 1
:
    inc move_ctr_x                          ; walk-cycle animator

    ; Only consider stepping on MOVE_PERIOD boundaries. This gates both
    ; the frequency of DrawFullMap repaints and the player's OW speed.
    lda framecounter
    and #(MOVE_PERIOD - 1)
    bne @draw

    ; Read raw controller state. We deliberately skip UpdateJoy's
    ; edge-detection (ProcessJoyButtons clobbers `joy` so held
    ; directional bits only appear on the press edge), because we want
    ; held-to-walk auto-repeat gated by MOVE_PERIOD. The NES achieves
    ; held movement via the StartMapMove state machine re-triggering
    ; joy_ignore; we mimic it with a simple cadence gate instead.
    jsr HAL_PollJoy
    and #JOY_DIR_MASK
    beq @draw                               ; no direction held
    sta held_dir                            ; cache dir bits for step branches

    ; Priority: horizontal wins if both axes are pressed. Each branch
    ; sets `facing` to a single bit (matching FF1's facing encoding)
    ; and steps ow_scroll_x/y.
    ;
    ; Horizontal stepping constraint: FF1's DrawMapRowCol paints a 32-
    ; NES-tile-wide row into a 2-nametable ring, starting at NT column
    ; (ow_scroll_x & $1F). When that start column != 0, the row straddles
    ; NT0 + NT1. Our ppu_flush only reads NT0, so straddled rows render
    ; with stale cells (X16: black, Neo: repeated tile 0). Until M2 adds
    ; proper dual-NT flush handling, we keep ow_scroll_x aligned to
    ; 32-cell boundaries so every paint lands wholly in NT0. That means
    ; horizontal movement is 32-cell hops -- coarse but functional for
    ; exercising collision + encounters. Vertical is 1 cell per step
    ; (rows don't straddle vertically).
    lda held_dir
    and #JOY_R
    beq :+
      lda #JOY_R
      sta facing
      lda ow_scroll_x
      clc
      adc #$20
      sta ow_scroll_x
      bra @repaint
:   lda held_dir
    and #JOY_L
    beq :+
      lda #JOY_L
      sta facing
      lda ow_scroll_x
      sec
      sbc #$20
      sta ow_scroll_x
      bra @repaint
:   lda held_dir
    and #JOY_D
    beq :+
      lda #JOY_D
      sta facing
      inc ow_scroll_y
      bra @repaint
:   lda #JOY_U                              ; only Up left
    sta facing
    dec ow_scroll_y

@repaint:
    ; Wipe the NT mirror before repainting so any cells not touched by
    ; DrawFullMap (e.g. attribute-table padding, future partial-paint
    ; strategies) render as blank instead of retaining stale data.
    jsr ClearNT
    jsr DrawFullMap

@draw:
    jsr ClearOAM
    lda vehicle
    tay
    jsr DrawPlayerMapmanSprite

    lda #$02
    jsr HAL_APU_4014_Write

    bra @frame
