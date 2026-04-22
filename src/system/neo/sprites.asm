; ---------------------------------------------------------------------------
; sprites.asm - Neo6502 HAL sprite plane (cursor + player mapman).
; ---------------------------------------------------------------------------
; FF1 builds sprite OAM in a page-aligned RAM buffer, then writes that
; buffer's page number to $4014 (OAMDMA). Our NES-port shim traps the
; $4014 write and tail-calls HAL_OAMFlush.
;
; Slot plan (Neo side, fixed):
;   Neo sprite 0 = cursor  (first 16x16 sprite image in tiles_*.gfx)
;   Neo sprite 1 = mapman  (one of 8 Fighter poses, baked into gfx)
;
; The NES doesn't reserve specific OAM slots for cursor vs mapman --
; whoever draws first takes oam[0..15] (via sprindex starting at 0)
; and the next caller gets [16..31], etc. So we can't key on a fixed
; OAM offset. Instead we walk OAM in 4-byte records, look at the UL
; tile ID to classify each block:
;
;     tile in $F0..$F3 -> cursor block (UL, DL, UR, DR of cursor)
;     tile in $00..$0F -> mapman block
;
; and drive the matching Neo sprite slot from that block's UL entry.
; Each 2x2 block eats 16 oam bytes (4 entries); we advance by 16 so
; DL/UR/DR get skipped once UL is classified. Y >= $EF at UL hides
; the whole block (FF1's $F8 sentinel).
;
; Mapman pose decode -- same key as on X16: UL tile uniquely picks
; R0/R1/L0/L1, and U0/U1 + D0/D1 are disambiguated by DR attr bit 6
; (the frame-1 variants H-flip their DR quadrant).
;
;     UL=$09 -> R0   UL=$0D -> R1
;     UL=$08 -> L0   UL=$0C -> L1
;     UL=$04 + DR_attr.6=0 -> U0;   =1 -> U1
;     UL=$00 + DR_attr.6=0 -> D0;   =1 -> D1
;
; Neo sprite image indices: cursor = 0, mapman poses = 1..8.
;
; Coord math: the 32x30 NES viewport sits inside the 320x240 plane
; with a 32-pixel horizontal gutter (see ppu_flush.asm). NES sprite Y
; stores (display_y - 1), so draw-Y = NES Y + 1.
;
; Hidden-slot tracking: within one flush we want to know whether the
; cursor or mapman slot was actually written (so we can hide the
; other). Two BSS flags (cursor_drawn, mapman_drawn) are cleared at
; the top of HAL_OAMFlush and set by the matching draw path. If a
; flag is still clear at the end, we issue Sprite Hide for that slot.
; ---------------------------------------------------------------------------

.import oam

.export HAL_SpritesInit
.export HAL_OAMFlush

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_SPRITES    = $06
API_FN_SPRITE_SET    = $02
API_FN_SPRITE_HIDE   = $03

CURSOR_SPRITE_NUM    = 0
MAPMAN_SPRITE_NUM    = 1
CURSOR_IMAGE_IDX     = 0
MAPMAN_IMAGE_BASE    = 1

GUTTER_X             = 32               ; must match ppu_flush.asm

; How many 4-byte OAM records to scan per flush. 8 blocks = 32 sprites
; worth, plenty for title screen (4 cursor) + map (4 mapman). Bump if
; a future screen draws a lot more.
OAM_RECORDS_WALKED   = 32

.segment "BSS"

cursor_drawn: .res 1
mapman_drawn: .res 1

.segment "CODE"

; HAL_SpritesInit -----------------------------------------------------------
; Cursor + mapman images are packed into tiles_ow.gfx (map mode) and
; tiles_font.gfx (font mode, cursor only) and loaded by HAL_LoadTileset.
; Nothing else to stage here; kept as a no-op so hal.asm's explicit JSR
; stays valid.
.proc HAL_SpritesInit
    rts
.endproc

; HAL_OAMFlush --------------------------------------------------------------
; Walk OAM records, dispatching each block to the matching Neo slot.
; After the walk, hide any slot that wasn't drawn this frame.
.proc HAL_OAMFlush
    stz cursor_drawn
    stz mapman_drawn

    ldx #0                              ; X = record index (0..OAM_RECORDS_WALKED-1)
@walk:
    txa
    asl
    asl                                 ; Y offset = X * 4
    tay

    lda oam, y                          ; UL Y coord
    cmp #$EF
    bcs @next_record                    ; hidden sprite -> skip

    iny                                 ; oam+1 = UL tile
    lda oam, y
    cmp #$F0
    bcc @maybe_mapman
      cmp #$F4
      bcs @next_record                  ; $F4+ not recognised
      ; cursor block (tile $F0..$F3). Emit sprite 0 once, then skip
      ; the remaining 3 sprites in this 2x2 block.
      lda cursor_drawn
      bne @skip_block                   ; already drawn once this frame
      dey                               ; back to UL Y
      jsr emit_cursor
      lda #1
      sta cursor_drawn
      bra @skip_block

@maybe_mapman:
    cmp #$10
    bcs @next_record                    ; tile >= $10 -> unknown; skip
    ; mapman block (tile $00..$0F).
    lda mapman_drawn
    bne @skip_block
    dey                                 ; back to UL Y
    jsr emit_mapman
    lda #1
    sta mapman_drawn
    ; fall through to skip-block

@skip_block:
    ; Each 2x2 block spans 4 OAM records. We already consumed this one,
    ; so advance X by 3 more (the @next_record inx below makes 4 total).
    inx
    inx
    inx

@next_record:
    inx
    cpx #OAM_RECORDS_WALKED
    bcc @walk

    ; --- hide any slot that wasn't written this frame ----------------------
    lda cursor_drawn
    bne :+
      lda #CURSOR_SPRITE_NUM
      jsr hide_sprite
:   lda mapman_drawn
    bne :+
      lda #MAPMAN_SPRITE_NUM
      jsr hide_sprite
:   rts
.endproc

; ---------------------------------------------------------------------------
; emit_cursor: Y indexes oam at UL Y. Push Sprite Set for slot 0.
; ---------------------------------------------------------------------------
.proc emit_cursor
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda #CURSOR_SPRITE_NUM
    sta API_PARAMETERS + 0

    iny
    iny
    iny                                 ; Y points at UL X (oam+3)
    lda oam, y
    clc
    adc #GUTTER_X
    sta API_PARAMETERS + 1
    lda #0
    adc #0
    sta API_PARAMETERS + 2

    dey
    dey
    dey                                 ; back to UL Y
    lda oam, y
    clc
    adc #1
    sta API_PARAMETERS + 3
    lda #0
    adc #0
    sta API_PARAMETERS + 4

    lda #CURSOR_IMAGE_IDX
    sta API_PARAMETERS + 5
    stz API_PARAMETERS + 6
    lda #7
    sta API_PARAMETERS + 7

    lda #API_FN_SPRITE_SET
    sta API_FUNCTION
    lda #API_GROUP_SPRITES
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done
    rts
.endproc

; ---------------------------------------------------------------------------
; emit_mapman: Y indexes oam at UL Y. Decode pose from UL tile and DR
; attr, push Sprite Set for slot 1.
; ---------------------------------------------------------------------------
.proc emit_mapman
    phy                                 ; save UL Y index -- decode_pose uses Y
    jsr decode_pose                     ; returns image idx in A, C=1 if known
    ply
    bcc @done                           ; unknown pose -> leave mapman hidden
    pha                                 ; save image idx

@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    lda #MAPMAN_SPRITE_NUM
    sta API_PARAMETERS + 0

    iny
    iny
    iny                                 ; oam+3 = UL X
    lda oam, y
    clc
    adc #GUTTER_X
    sta API_PARAMETERS + 1
    lda #0
    adc #0
    sta API_PARAMETERS + 2

    dey
    dey
    dey                                 ; UL Y
    lda oam, y
    clc
    adc #1
    sta API_PARAMETERS + 3
    lda #0
    adc #0
    sta API_PARAMETERS + 4

    pla
    sta API_PARAMETERS + 5              ; image idx
    stz API_PARAMETERS + 6              ; flip baked into pose images
    lda #7
    sta API_PARAMETERS + 7

    lda #API_FN_SPRITE_SET
    sta API_FUNCTION
    lda #API_GROUP_SPRITES
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done
@done:
    rts
.endproc

; ---------------------------------------------------------------------------
; decode_pose: Y points at mapman block UL-Y. Returns image idx in A,
; C=1 if known, C=0 if unknown.
; ---------------------------------------------------------------------------
.proc decode_pose
    iny                                 ; oam+1 = UL tile
    lda oam, y
    cmp #$09
    bne :+
      lda #MAPMAN_IMAGE_BASE + 0
      sec
      rts
:   cmp #$0D
    bne :+
      lda #MAPMAN_IMAGE_BASE + 1
      sec
      rts
:   cmp #$08
    bne :+
      lda #MAPMAN_IMAGE_BASE + 2
      sec
      rts
:   cmp #$0C
    bne :+
      lda #MAPMAN_IMAGE_BASE + 3
      sec
      rts
:   cmp #$04
    bne :+
      ; U0 / U1 disambig on DR attr. Y is at UL+1; DR attr = oam[UL+14],
      ; so we need +13 from here.
      tya
      clc
      adc #13
      tay
      lda oam, y
      and #$40
      beq @u0
        lda #MAPMAN_IMAGE_BASE + 5
        sec
        rts
@u0:  lda #MAPMAN_IMAGE_BASE + 4
      sec
      rts
:   cmp #$00
    bne :+
      tya
      clc
      adc #13
      tay
      lda oam, y
      and #$40
      beq @d0
        lda #MAPMAN_IMAGE_BASE + 7
        sec
        rts
@d0:  lda #MAPMAN_IMAGE_BASE + 6
      sec
      rts
:   clc                                 ; unknown pose
    rts
.endproc

; ---------------------------------------------------------------------------
; hide_sprite: A = Neo sprite slot to hide.
; ---------------------------------------------------------------------------
.proc hide_sprite
    pha
@wait_idle:
    lda API_COMMAND
    bne @wait_idle
    pla
    sta API_PARAMETERS + 0
    lda #API_FN_SPRITE_HIDE
    sta API_FUNCTION
    lda #API_GROUP_SPRITES
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done
    rts
.endproc
