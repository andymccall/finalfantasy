; ---------------------------------------------------------------------------
; tiles_load.asm - Neo6502 HAL_LoadTiles implementation.
; ---------------------------------------------------------------------------
; The Neo console exposes only 64 redefinable glyph slots (codes $C0..$FF)
; via Group 2 Function $05 "Define Character". Each call takes a character
; code in the first parameter byte and seven row bytes in the next seven.
; Rendering reads bits 7..2 of each row byte as a 6-wide cell.
;
; We load the first 64 FF1 tiles (FF1 slots $80..$BF, which cover digits
; '0'-'9' and letters 'A'-Z plus early lowercase) into Neo user-font slots
; $C0..$FF. The flush routine translates nametable bytes in that source
; range by adding $40, so the 14-bit PPU address space and FF1's native
; tile numbering still make sense to the rest of the code.
;
; Rightmost two columns of each NES glyph are cropped by the 6-wide cell
; (acceptable - the FF1 font has blank margin on the right for most
; alphanumerics). Bottom row is dropped since Neo only stores 7 rows.
; ---------------------------------------------------------------------------

.export HAL_LoadTiles

ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_CONSOLE    = $02
API_FN_DEFINE_CHAR   = $05

FONT_TILES           = 64               ; FF1 slots $80..$BF
FIRST_NEO_SLOT       = $C0
BYTES_PER_TILE       = 7

.segment "ZEROPAGE"

font_ptr: .res 2

.segment "BSS"

tile_index: .res 1

.segment "RODATA"

ff1_font:
    .incbin "font_converted.bin"

.segment "CODE"

.proc HAL_LoadTiles
    lda #<ff1_font
    sta font_ptr + 0
    lda #>ff1_font
    sta font_ptr + 1

    stz tile_index
@tile_loop:
    ; wait for any previous API call to drain
@wait_idle:
    lda API_COMMAND
    bne @wait_idle

    ; parameter 0 = Neo character code
    lda tile_index
    clc
    adc #FIRST_NEO_SLOT
    sta API_PARAMETERS + 0

    ; parameters 1..7 = 7 row bytes from the converted blob
    ldy #0
@row_loop:
    lda (font_ptr), y
    sta API_PARAMETERS + 1, y
    iny
    cpy #BYTES_PER_TILE
    bne @row_loop

    lda #API_FN_DEFINE_CHAR
    sta API_FUNCTION
    lda #API_GROUP_CONSOLE
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done

    ; advance source pointer by BYTES_PER_TILE
    lda font_ptr + 0
    clc
    adc #BYTES_PER_TILE
    sta font_ptr + 0
    bcc @no_carry
    inc font_ptr + 1
@no_carry:

    inc tile_index
    lda tile_index
    cmp #FONT_TILES
    bne @tile_loop
    rts
.endproc
