; ---------------------------------------------------------------------------
; hal.asm - Neo6502 HAL implementation.
; ---------------------------------------------------------------------------
; Rendering model: the Neo console is unused; everything is drawn on the
; graphics plane (320x240, the Neo's only graphics mode). FF1's 32x30
; nametable is painted via Group 5 Function 7 Draw Image per cell, with
; a 32-pixel horizontal gutter centring the 256-pixel-wide NES viewport.
;
; Vblank via API_GROUP_GRAPHICS / API_FN_FRAME_COUNT. The previous 32-bit
; counter is held in BSS; a new frame is signalled when any byte differs.
;
; API pattern: store function in API_FUNCTION, spin until API_COMMAND is
; zero (previous call done), then store the group in API_COMMAND to fire.
; Results land in API_PARAMETERS once the call completes.
; ---------------------------------------------------------------------------

.import main
.import HAL_PPUInit
.import HAL_FlushNametable
.import HAL_LoadTiles
.import HAL_PaletteInit

.export HAL_Init
.export HAL_WaitVblank

; --- Neo6502 API -----------------------------------------------------------
ControlPort          = $FF00
API_COMMAND          = ControlPort + 0
API_FUNCTION         = ControlPort + 1
API_PARAMETERS       = ControlPort + 4

API_GROUP_GRAPHICS   = $05
API_FN_FRAME_COUNT   = $25

API_GROUP_CONSOLE    = $02
API_FN_CLEAR_SCREEN  = $0C

; ---------------------------------------------------------------------------
; Entry: exec.zip loads the binary at $0800 and jumps there.
; ---------------------------------------------------------------------------

.segment "STARTUP"
    jmp main

; ---------------------------------------------------------------------------

.segment "BSS"

last_frame_count: .res 4

; ---------------------------------------------------------------------------

.segment "CODE"

.proc HAL_Init
    stz last_frame_count + 0
    stz last_frame_count + 1
    stz last_frame_count + 2
    stz last_frame_count + 3

    ; One-shot Console CLS to erase the firmware's "Morpheus" boot banner
    ; before we take over the graphics plane. Done once at init -- per-frame
    ; CLS would cause flicker because it can't complete alongside 960 Draw
    ; Image calls inside a single vblank.
@wait_idle:
    lda API_COMMAND
    bne @wait_idle
    lda #API_FN_CLEAR_SCREEN
    sta API_FUNCTION
    lda #API_GROUP_CONSOLE
    sta API_COMMAND
@wait_done:
    lda API_COMMAND
    bne @wait_done

    jsr HAL_PaletteInit                 ; program Neo palette slots 0..3 for FF1 menu colours
    jsr HAL_PPUInit
    jsr HAL_LoadTiles                   ; loads combined tiles.gfx (tiles + cursor sprite)
    rts
.endproc

.proc HAL_WaitVblank
@poll:
    lda #API_FN_FRAME_COUNT
    sta API_FUNCTION
@wait_poll:
    lda API_COMMAND
    bne @wait_poll
    lda #API_GROUP_GRAPHICS
    sta API_COMMAND

    lda API_PARAMETERS + 0
    cmp last_frame_count + 0
    bne @synced
    lda API_PARAMETERS + 1
    cmp last_frame_count + 1
    bne @synced
    lda API_PARAMETERS + 2
    cmp last_frame_count + 2
    bne @synced
    lda API_PARAMETERS + 3
    cmp last_frame_count + 3
    bne @synced
    bra @poll

@synced:
    lda API_PARAMETERS + 0
    sta last_frame_count + 0
    lda API_PARAMETERS + 1
    sta last_frame_count + 1
    lda API_PARAMETERS + 2
    sta last_frame_count + 2
    lda API_PARAMETERS + 3
    sta last_frame_count + 3

    jsr HAL_FlushNametable
    rts
.endproc
