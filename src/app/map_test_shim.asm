; ---------------------------------------------------------------------------
; map_test_shim.asm - Overworld metatile preview harness.
; ---------------------------------------------------------------------------
; Decompresses 15 consecutive map rows starting at MAP_START_ROW and expands
; each via the tsa_ul/ur/dl/dr tables into the 2x2 NES-tile metatiles FF1
; renders. The result fills nametable rows 0..29 with a 16-metatile-wide
; (32 NES tiles) viewport, which is what the real overworld draws.
;
; Per-metatile attribute groups come from tsa_attr. FF1's attribute table
; packs four 2-bit groups per byte (covering a 4x4-cell = 2x2-metatile
; region); since tsa_attr values are uniform per metatile ($00/$55/$AA/$FF),
; we can just bundle two adjacent metatiles' top-half group bits into each
; attribute byte: bits 1:0 come from the left metatile, bits 3:2 from the
; right; the bottom-half bits repeat the same pattern for the NT-row pair.
;
; MAP_START_ROW / MAP_START_COL pick the map-space origin. Coneria sits
; around (col 152, row 164); nudging these lets us aim at landmarks to
; confirm the composition+palette path visually.
;
; Called from pty_gen_shim.asm's EnterNewGame after party-gen returns.
; Spins forever on HAL_WaitVblank; no input is read.
; ---------------------------------------------------------------------------

.import HAL_WaitVblank
.import HAL_LoadTileset
.import HAL_SetTileMode
.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write

.import cur_pal
.import DrawPalette
.import ClearNT

.import MapDecompressRow
.import map_row_buf

.import LoadOWTilesetData
.import tsa_ul, tsa_ur, tsa_dl, tsa_dr, tsa_attr
.import load_map_pal

.export EnterMapTest

; --- Map viewport origin ---------------------------------------------------
; 15 map rows x 16 map cols fills the 32x30 NT at 2x2 tiles per metatile.
MAP_START_ROW = 150
MAP_START_COL = 140

NT_COLS       = 32
NT_ROWS       = 30
MAP_WIDTH_TILES = 16            ; metatiles per row in the window

.segment "ZEROPAGE"

paint_row: .res 1                           ; which *metatile* row we're on (0..14)
paint_src: .res 1                           ; current map row being decompressed

.segment "CODE"

EnterMapTest:
    ; --- swap in the OW tileset --------------------------------------------
    lda #1                                  ; tileset id 1 = tiles_ow.gfx
    jsr HAL_LoadTileset
    lda #1                                  ; tile mode 1 = map
    jsr HAL_SetTileMode

    ; --- populate tsa_ul/ur/dl/dr/attr from the RODATA blob ----------------
    jsr LoadOWTilesetData

    ; --- wipe the NT mirror so Neo's per-row dirty gate repaints every cell
    jsr ClearNT

    ; --- paint 15 metatile rows * 16 metatiles = 240 metatiles --------------
    stz paint_row
    lda #MAP_START_ROW
    sta paint_src

@meta_row_loop:
    ; decompress map row into map_row_buf (256 tiles, we sample 16 of them)
    lda paint_src
    jsr MapDecompressRow

    ; --- write the top NT row (UL/UR halves of each metatile) --------------
    lda paint_row                           ; NT row = meta_row * 2
    asl
    jsr set_ppu_addr_to_nt_row

    ldx #MAP_START_COL                      ; X = source index into map_row_buf
    ldy #MAP_WIDTH_TILES                    ; Y = metatile countdown
@top_loop:
    lda map_row_buf, x                      ; A = metatile id (0..127)
    phx                                     ; save src idx -- tsa_* clobbers X
    tax                                     ; X = metatile id
    lda tsa_ul, x
    jsr HAL_PPU_2007_Write
    lda tsa_ur, x
    jsr HAL_PPU_2007_Write
    plx
    inx
    dey
    bne @top_loop

    ; --- write the bottom NT row (DL/DR halves) -----------------------------
    lda paint_row
    asl
    clc
    adc #1                                  ; NT row = meta_row * 2 + 1
    jsr set_ppu_addr_to_nt_row

    ldx #MAP_START_COL
    ldy #MAP_WIDTH_TILES
@bot_loop:
    lda map_row_buf, x
    phx
    tax
    lda tsa_dl, x
    jsr HAL_PPU_2007_Write
    lda tsa_dr, x
    jsr HAL_PPU_2007_Write
    plx
    inx
    dey
    bne @bot_loop

    inc paint_row
    inc paint_src
    lda paint_row
    cmp #15                                 ; 15 metatile rows = 30 NT rows
    bne @meta_row_loop

    ; --- write the attribute table -----------------------------------------
    ; The PPU attribute table is exactly 64 bytes arranged as 8 rows x 8
    ; cols, each byte covering a 4x4-cell = 2x2-metatile area of the NT.
    ; Our 16-metatile-wide window = 8 attr cols x 8 attr rows (15 metatile
    ; rows -> last attr row covers rows 14 + a throwaway row 15; we clamp
    ; the clamped-off metatile to row 14 in fetch_meta_group).
    ;
    ; For each attr byte we OR the group bits of the UL/UR/DL/DR metatiles
    ; into bit fields 1:0 / 3:2 / 5:4 / 7:6. Uniform tsa_attr means the
    ; low 2 bits of the byte already carry the group.
    lda #$23
    jsr HAL_PPU_2006_Write
    lda #$C0
    jsr HAL_PPU_2006_Write

    ldx #0                                  ; X = attr row counter (0..7)
@attr_row:
    ldy #0                                  ; Y = attr col counter (0..7)
@attr_col:
    jsr build_attr_byte
    jsr HAL_PPU_2007_Write
    iny
    cpy #8
    bne @attr_col
    inx
    cpx #8
    bne @attr_row

    ; --- push the OW palette *after* all NT + attr writes have landed. -----
    ; Doing this earlier means the next vblank paints cur_pal (green grass
    ; colours) while the NT mirror still holds the party-gen box tiles, so
    ; the user sees one frame of orange-text-on-green before the map
    ; appears. Seeding load_map_pal into cur_pal only now keeps the
    ; palette swap and the new NT contents in lockstep on the same flush.
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

; ---------------------------------------------------------------------------
; set_ppu_addr_to_nt_row(A = nt_row 0..29) -- point PPUADDR at column 0.
; PPU address = $2000 + nt_row * 32 = $2000 + (nt_row << 5).
; ---------------------------------------------------------------------------
.proc set_ppu_addr_to_nt_row
    pha
    ; row >> 3 gives the high-byte add-in (0..3), OR'd with $20 base.
    lsr
    lsr
    lsr
    ora #$20
    jsr HAL_PPU_2006_Write
    pla
    ; row & 7 << 5 gives the low byte.
    and #$07
    ldx #5
@shift:
    asl
    dex
    bne @shift
    jmp HAL_PPU_2006_Write                  ; tail call
.endproc

; ---------------------------------------------------------------------------
; build_attr_byte(X = attr_row 0..7, Y = attr_col 0..7) -> A
; Each NES attribute byte covers a 4x4-cell = 2x2-metatile area. We treat
; attr_row = meta_row / 2, attr_col = meta_col / 2, so the attr byte at
; (attr_row, attr_col) describes metatiles (2ar,2ac), (2ar,2ac+1),
; (2ar+1,2ac), (2ar+1,2ac+1) -> bits 1:0 / 3:2 / 5:4 / 7:6.
;
; Since tsa_attr values are always uniform 4-group packings ($00/$55/$AA/
; $FF), we extract the bottom-2 bits of tsa_attr[metatile_id] to get the
; group and re-pack.
; ---------------------------------------------------------------------------
.proc build_attr_byte
    phx
    phy
    ; metatile row of TL quadrant = attr_row * 2
    txa
    asl
    sta attr_meta_row
    ; metatile col of TL quadrant = attr_col * 2
    tya
    asl
    sta attr_meta_col

    stz attr_out

    ; --- UL quadrant (bits 1:0) -------------------------------------------
    jsr fetch_meta_group
    ora attr_out
    sta attr_out

    ; --- UR quadrant (bits 3:2) -------------------------------------------
    inc attr_meta_col
    jsr fetch_meta_group
    asl
    asl
    ora attr_out
    sta attr_out

    ; --- DL quadrant (bits 5:4) -------------------------------------------
    dec attr_meta_col                       ; back to base col
    inc attr_meta_row
    jsr fetch_meta_group
    asl
    asl
    asl
    asl
    ora attr_out
    sta attr_out

    ; --- DR quadrant (bits 7:6) -------------------------------------------
    inc attr_meta_col
    jsr fetch_meta_group
    asl
    asl
    asl
    asl
    asl
    asl
    ora attr_out
    sta attr_out

    lda attr_out
    ply
    plx
    rts
.endproc

; fetch_meta_group ------------------------------------------------------
; Fetch the metatile id at (attr_meta_row, attr_meta_col) from the rendered
; window, look it up in tsa_attr, and return its low 2 bits in A.
.proc fetch_meta_group
    ; map_row = MAP_START_ROW + attr_meta_row. Since we only render 15
    ; metatile rows and the attribute table has a spare 8th row whose
    ; bottom half extends off the visible area, clamp meta_row to 14 so
    ; we never exceed our decompress-once-per-row pattern.
    ; NOTE: this harness does a single decompression pass per metatile
    ; row already, but build_attr_byte runs *after* that pass. To avoid
    ; re-decompressing 15 rows just to build the attr table, we store
    ; map_row_buf during each pass would require 15*256 bytes. Instead,
    ; for the attr pass we re-decompress on demand -- 8 rows total.
    lda attr_meta_row
    cmp #15
    bcc :+
    lda #14                                 ; clamp (edge of 15-row window)
:   clc
    adc #MAP_START_ROW
    jsr MapDecompressRow

    lda attr_meta_col
    clc
    adc #MAP_START_COL
    tax
    lda map_row_buf, x
    tax
    lda tsa_attr, x
    and #$03
    rts
.endproc

.segment "BSS"

attr_meta_row: .res 1
attr_meta_col: .res 1
attr_out:      .res 1
