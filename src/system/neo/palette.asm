; ---------------------------------------------------------------------------
; palette.asm - Neo6502 HAL_UploadPalette implementation.
; ---------------------------------------------------------------------------
; cur_pal holds 32 bytes of NES colour indices. Each is expanded to an
; (R, G, B) triple via a fixed 192-byte LUT (64 entries * 3 bytes) and
; pushed to the Neo palette slot of matching index using the graphics
; group's SET_PALETTE function.
;
; The NES palette is NTSC-phase based; see the X16 implementation for why
; this is LUT-driven instead of arithmetic.
;
; API call layout used here (SET_PALETTE):
;     API_PARAMETERS + 0 = palette index (0..255)
;     API_PARAMETERS + 1 = red
;     API_PARAMETERS + 2 = green
;     API_PARAMETERS + 3 = blue
; If the firmware expects a different ordering, only the store sequence
; inside the loop needs to change; the LUT is format-agnostic as
; (R, G, B) triples.
; ---------------------------------------------------------------------------

.import cur_pal

.export HAL_UploadPalette

; --- Neo6502 API -----------------------------------------------------------
API_COMMAND        = $FF00
API_FUNCTION       = $FF01
API_PARAMETERS     = $FF04

API_GROUP_GRAPHICS = $05
API_FN_SET_PALETTE = $20

; ---------------------------------------------------------------------------

.segment "BSS"

pal_walker: .res 1                ; cur_pal loop counter
tmp_index:  .res 1                ; scratch for NES index * 3 computation

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_UploadPalette
    stz pal_walker
@loop:
    ; --- build LUT offset: NES index * 3 -----------------------------------
    ldy pal_walker
    lda cur_pal, y
    and #$3F                      ; mask NES emphasis bits
    sta tmp_index                 ; save masked index
    asl a                         ; * 2
    clc
    adc tmp_index                 ; * 3
    tax

    ; --- wait for any pending API call to finish ---------------------------
@wait_prev:
    lda API_COMMAND
    bne @wait_prev

    ; --- fill parameters ---------------------------------------------------
    lda pal_walker                ; Neo palette slot 0..31
    sta API_PARAMETERS + 0
    lda nes_to_neo_lut, x         ; R
    sta API_PARAMETERS + 1
    lda nes_to_neo_lut+1, x       ; G
    sta API_PARAMETERS + 2
    lda nes_to_neo_lut+2, x       ; B
    sta API_PARAMETERS + 3

    ; --- fire SET_PALETTE --------------------------------------------------
    lda #API_FN_SET_PALETTE
    sta API_FUNCTION
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND

    ; --- next index --------------------------------------------------------
    inc pal_walker
    lda pal_walker
    cmp #32
    bne @loop

    ; Wait for the final call so subsequent API users see a clean queue.
@wait_last:
    lda API_COMMAND
    bne @wait_last
    rts
.endproc

; ---------------------------------------------------------------------------
; NES -> Neo6502 RGB lookup. 64 entries * 3 bytes (R, G, B).
; Values are 8-bit-per-channel, quantised from the Nestopia NTSC reference.
; NES slots $0D/$0E/$0F and the equivalent "blank" slots in each row are
; forced to black (NES hardware treats them as off-colour-burst).
; ---------------------------------------------------------------------------

.segment "RODATA"

nes_to_neo_lut:
    .byte $7C,$7C,$7C,  $00,$00,$FC,  $00,$00,$BC,  $44,$28,$BC  ; $00-$03
    .byte $94,$00,$84,  $A8,$00,$20,  $A8,$10,$00,  $88,$14,$00  ; $04-$07
    .byte $50,$30,$00,  $00,$78,$00,  $00,$68,$00,  $00,$58,$00  ; $08-$0B
    .byte $00,$40,$58,  $00,$00,$00,  $00,$00,$00,  $00,$00,$00  ; $0C-$0F
    .byte $BC,$BC,$BC,  $00,$78,$F8,  $00,$58,$F8,  $68,$44,$FC  ; $10-$13
    .byte $D8,$00,$CC,  $E4,$00,$58,  $F8,$38,$00,  $E4,$5C,$10  ; $14-$17
    .byte $AC,$7C,$00,  $00,$B8,$00,  $00,$A8,$00,  $00,$A8,$44  ; $18-$1B
    .byte $00,$88,$88,  $00,$00,$00,  $00,$00,$00,  $00,$00,$00  ; $1C-$1F
    .byte $F8,$F8,$F8,  $3C,$BC,$FC,  $68,$88,$FC,  $98,$78,$F8  ; $20-$23
    .byte $F8,$78,$F8,  $F8,$58,$98,  $F8,$78,$58,  $FC,$A0,$44  ; $24-$27
    .byte $F8,$B8,$00,  $B8,$F8,$18,  $58,$D8,$54,  $58,$F8,$98  ; $28-$2B
    .byte $00,$E8,$D8,  $78,$78,$78,  $00,$00,$00,  $00,$00,$00  ; $2C-$2F
    .byte $FC,$FC,$FC,  $A4,$E4,$FC,  $B8,$B8,$F8,  $D8,$B8,$F8  ; $30-$33
    .byte $F8,$B8,$F8,  $F8,$A4,$C0,  $F0,$D0,$B0,  $FC,$E0,$A8  ; $34-$37
    .byte $F8,$D8,$78,  $D8,$F8,$78,  $B8,$F8,$B8,  $B8,$F8,$D8  ; $38-$3B
    .byte $00,$FC,$FC,  $F8,$D8,$F8,  $00,$00,$00,  $00,$00,$00  ; $3C-$3F
