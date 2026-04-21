; ---------------------------------------------------------------------------
; title_screen_shim.asm - Translator wrapper for EnterTitleScreen + friends.
; ---------------------------------------------------------------------------
; Pulls three verbatim extracts from bank_0E.asm under one compilation unit:
;
;   title_screen.inc   -- EnterTitleScreen, IntroTitlePrepare,
;                         TitleScreen_DrawRespondRate, lut_TitleText_*,
;                         lut_TitleCursor_Y  (bank_0E.asm:3472-3670)
;   title_music.inc    -- TitleScreen_Music (bank_0E.asm:113-116)
;   clear_nt.inc       -- ClearNT, the attribute/nametable fill that
;                         IntroTitlePrepare ends with (bank_0E.asm:2504-2534)
;
; Everything else the verbatim code JSRs into either lives in another shim
; (DrawBox, DrawComplexString, TitleScreen_Copyright, MenuCondStall),
; comes from a HAL hook (the PPU/APU port writes), or is stubbed here.
;
; The stubs sit at bank boundaries the re-host hasn't crossed yet:
;   - LoadMenuCHRPal         : CHR + palette upload is done by HAL_LoadTiles
;                              and DrawPalette from main.asm, not via this
;                              routine.
;   - TurnMenuScreenOn_ClearOAM : PPU is always on; we still need to zero
;                              OAM so garbage doesn't accumulate.
;   - ClearOAM               : fills oam[0..255] with $FF (the NES "hide
;                              sprite" convention), matching what the real
;                              routine in bank_0E does.
;   - DrawCursor             : cheap text-mode stand-in until the tile
;                              renderer lands and we can port the real
;                              2x2 sprite routine. Writes '>' into the
;                              nametable mirror at (spr_x/8, spr_y/8)
;                              and remembers the position so ClearOAM
;                              (called at the top of each @Loop) can
;                              restore the previous cell to a space.
;   - PlaySFX_MenuSel        : no audio driver; stub RTS.
;   - PlaySFX_MenuMove
;
; WaitForVBlank_L is re-exported here too -- on the NES it stalls until
; NMI, and our HAL_WaitVblank does the equivalent host-side work. The
; RTS stub previously in box_drawing_shim is unreachable only because
; menustall was 0; now it's on the title-screen's per-frame path, so we
; point it at the real HAL.
;
; .feature force_range: EnterTitleScreen's Left-branch arithmetic uses
; `LDA #-1` (bank_0E.asm:3546). Older ca65 builds (including the one
; shipped with FF1Disassembly) accepted signed immediates silently;
; current ca65 flags them as out-of-range. The feature flag restores
; the old behaviour so the verbatim extract assembles unchanged.
; ---------------------------------------------------------------------------

.feature force_range

.import HAL_WaitVblank
.import HAL_PPU_2001_Write
.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write
.import HAL_APU_4014_Write
.import HAL_APU_4015_Write

.import TitleScreen_Copyright
.import DrawBox
.import DrawComplexString
.import CallMusicPlay                   ; audio stub lives in box_drawing_shim
.import UpdateJoy                       ; real impl lives in joy_shim

.importzp text_ptr
.import cur_bank, ret_bank
.import box_x, box_y, box_wd, box_ht
.import menustall
.import soft2000
.import respondrate, cursor
.import joy, joy_a, joy_b, joy_start, joy_prevdir
.import spr_x, spr_y
.import ppu_nt_mirror
.import music_track
.import oam

.export EnterTitleScreen
.export IntroTitlePrepare
.export WaitForVBlank_L
.export ClearNT
.export TurnMenuScreenOn_ClearOAM

; Joypad direction bit (from FF1's Constants.inc).
RIGHT = $01

; Flat address space -- any value satisfies the cur_bank/ret_bank stores.
BANK_THIS = $00

.segment "CODE"

; The real WaitForVBlank_L on the NES loops until the NMI handler flips a
; flag. We have HAL_WaitVblank, which does the host-side equivalent
; (blocking until the next vblank event). JSR into it, then RTS.
WaitForVBlank_L:
    jmp HAL_WaitVblank                  ; tail-call: preserves return addr

; LoadMenuCHRPal on the NES pushes the menu CHR and palette data into PPU
; memory. Our port does both out-of-band: HAL_LoadTiles uploads the font
; at boot and main.asm stages the title palette before calling
; TitleScreen_Copyright. So the stub can return immediately.
LoadMenuCHRPal:
    rts

; TurnMenuScreenOn_ClearOAM on the NES flips PPUCTRL/PPUMASK bits to
; enable rendering after ClearOAM. Our PPU is always on; we just need the
; OAM zero-out, and even that is a safety net because DrawCursor is
; stubbed too.
TurnMenuScreenOn_ClearOAM:
    ; fall through to ClearOAM and let its RTS return

; ClearOAM fills 256 bytes of the oam buffer with $FF. $FF in the Y
; coordinate puts the sprite off-screen on real hardware, so "hide all
; sprites" is just "write $FF everywhere". This matches the NES routine.
;
; We also use ClearOAM's per-frame firing as the erase signal for our
; text-mode cursor: if a previous position was recorded, restore that
; nametable cell to a space so the '>' doesn't smear across rows as the
; selection moves.
ClearOAM:
    ldx #0
    lda #$FF
@oam_loop:
    sta oam, x
    inx
    bne @oam_loop

    ; --- erase previous cursor cell (if any) --------------------------------
    lda cursor_prev_valid
    beq @done
    lda #' '                            ; blank the old cell
    ldx cursor_prev_lo
    ldy cursor_prev_hi
    stx @erase_ptr + 1
    sty @erase_ptr + 2
    ldy #0
@erase_ptr:
    sta ppu_nt_mirror                   ; patched above with the saved address
    stz cursor_prev_valid
@done:
    rts

; DrawCursor on the NES draws a 2x2 sprite at (spr_x, spr_y). We haven't
; shipped the tile renderer yet, so there's no sprite plane to target.
; As a stand-in, write '>' into the nametable mirror at the cell that
; contains the pixel coord (spr_x-8, spr_y) -- the real sprite hangs
; off the left of the text, so we shift one cell left. Record the cell
; address so ClearOAM can blank it on the next frame.
;
; spr_x is divided by 8 to get column; spr_y likewise for row. The
; mirror offset is row*32 + col, added to ppu_nt_mirror. Two successive
; >>3 and <<5 (for row) give a 16-bit offset into the 2 KiB mirror.
DrawCursor:
    ; --- col = (spr_x / 8) - 1 ----------------------------------------------
    lda spr_x
    lsr
    lsr
    lsr
    sec
    sbc #1
    sta cursor_col

    ; --- row = spr_y / 8 ----------------------------------------------------
    lda spr_y
    lsr
    lsr
    lsr
    sta cursor_row

    ; --- nt_ptr = ppu_nt_mirror + row*32 + col ------------------------------
    ; high byte contribution: row >> 3  (= row*32 / 256)
    lda cursor_row
    lsr
    lsr
    lsr
    clc
    adc #>ppu_nt_mirror
    sta cursor_hi

    ; low byte contribution: (row << 5) | col (col < 32 so no overlap)
    lda cursor_row
    asl
    asl
    asl
    asl
    asl
    ora cursor_col
    clc
    adc #<ppu_nt_mirror
    sta cursor_lo
    bcc @store
    inc cursor_hi

@store:
    ; record for ClearOAM's next-frame erase
    lda cursor_lo
    sta cursor_prev_lo
    lda cursor_hi
    sta cursor_prev_hi
    lda #1
    sta cursor_prev_valid

    ; write '>' to the cell via self-modified STA
    lda cursor_lo
    sta @store_addr + 1
    lda cursor_hi
    sta @store_addr + 2
    lda #'>'
@store_addr:
    sta ppu_nt_mirror                   ; patched with cursor_lo/hi above
    rts

.segment "BSS"
cursor_col:        .res 1
cursor_row:        .res 1
cursor_lo:         .res 1
cursor_hi:         .res 1
cursor_prev_lo:    .res 1
cursor_prev_hi:    .res 1
cursor_prev_valid: .res 1

.segment "CODE"

; Audio stubs -- no music driver yet. CallMusicPlay lives in
; box_drawing_shim and is already a stub there.
PlaySFX_MenuSel:
    rts
PlaySFX_MenuMove:
    rts

.include "title_screen.inc"
.include "title_music.inc"
.include "clear_nt.inc"
