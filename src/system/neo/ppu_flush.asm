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
; Per-flush clear (Set Color + Set Solid + Draw Rectangle):
;   Draw Image's inner loop leaves pixelXor/pixelAnd in whatever state
;   the last drawn pixel required, so we re-seed pixelXor=0 and
;   useSolidFill=1 at the start of every flush, then issue one Draw
;   Rectangle to paint the whole NES viewport black. Three API calls
;   per frame vs. hundreds of per-cell rectangles, and no dedicated
;   blank tile (which would cost one of our 128 tile slots).
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

.segment "BSS"

flush_row: .res 1
flush_col: .res 1

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

    ; --- Per-flush clear: paint the 256x240 NES viewport black. -----------
    ; Draw Image leaves pixelXor/pixelAnd in an arbitrary state, so we
    ; re-seed colour + solid-fill before every frame's rectangle.
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

    lda #1
    sta API_PARAMETERS + 0              ; solidFill = 1 for the clear rect
    lda #API_FN_SET_SOLID
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_solid_done:
    lda API_COMMAND
    bne @wait_solid_done

    ; Rectangle (GUTTER_X, 0) .. (VIEWPORT_RIGHT, VIEWPORT_BOTTOM).
    ; X1 = 32
    lda #<GUTTER_X
    sta API_PARAMETERS + 0
    stz API_PARAMETERS + 1
    ; Y1 = 0
    stz API_PARAMETERS + 2
    stz API_PARAMETERS + 3
    ; X2 = 287 ($011F)
    lda #<VIEWPORT_RIGHT
    sta API_PARAMETERS + 4
    lda #>VIEWPORT_RIGHT
    sta API_PARAMETERS + 5
    ; Y2 = 239
    lda #VIEWPORT_BOTTOM
    sta API_PARAMETERS + 6
    stz API_PARAMETERS + 7
    lda #API_FN_RECTANGLE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_rect_done:
    lda API_COMMAND
    bne @wait_rect_done

    ; Switch solidFill back to 0 for Draw Image: each font tile has the
    ; NES 8x8 in the upper-left of a 16x16 image with nibble-0 transparent
    ; quadrants. With solidFill=1 those transparent quadrants would paint
    ; black over the upper-left 8x8 of the neighbouring cells, eating the
    ; top half of the capitals whose row is drawn after row-above's nibble-0
    ; lower quadrant. solidFill=0 skips nibble-0 pixels so neighbours keep
    ; their glyphs; the per-flush rectangle above has already cleared to
    ; black, so the nibble-0 quadrants simply "show through" to black.
@wait_solid0:
    lda API_COMMAND
    bne @wait_solid0
    stz API_PARAMETERS + 0              ; solidFill = 0
    lda #API_FN_SET_SOLID
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_solid0_done:
    lda API_COMMAND
    bne @wait_solid0_done

    stz flush_row
@row_loop:
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
    bcc @row_ready
    inc flush_ptr + 1

@row_ready:
    stz flush_col
    ldy #0
@col_loop:
    lda (flush_ptr), y

    cmp #FF1_FONT_BASE
    bcc @skip_cell                      ; < $80 : blank (ClearNT sentinel)
    sec
    sbc #FF1_FONT_BASE                  ; tile id = byte - $80 (range $00..$7F)

    pha                                 ; stash tile id across API setup

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
    lda #1
    sta API_PARAMETERS + 7              ; solidFill = 1 (paint nibble 0 too)

    lda #API_FN_DRAW_IMAGE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND
@wait_draw:
    lda API_COMMAND
    bne @wait_draw

@skip_cell:
    iny
    inc flush_col
    lda flush_col
    cmp #NT_COLS
    bne @col_loop

    inc flush_row
    lda flush_row
    cmp #NT_ROWS
    beq @done
    jmp @row_loop
@done:
@skip_all:
    rts
.endproc
