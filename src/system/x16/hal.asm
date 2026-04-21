; ---------------------------------------------------------------------------
; hal.asm - Commander X16 HAL implementation.
; ---------------------------------------------------------------------------
; Polling-based vblank. VERA raises the VSYNC bit in ISR every frame; an
; SEI guards the poll so the KERNAL IRQ handler (which also acks VSYNC)
; cannot race us, then CLI lets it catch up on keyboard / jiffy.
;
; On init the text layer map is cleared to (char=0, attr=$01) so any later
; flush of the PPU nametable mirror paints into a known background. After
; each vblank the HAL copies the 32x30 visible region of the mirror into
; the VERA text layer.
;
; Chaining the KERNAL IRQ vector at $0314 is avoided because the IRQ target
; lives behind ROM-bank switching that the application does not control.
; ---------------------------------------------------------------------------

.import main
.import HAL_PPUInit
.import HAL_FlushNametable

.export HAL_Init
.export HAL_WaitVblank

; --- VERA registers --------------------------------------------------------
VERA_ADDR_L    = $9F20
VERA_ADDR_M    = $9F21
VERA_ADDR_H    = $9F22
VERA_DATA0     = $9F23
VERA_CTRL      = $9F25
VERA_ISR       = $9F27
; Text-screen map defaults to VRAM $1B000 on boot, 2 bytes per cell.

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
    stz VERA_CTRL                       ; DCSEL=0, ADDRSEL=0

    ; --- clear the text layer map ($1:B000..$1:EFFF, 16 KiB) ----------------
    stz VERA_ADDR_L
    lda #$B0
    sta VERA_ADDR_M
    lda #$11                            ; bit16=1, stride=+1
    sta VERA_ADDR_H

    ldx #$20                            ; $20 outer iterations * 256 cells
@page:
    ldy #0
@cell:
    stz VERA_DATA0                      ; char = $00
    lda #$01
    sta VERA_DATA0                      ; attr = white fg on black bg
    iny
    bne @cell
    dex
    bne @page

    jsr HAL_PPUInit
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
