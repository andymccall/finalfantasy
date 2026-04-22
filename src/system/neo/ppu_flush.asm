; ---------------------------------------------------------------------------
; ppu_flush.asm - Neo6502 HAL_FlushNametable implementation.
; ---------------------------------------------------------------------------
; Walks the 32x30 visible region of the nametable mirror and paints every
; cell via Group $05 Function $07 "Draw Image" onto the graphics plane.
;
; Nametable byte mapping (matches FF1DA bank_0F.asm ClearNT,
; bank_0E.asm IntroTitlePrepare, bank_0E.asm EnterIntroStory):
;   $80..$FF : font / border tile. We issue Draw Image with image id =
;              (byte - $80), mapping to Neo tile ids $00..$7F packed
;              by chr_to_neo_gfx.py.
;   $00..$7F : cleared / background. FF1's ClearNT fills the entire
;              nametable with $00; on the NES that displays pattern
;              tile 0 (all pixel 0). Per-cell we skip these, but before
;              walking the grid we paint a single black rectangle over
;              the 256x240 viewport (see "per-flush clear" below), so
;              skipping = "black". This fixes the story->menu
;              transition where stale glyphs from the previous frame
;              would otherwise linger under the $00 cells.
;
; Attribute-group gating: Neo runs a flat 4-colour palette so it can't
; carry per-cell palette groups the way the NES does. To approximate
; FF1's intro-story fade (which reveals text row-by-row by flipping
; attribute metatiles from group 1 -> group 2 -> group 3), we gate tile
; drawing on the cell's current attribute group: group 3 draws, groups
; 0/1/2 skip (fall through to the black pre-clear). Group 2 is the
; "currently animating" row and we DO want to see it mid-fade, so we
; treat it as drawable too; the foreground colour is driven by
; HAL_PalettePush hooking writes to NES $3F0B, giving us the grey-to-
; white cycle. Groups 0 and 1 stay hidden. When FF1 eventually locks
; the block to %11111111 (all group 3), the row renders at its final
; colour and stays there.
;
; Exception: NES tile $FF is the "blue fill" background tile (every
; pixel = nibble 2 = blue). On the NES it sits under the fading text
; and is always visible (its colour index 2 is the same blue in every
; palette group, so the attribute group doesn't change what it looks
; like). We carve out a fast-path before the attr-group gate so tile
; $FF always draws -- without it the whole screen stays black until
; the text fade, instead of showing the blue curtain from the start.
;
; Attribute byte -> group lookup. Each attribute byte covers a 4x4-cell
; region and carries 4 two-bit groups packed as:
;
;   bit  7 6 5 4 3 2 1 0
;       [BR][BL][TR][TL]
;
; For cell (row, col) the group is (attr >> shift) & 3, with shift
; computed as ((row & 2) << 1) | (col & 2):
;
;   (row&2, col&2) -> shift
;     (0,  0)      -> 0   top-left quadrant
;     (0,  2)      -> 2   top-right quadrant
;     (2,  0)      -> 4   bottom-left quadrant
;     (2,  2)      -> 6   bottom-right quadrant
;
; The attr byte itself is at ppu_nt_mirror + $3C0 + (row>>2)*8 + (col>>2).
;
; Per-row dirty gating + per-row strip clear:
;   ppu.asm marks row_dirty[row] whenever a $2007 write actually changes
;   a tile or attr byte in that NT row (attr writes mark all 4 rows of
;   the metatile). Here we iterate rows 0..29 and skip cleanly past any
;   row whose dirty bit is zero. For dirty rows we paint a 256x8 black
;   strip to wipe the previous frame's content, then paint every cell.
;   The flag is cleared when the row is painted.
;
;   Clean rows keep whatever pixels they had last frame -- which is
;   exactly what we want, since those pixels are still the correct
;   steady-state image. The old "one 256x240 black rectangle per frame"
;   approach forced every row to be repainted and caused the already-
;   rendered text to flicker whenever a new fade row made the nametable
;   dirty.
;
; Draw Image parameters (Group $05, Function $07):
;   P0/P1  X coord (16-bit, screen pixels)
;   P2/P3  Y coord (16-bit)
;   P4     image id (0..127 = 16x16 tile)
;   P5     scale
;   P6     flip
;   P7     solid-fill flag (1 = paint transparent pixels too)
;
; Draw Image with solidFill=1 writes every pixel (including nibble 0),
; so each cell paint fully overwrites the prior low-nibble content in
; that cell's 8x8 region. GFXPlotPixel masks pixelAnd with 0xF0 when
; sprites are in use, so sprite pixels (high nibble) survive through
; solid-fill tile writes unchanged.
;
; Screen layout: Neo graphics plane is 320x240. We centre the 32-wide
; (256 px) nametable with a 32-pixel horizontal gutter (0-pixel vertical
; offset). Each NES 8x8 tile lives in the upper-left 8x8 of a 16x16 Neo
; image; at scale=1, neighbouring cells' transparent quadrants don't
; overpaint each other's glyphs because paint order is left-to-right,
; top-to-bottom and later paints win on the overlap.
; ---------------------------------------------------------------------------

.import ppu_nt_mirror
.import nt_dirty
.import row_dirty

.export HAL_FlushNametable

ControlPort         = $FF00
API_COMMAND         = ControlPort + 0
API_FUNCTION        = ControlPort + 1
API_PARAMETERS      = ControlPort + 4

API_GROUP_GRAPHICS  = $05
API_FN_DRAW_IMAGE   = $07
API_FN_RECTANGLE    = $03
API_FN_SET_COLOR    = $40
API_FN_SET_SOLID    = $41

NT_COLS             = 32
NT_ROWS             = 30
GUTTER_X            = 32                ; (320 - 256) / 2
VIEWPORT_RIGHT      = GUTTER_X + 255    ; 287 (inclusive right edge)
VIEWPORT_BOTTOM     = 239               ; inclusive bottom edge
FF1_FONT_BASE       = $80               ; nametable bytes $80..$FF map to tile ids $00..$7F

.segment "ZEROPAGE"

flush_ptr: .res 2
attr_ptr:  .res 2

.segment "BSS"

flush_row:       .res 1
flush_col:       .res 1
flush_row_shift: .res 1                 ; (row & 2) << 1: 0 or 4

.segment "CODE"

.proc HAL_FlushNametable
    ; --- Short-circuit on clean mirror --------------------------------------
    ; FF1 often leaves the nametable untouched for many frames (e.g. during
    ; the intro-story palette fade, where only palette RAM ticks). Repainting
    ; a static grid every vblank can't complete inside one Neo frame budget,
    ; so the scanout catches a half-painted graphics plane -- visible flicker.
    ; ppu.asm sets nt_dirty on every $2007 nametable write; we paint only
    ; when something has actually changed, and clear the flag at the end.
    lda nt_dirty
    bne @do_flush
    jmp @skip_all
@do_flush:
    stz nt_dirty

    stz flush_row
@row_loop:
    ; --- per-row dirty gate ------------------------------------------------
    ; Skip rows that haven't changed since the last flush. ppu.asm marks
    ; row_dirty[row] on every tile/attr byte write that actually changes
    ; the mirror. Repainting only dirty rows cuts the flush from 960 cells
    ; to ~32 per animated row, which in turn removes the flicker on the
    ; already-rendered rows that used to be overpainted every frame.
    ldx flush_row
    lda row_dirty, x
    bne @row_is_dirty
    jmp @next_row                       ; long jump: body exceeds branch range
@row_is_dirty:
    stz row_dirty, x

    ; --- Per-row black strip clear -----------------------------------------
    ; This row is dirty: paint a 256x8 black rectangle to wipe the previous
    ; frame's contents so glyphs that vanished (e.g. DTE replacement, scroll)
    ; don't leave residue. Draw Image mutates pixelXor per tile pixel, so
    ; we must re-seed Set Color to 0 every row before the rect, or the
    ; strip paints with whatever the last tile pixel left in pixelXor.
    ; We also use solidFill=1 for the strip so every pixel lands, then
    ; switch back to solidFill=0 before Draw Image so the tile's
    ; transparent nibble-0 quadrants don't paint over neighbouring cells.
@wait_color:
    lda API_COMMAND
    bne @wait_color
    stz API_PARAMETERS + 0              ; colour index 0 = black
    lda #API_FN_SET_COLOR
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_color_done:
    lda API_COMMAND
    bne @wait_color_done

@wait_solid1:
    lda API_COMMAND
    bne @wait_solid1
    lda #1
    sta API_PARAMETERS + 0              ; solidFill = 1
    lda #API_FN_SET_SOLID
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_solid1_done:
    lda API_COMMAND
    bne @wait_solid1_done

    ; X1 = GUTTER_X (32)
    lda #<GUTTER_X
    sta API_PARAMETERS + 0
    stz API_PARAMETERS + 1
    ; Y1 = row * 8 (0..232, fits one byte)
    lda flush_row
    asl
    asl
    asl
    sta API_PARAMETERS + 2
    stz API_PARAMETERS + 3
    ; X2 = VIEWPORT_RIGHT (287)
    lda #<VIEWPORT_RIGHT
    sta API_PARAMETERS + 4
    lda #>VIEWPORT_RIGHT
    sta API_PARAMETERS + 5
    ; Y2 = row * 8 + 7
    lda flush_row
    asl
    asl
    asl
    clc
    adc #7
    sta API_PARAMETERS + 6
    stz API_PARAMETERS + 7
    lda #API_FN_RECTANGLE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_rect_done:
    lda API_COMMAND
    bne @wait_rect_done

    ; solidFill back to 0 before Draw Image.
@wait_solid0:
    lda API_COMMAND
    bne @wait_solid0
    stz API_PARAMETERS + 0
    lda #API_FN_SET_SOLID
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_solid0_done:
    lda API_COMMAND
    bne @wait_solid0_done

@paint_row:
    ; --- flush_ptr = ppu_nt_mirror + row * 32 -------------------------------
    lda flush_row
    lsr
    lsr
    lsr                                 ; row >> 3 = high byte of row*32
    clc
    adc #>ppu_nt_mirror
    sta flush_ptr + 1
    lda flush_row
    asl
    asl
    asl
    asl
    asl                                 ; row << 5 = low byte of row*32
    clc
    adc #<ppu_nt_mirror
    sta flush_ptr + 0
    bcc @attr_setup
    inc flush_ptr + 1

@attr_setup:
    ; --- attr_ptr = ppu_nt_mirror + $3C0 + (row >> 2) * 8 -------------------
    ; The attribute table sits in the last 64 bytes of each nametable.
    ; (row >> 2) * 8 walks the 8-byte rows of attribute bytes; (col >> 2)
    ; will index within the row once we're in @col_loop.
    lda flush_row
    lsr
    lsr                                 ; row >> 2 (0..7)
    asl
    asl
    asl                                 ; * 8 (0..56, fits in one byte)
    clc
    adc #<(ppu_nt_mirror + $3C0)
    sta attr_ptr + 0
    lda #>(ppu_nt_mirror + $3C0)
    adc #0                              ; pick up any carry
    sta attr_ptr + 1

    ; --- flush_row_shift = (row & 2) << 1 -----------------------------------
    ; Base shift for "top vs bottom half" of the 4x4 attribute metatile.
    ; Per-cell we OR in (col & 2) to reach the final 0/2/4/6 shift count.
    lda flush_row
    and #$02
    asl
    sta flush_row_shift

    stz flush_col
    ldy #0
@col_loop:
    lda (flush_ptr), y

    cmp #FF1_FONT_BASE
    bcc @skip_cell                      ; < $80 : blank (ClearNT sentinel)
    sec
    sbc #FF1_FONT_BASE                  ; tile id = byte - $80 (range $00..$7F)

    pha                                 ; stash tile id across API setup

    ; --- blue-fill fast path: NES tile $FF (Neo id $7F) bypasses the gate --
    ; It's the background fill whose pixels are all nibble 2 (blue) in every
    ; NES palette group, so it should always be visible.
    cmp #$7F
    beq @draw_tile

    ; --- attribute-group gate ----------------------------------------------
    ; Look up this cell's NES attribute group (0..3). Skip rendering unless
    ; the group is 2 (animating) or 3 (fully faded in). See file header for
    ; the attr byte layout and shift derivation.
    phy                                 ; save NT column index (Y)
    lda flush_col
    lsr
    lsr                                 ; col >> 2 (0..7)
    tay
    lda (attr_ptr), y                   ; attr byte covering this cell
    ply                                 ; restore Y

    ; compute shift = flush_row_shift | (col & 2)
    pha                                 ; save attr byte under tile id
    lda flush_col
    and #$02
    ora flush_row_shift
    tax                                 ; X = shift count (0/2/4/6)
    pla                                 ; attr byte back in A
@attr_shift_loop:
    cpx #0
    beq @attr_shift_done
    lsr
    lsr
    dex
    dex
    bra @attr_shift_loop
@attr_shift_done:
    and #$03                            ; group 0..3
    cmp #$01
    bne @draw_tile                      ; groups 0/2/3: draw as-is
    ; group 1: the intro-story "faded-out / invisible" palette. Swap in
    ; the blue-fill tile so the text-to-be stays hidden under the curtain
    ; until it fades. Group 0 is a legitimate visible palette on the
    ; party-gen / name-input screens (the NES uses it to tint the top
    ; box orange); we can't reproduce the tint on Neo but we must still
    ; draw the border / text glyphs.
    pla                                 ; drop real tile id
    lda #$7F                            ; Neo id for NES tile $FF
    pha
@draw_tile:

    ; --- Draw Image at (GUTTER_X + col*8, row*8) ----------------------------
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    ; P0/P1 = X (16-bit). X = GUTTER_X + col*8. col<=31 so col*8<=248,
    ; + 32 = 280 -> two bytes needed.
    lda flush_col
    asl
    asl
    asl                                 ; col*8 (0..248)
    clc
    adc #GUTTER_X
    sta API_PARAMETERS + 0
    lda #0
    adc #0                              ; pick up carry into high byte
    sta API_PARAMETERS + 1

    ; P2/P3 = Y = row*8 (0..232, fits in one byte).
    lda flush_row
    asl
    asl
    asl
    sta API_PARAMETERS + 2
    stz API_PARAMETERS + 3

    pla
    sta API_PARAMETERS + 4              ; image id
    lda #1
    sta API_PARAMETERS + 5              ; scale = 1
    stz API_PARAMETERS + 6              ; no flip
    stz API_PARAMETERS + 7              ; solidFill = 0: skip nibble-0 pixels
                                        ; so the transparent lower-half of
                                        ; the 16x16 image doesn't paint
                                        ; black over the next NT row's
                                        ; glyphs (which may be clean and
                                        ; never repainted this frame).

    lda #API_FN_DRAW_IMAGE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_draw:
    lda API_COMMAND
    bne @wait_draw
    bra @skip_cell

@skip_tile_draw:
    pla                                 ; discard stashed tile id
@skip_cell:
    iny
    inc flush_col
    lda flush_col
    cmp #NT_COLS
    beq @col_done
    jmp @col_loop                       ; long jump: body exceeds -128 branch range
@col_done:
@next_row:
    inc flush_row
    lda flush_row
    cmp #NT_ROWS
    beq @done
    jmp @row_loop
@done:
@skip_all:
    rts
.endproc
