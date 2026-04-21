; ---------------------------------------------------------------------------
; palette_strip.asm - Neo6502 HAL_ShowPaletteStrip implementation.
; ---------------------------------------------------------------------------
; Paints 32 filled rectangles across the screen, one per uploaded palette
; slot (0..31). Each rectangle is 8 pixels wide and 40 pixels tall, starting
; at y = 100 and tiled left-to-right at x = slot * 8.
;
; API calls used:
;   Group $05 function $41  Set Solid Flag       -- useSolidFill = 1
;   Group $05 function $40  Set Draw Colour      -- pixelXor = slot index
;   Group $05 function $03  Draw Rectangle       -- x1,y1,x2,y2 as 16-bit LE
;                                                  in API_PARAMETERS 0..7
; ---------------------------------------------------------------------------

.export HAL_ShowPaletteStrip

API_COMMAND        = $FF00
API_FUNCTION       = $FF01
API_PARAMETERS     = $FF04

API_GROUP_GRAPHICS = $05
API_FN_DRAW_RECT   = $03
API_FN_SET_COLOUR  = $40
API_FN_SET_SOLID   = $41

STRIP_COUNT = 32
STRIP_Y_TOP = 100
STRIP_Y_BOT = 139

.segment "BSS"

strip_idx: .res 1

.segment "CODE"

.proc HAL_ShowPaletteStrip
    ; --- enable solid fill for rectangles -----------------------------------
@wait_solid:
    lda API_COMMAND
    bne @wait_solid
    lda #$01
    sta API_PARAMETERS + 0
    lda #API_FN_SET_SOLID
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND

    stz strip_idx
@loop:
    ; --- set draw colour = current slot --------------------------------------
@wait_colour:
    lda API_COMMAND
    bne @wait_colour
    lda strip_idx
    sta API_PARAMETERS + 0
    lda #API_FN_SET_COLOUR
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND

    ; --- draw filled rectangle at x = slot*8, y = 100..139 ------------------
@wait_rect:
    lda API_COMMAND
    bne @wait_rect

    lda strip_idx
    asl
    asl
    asl                             ; slot * 8
    sta API_PARAMETERS + 0          ; x1 low
    clc
    adc #7
    sta API_PARAMETERS + 4          ; x2 low
    stz API_PARAMETERS + 1          ; x1 high
    stz API_PARAMETERS + 5          ; x2 high

    lda #STRIP_Y_TOP
    sta API_PARAMETERS + 2          ; y1 low
    stz API_PARAMETERS + 3          ; y1 high
    lda #STRIP_Y_BOT
    sta API_PARAMETERS + 6          ; y2 low
    stz API_PARAMETERS + 7          ; y2 high

    lda #API_FN_DRAW_RECT
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND

    inc strip_idx
    lda strip_idx
    cmp #STRIP_COUNT
    bne @loop

    ; Drain the queue so later API users see a clean command byte.
@wait_last:
    lda API_COMMAND
    bne @wait_last
    rts
.endproc
