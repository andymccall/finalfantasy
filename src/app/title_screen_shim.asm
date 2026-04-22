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
.import DrawCursor                      ; real 2x2-sprite impl lives in sprite_shim
.import DrawPalette                     ; for TurnMenuScreenOn_ClearOAM
.import CallMusicPlay                   ; audio stub lives in box_drawing_shim
.import UpdateJoy                       ; real impl lives in joy_shim

.importzp text_ptr
.import cur_bank, ret_bank
.import box_x, box_y, box_wd, box_ht
.import menustall
.import soft2000
.import respondrate, cursor
.import joy, joy_a, joy_b, joy_start, joy_prevdir
.import spr_x, spr_y, sprindex
.import music_track
.import oam

.export EnterTitleScreen
.export IntroTitlePrepare
.export WaitForVBlank_L
.export ClearNT
.export TurnMenuScreenOn_ClearOAM
.export ClearOAM
.export PlaySFX_MenuSel
.export PlaySFX_MenuMove

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
; enable rendering after ClearOAM, and crucially calls DrawPalette to
; push cur_pal out to $3F00..$3F1F. Our PPU is always on, but callers
; (PtyGen_DrawScreen, DrawNameInputScreen) rely on the palette-push
; side effect so cur_pal shuffles made before the call land in VERA.
TurnMenuScreenOn_ClearOAM:
    jsr ClearOAM
    jmp DrawPalette

; ClearOAM mirrors the NES routine (bank_0F.asm:984): fill the entire
; 256-byte oam buffer with $F8 (Y = $F8 is the NES off-screen marker
; FF1 uses for "this sprite is hidden") and reset sprindex to 0. The
; real NES version hardcodes oam at $0200 and unrolls four pages; our
; oam lives anywhere in BSS, so one loop over all 256 bytes is fine.
ClearOAM:
    ldx #0
    lda #$F8
@oam_loop:
    sta oam, x
    inx
    bne @oam_loop
    stz sprindex
    rts

; Audio stubs -- no music driver yet. CallMusicPlay lives in
; box_drawing_shim and is already a stub there.
PlaySFX_MenuSel:
    rts
PlaySFX_MenuMove:
    rts

.include "title_screen.inc"
.include "title_music.inc"
.include "clear_nt.inc"
