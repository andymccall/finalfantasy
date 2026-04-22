; ---------------------------------------------------------------------------
; hal.asm - Commander X16 HAL implementation.
; ---------------------------------------------------------------------------
; Polling-based vblank. VERA raises the VSYNC bit in ISR every frame; an
; SEI guards the poll so the KERNAL IRQ handler (which also acks VSYNC)
; cannot race us, then CLI lets it catch up on keyboard / jiffy.
;
; On init layer 1 is switched into 4bpp tile mode with a 32x32 tile map,
; 8x8 tiles, pointed at:
;   - tile map  at VRAM $1:B000  (2 KB, 32x32 * 2 bytes per entry)
;   - tile base at VRAM $1:C000  (8 KB, 256 slots * 32 bytes per tile)
;
; Tile slot 0 is the "blank" tile (all transparent pixels), used wherever
; the virtual PPU's nametable mirror holds a $00 byte (FF1's ClearNT
; sentinel). FF1 nametable bytes $80..$FF go straight through as tile
; slot ids -- the converted font CHR is uploaded into those slots by
; HAL_LoadTiles.
;
; The tile map is zeroed at boot so every cell starts as the blank tile;
; the first HAL_FlushNametable call after EnterIntroStory / EnterTitleScreen
; paints the visible 32x30 region with the real tile ids + NES-attribute-
; derived palette offsets.
;
; Chaining the KERNAL IRQ vector at $0314 is avoided because the IRQ target
; lives behind ROM-bank switching that the application does not control.
; ---------------------------------------------------------------------------

.import main
.import HAL_PPUInit
.import HAL_FlushNametable
.import HAL_LoadTiles
.import HAL_SpritesInit
.import HAL_UploadMapTiles
.import HAL_SetTileMode

.include "mbc/am3/am3.inc"

.export HAL_Init
.export HAL_WaitVblank
.export HAL_SetCameraPixel

; --- VERA registers --------------------------------------------------------
VERA_ADDR_L    = $9F20
VERA_ADDR_M    = $9F21
VERA_ADDR_H    = $9F22
VERA_DATA0     = $9F23
VERA_CTRL      = $9F25
VERA_ISR       = $9F27
VERA_DC_HSCALE = $9F2A                  ; DCSEL=0: horizontal output scale
VERA_DC_VSCALE = $9F2B                  ; DCSEL=0: vertical output scale
VERA_L1_CONFIG    = $9F34
VERA_L1_MAPBASE   = $9F35
VERA_L1_TILEBASE  = $9F36
VERA_L1_HSCROLL_L = $9F37
VERA_L1_HSCROLL_H = $9F38
VERA_L1_VSCROLL_L = $9F39
VERA_L1_VSCROLL_H = $9F3A

; Layer 1 tile-mode configuration:
;   L1_CONFIG    = %00_01_0_0_10  = $12    (map 64x32, T256C=0, tile mode, 4bpp)
;   L1_MAPBASE   = $1B000 >> 9    = $D8    (tile map  at VRAM $1:B000, 4 KB)
;   L1_TILEBASE  = ($1C000 >> 11) << 2 = $E0  (tile base at VRAM $1:C000,
;                                              tile size 8x8 -- bits 1:0 = 0)
; The 64x32 map gives enough horizontal slack that nothing wraps around
; the edge of the visible NES region. We render the 32-col NES viewport
; into map columns 16..47 (dead centre) and leave map columns 0..15 and
; 48..63 as blank tile slot 0, so scroll artefacts and text that spills
; past column 31 land in blank space instead of re-appearing on the far
; side of the screen.
L1_CONFIG_VAL   = $12
L1_MAPBASE_VAL  = $D8
L1_TILEBASE_VAL = $E0

; Tile map: 64 cols * 32 rows * 2 bytes = 4 KB at VRAM $1:B000.
TILEMAP_L       = $00
TILEMAP_M       = $B0
TILEMAP_H       = $11                   ; bank 1, stride +1
TILEMAP_BYTES_HI = $10                  ; 4 KB = 16 pages

DC_SCALE_2X    = $40                    ; scale_factor = 128 / this, so $40 -> 2x

; With a 64-column map, the map's horizontal extent is 512 source pixels.
; NES col 0 lives at map col 16 = pixel 128; we want that to render at
; display pixel 32 (so the 256-wide NES region sits in the middle of the
; 320-wide VERA output with 32-pixel gutters). HSCROLL pushes the camera
; right, so the required value is 128 - 32 = 96 = $060.
HSCROLL_CENTER_L = $60
HSCROLL_CENTER_H = $00

; ---------------------------------------------------------------------------
; PRG header + BASIC stub: 10 SYS2061
; ---------------------------------------------------------------------------

.segment "LOADADDR"
    .word $0801

.segment "STARTUP"

basic_stub:
    .word basic_stub_end
    .word 10
    .byte $9E
    .byte "2061"
    .byte $00
basic_stub_end:
    .word $0000
    jmp main

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_Init
    jsr AM3_Init                        ; DIAGNOSTIC: now writes 1 not 0
    stz VERA_CTRL                       ; DCSEL=0, ADDRSEL=0

    ; --- 2x display scale: 320x240 effective, closer to NES 256x240 ---------
    lda #DC_SCALE_2X
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE

    ; --- point layer 1 at our 4bpp 32x32 tile map + tile base ---------------
    lda #L1_CONFIG_VAL
    sta VERA_L1_CONFIG
    lda #L1_MAPBASE_VAL
    sta VERA_L1_MAPBASE
    lda #L1_TILEBASE_VAL
    sta VERA_L1_TILEBASE

    ; --- centre the 32x30 NES region in the 40x30 VERA viewport -------------
    lda #HSCROLL_CENTER_L
    sta VERA_L1_HSCROLL_L
    lda #HSCROLL_CENTER_H
    sta VERA_L1_HSCROLL_H

    ; --- zero the 4 KB tile map ($1:B000..$1:BFFF) --------------------------
    lda #TILEMAP_L
    sta VERA_ADDR_L
    lda #TILEMAP_M
    sta VERA_ADDR_M
    lda #TILEMAP_H
    sta VERA_ADDR_H

    ldx #TILEMAP_BYTES_HI               ; 8 pages of 256 bytes
@page:
    ldy #0
@byte:
    stz VERA_DATA0
    iny
    bne @byte
    dex
    bne @page

    jsr HAL_PPUInit
    jsr HAL_LoadTiles
    jsr HAL_UploadMapTiles              ; map tiles at VRAM slots $00..$7F
    jsr HAL_SpritesInit
    lda #0                              ; menu mode -- NES $80..$FF renders as VERA slot = byte
    jsr HAL_SetTileMode
    rts
.endproc

.proc HAL_WaitVblank
    sei                                 ; block KERNAL IRQ so it can't ack VSYNC behind us
    lda #$01
    sta VERA_ISR                        ; clear any stale VSYNC flag
@wait:
    bit VERA_ISR
    beq @wait
    cli                                 ; let KERNAL catch up on keyboard / jiffy

    jsr HAL_FlushNametable
    rts
.endproc

; HAL_SetCameraPixel --------------------------------------------------------
; A = pixel-level sub-X offset (0..15), X = sub-Y offset (0..15).
; Nudge VERA HSCROLL/VSCROLL around the HSCROLL_CENTER baseline so the
; visible region slides smoothly within the current NT-mirror contents.
; Cell-level camera motion is handled by the caller (via DrawFullMap when
; a boundary is crossed); this call only handles the sub-cell pixel offset.
;
; Map cell is 16 NES pixels (2x2 NES tiles). One NES pixel = one VERA pixel
; at this target's 1:1 source resolution; the 2x display scale just upsizes
; on output. So sub-X 0..15 maps linearly onto HSCROLL_CENTER + sub_x.
.proc HAL_SetCameraPixel
    pha                                 ; stash sub-X
    clc
    adc #HSCROLL_CENTER_L
    sta VERA_L1_HSCROLL_L
    lda #HSCROLL_CENTER_H
    adc #0                              ; propagate carry (sub-X max 15, never carries)
    sta VERA_L1_HSCROLL_H
    pla

    txa
    sta VERA_L1_VSCROLL_L
    lda #0
    sta VERA_L1_VSCROLL_H
    rts
.endproc
