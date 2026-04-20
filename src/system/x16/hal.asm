; ---------------------------------------------------------------------------
; hal.asm - Commander X16 HAL implementation.
; ---------------------------------------------------------------------------
; Polling-based vblank. VERA raises the VSYNC bit in ISR every frame; an
; SEI guards the poll so the KERNAL IRQ handler (which also acks VSYNC)
; cannot race us, then CLI lets it catch up on keyboard / jiffy.
;
; Visible heartbeat: after each vblank the top-left text cell is rewritten
; with the next glyph by poking VRAM $1B000 directly, giving a one-cell
; flicker locked to the display refresh.
;
; Chaining the KERNAL IRQ vector at $0314 is avoided because the IRQ target
; lives behind ROM-bank switching that the application does not control.
; ---------------------------------------------------------------------------

.import main

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

.segment "BSS"

heartbeat_char:  .res 1

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_Init
    stz VERA_CTRL               ; DCSEL=0, ADDRSEL=0 (use ADDR0/DATA0)
    stz heartbeat_char
    rts
.endproc

.proc HAL_WaitVblank
    sei                         ; block KERNAL IRQ so it can't ack VSYNC behind us
    lda #$01
    sta VERA_ISR                ; clear any stale VSYNC flag
@wait:
    bit VERA_ISR                ; BIT sets Z from (A & mem); A=$01 tests bit 0
    beq @wait
    cli                         ; let KERNAL catch up on keyboard / jiffy

    ; Point VERA at VRAM $1B000 -- screen cell (0,0), character byte.
    stz VERA_ADDR_L
    lda #$B0
    sta VERA_ADDR_M
    lda #$01                    ; bit16=1, no auto-increment
    sta VERA_ADDR_H

    inc heartbeat_char
    lda heartbeat_char
    sta VERA_DATA0
    rts
.endproc
