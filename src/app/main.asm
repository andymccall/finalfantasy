; ---------------------------------------------------------------------------
; main.asm - Application entry point.
; ---------------------------------------------------------------------------
; Called once per boot by the platform's STARTUP segment. We first zero
; the ZEROPAGE and BSS segments to mirror the NES reset vector's
; RAM-clear, which is what FF1's GameStart routine assumes (it only
; initialises the variables it cares about and relies on everything else
; being zero at power-on). HAL_Init brings the display up and uploads
; the FF1 font; the title palette is staged into cur_pal and walked out
; via DrawPalette; then EnterTitleScreen takes over -- the verbatim
; routine that draws copyright text, the three menu boxes, their
; strings, and runs the title-screen input loop.
;
; With joypad input stubbed to zero, EnterTitleScreen's logic loop never
; takes the "option chosen" exit, so it spins on HAL_WaitVblank forever
; -- which is exactly the steady state we want at this milestone. The
; vblank flush paints the nametable + NES attribute table onto the host
; display each frame from inside HAL_WaitVblank.
; ---------------------------------------------------------------------------

.include "system/hal.inc"

.import cur_pal
.import DrawPalette
.import EnterTitleScreen
.import EnterIntroStory
.import EnterNewGame
.import ClearNT
.import startintrocheck
.import soft2000

.importzp clear_ptr

; ld65 emits these automatically for any segment: start address and
; total size in bytes. We use them to zero ZEROPAGE and BSS without
; having to enumerate every variable in ff_ram.asm.
.import __ZEROPAGE_RUN__, __ZEROPAGE_SIZE__
.import __BSS_RUN__, __BSS_SIZE__

.export main
.export GameStart_L

.segment "CODE"

.proc main
    jsr clear_ram
    jsr HAL_Init
    jsr load_title_palette
    jsr DrawPalette
    jmp GameStart_L                     ; tail-call: GameStart never returns
.endproc

; GameStart_L on the NES is a fixed-address trampoline (JMP GameStart).
; FF1 code JSRs here from IntroStory_Joy on a Start-press to "restart"
; the game (bounce back to the title screen).
;
; This is a trimmed port of GameStart (bank_0F.asm:66-154):
;   - hardware init (PPU/APU) collapses to soft2000 staging; our HAL
;     handles display bring-up in HAL_Init.
;   - startup-info loops (party stats, game flags, exptonext) and
;     SRAM verify / party-gen are skipped -- the title screen doesn't
;     consult any of them, so they can land when we port combat/OW.
;   - startintrocheck is the only cold-vs-warm signal we keep. clear_ram
;     zeroes it on every run, so $4D != $00 always takes the cold path
;     and the intro plays. When IntroStory_Joy JMPs back here later,
;     startintrocheck is still $4D and the intro is skipped.
;
; Carry on return from EnterTitleScreen signals Continue vs New Game:
; we have neither SRAM nor party gen yet, so both paths just wipe the
; nametable and spin on HAL_WaitVblank so the operator can see the
; title input closed the loop.
GameStart_L:
    lda #$08                            ; sprites use pattern table at $1xxx
    sta soft2000

    ldx #$FF                            ; reset stack pointer
    txs

    lda startintrocheck
    cmp #$4D
    beq @skip_intro
      lda #$4D
      sta startintrocheck
      jsr EnterIntroStory

@skip_intro:
    jsr EnterTitleScreen                ; C clear = Continue, C set = New Game
    bcc @continue
    jmp EnterNewGame                    ; tail-jump: EnterNewGame spins forever

@continue:
    jsr ClearNT
@forever:
    jsr HAL_WaitVblank
    jmp @forever

; Zero every byte of BSS, then every byte of ZEROPAGE. The NES reset
; vector does the equivalent by sweeping $0000..$07FF before calling
; GameStart, which is why FF1 can assume respondrate/cursor/joy*/
; music_track are all zero on entry to EnterTitleScreen.
;
; Order matters: we stash a 16-bit working pointer in zero page at
; clear_ptr (reserved via ff_ram.asm) and use it for the BSS sweep
; via (clear_ptr),y. The zero-page clear happens afterwards, which
; also zeroes clear_ptr itself. BSS can be any size; zero page is
; bounded to 256 bytes so an LDX loop suffices.
.proc clear_ram
    ; --- BSS ---
    lda #<__BSS_RUN__
    sta clear_ptr
    lda #>__BSS_RUN__
    sta clear_ptr+1
    ldx #<(>__BSS_SIZE__)       ; whole-page count (high byte of size)
    ldy #0
    lda #0
    cpx #0
    beq @tail
@page_loop:
    sta (clear_ptr), y
    iny
    bne @page_loop
    inc clear_ptr+1
    dex
    bne @page_loop
@tail:
    ldx #<(<__BSS_SIZE__)       ; leftover bytes in final page
    beq @zp
@tail_loop:
    sta (clear_ptr), y
    iny
    dex
    bne @tail_loop

    ; --- ZEROPAGE (this also zeroes clear_ptr) ---
@zp:
    ldx #<__ZEROPAGE_SIZE__     ; ZEROPAGE is <= 256 bytes; low byte is size
    beq @done
    lda #0
@zp_loop:
    dex
    sta __ZEROPAGE_RUN__, x
    bne @zp_loop
    sta __ZEROPAGE_RUN__        ; X=0 case: write slot 0
@done:
    rts
.endproc

; Copy 32 NES colour indices from RODATA into FF1's cur_pal staging buffer.
; DrawPalette then reads cur_pal on behalf of the original game code.
.proc load_title_palette
    ldx #31
@copy:
    lda title_palette, x
    sta cur_pal, x
    dex
    bpl @copy
    rts
.endproc

.segment "RODATA"

; FF1 title-screen palette. On a real NES the menu/title screen uses a
; single shared palette group across the whole screen (ClearNT fills the
; attribute table with $FF -- i.e. every quadrant picks palette group 3).
; Group 3 carries the "blue border" palette FF1's LoadBorderPalette_Blue
; writes at $3F0C..$3F0F: black(0F) / dark-grey(00) / blue(01) / white(30).
; Box-border tiles use pixel values 1/2/3 to render dark-grey outlines,
; blue fill, and white highlights respectively; the intro story's "fade-
; in" palette group 2 also wants color 2 = blue so tile $FF (the blank
; space tile, all pixels = nibble 2) renders the blue background.
; Groups 0/1/2 are staged for palette-trap completeness and to match
; the NES behaviour of writing the full $3F00..$3F1F range.
; Groups 1 and 2 are pre-faded to blue ($01) in colour slots 2/3: on the NES
; EnterIntroStory writes $01 to cur_pal+$6/$7/$A/$B while the PPU is off, so
; the flashed text is never visible. Our HAL flushes every vblank regardless
; of PPU-on state, so we must land the faded values in VERA before the first
; frame is drawn — otherwise the nametable paints once with group 1 fully
; visible before the fade animation kicks in. Groups 0 and 3 stay at the
; border palette; group 3 is what the text fades INTO at the end.
title_palette:
    .byte $0F, $00, $01, $30            ; group 0 (unused by title)
    .byte $0F, $00, $01, $01            ; group 1: faded-out (blue on blue)
    .byte $0F, $00, $01, $01            ; group 2: animating (starts blue)
    .byte $0F, $00, $01, $30            ; group 3: fully faded in (blue border)
    ; Sprite palettes. HAL_OAMFlush now dispatches NES sprite attr bits
    ; 1:0 to VERA palette offset (4 + N), so each NES sprite palette
    ; maps 1:1 to a distinct VERA slot base. FF1's title-screen cursor
    ; LUT uses palette 3 ($0F/$30/$10/$00 = black/white/light-grey/
    ; mid-grey); other sprite palettes are unused on the title screen.
    .byte $0F, $30, $30, $30            ; sprite palette 0 (unused)
    .byte $0F, $30, $30, $30            ; sprite palette 1 (unused)
    .byte $0F, $30, $30, $30            ; sprite palette 2 (unused)
    .byte $0F, $30, $10, $00            ; sprite palette 3: cursor shading
