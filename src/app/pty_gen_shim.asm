; ---------------------------------------------------------------------------
; pty_gen_shim.asm - Translator wrapper for NewGamePartyGeneration screen.
; ---------------------------------------------------------------------------
; pty_gen.inc carries the verbatim extracts:
;
;   NewGamePartyGeneration  (bank_0E.asm:2581-2626 -- 4-character loop)
;   DoPartyGen_OnCharacter  (bank_0E.asm:2713-2751 -- per-char input loop)
;   PtyGen_Frame            (bank_0E.asm:2933-2946 -- per-frame sprite+DMA)
;   PtyGen_Joy              (bank_0E.asm:2987-3006 -- UpdateJoy + SFX)
;   PtyGen_DrawCursor       (bank_0E.asm:3155-3161)
;   PtyGen_DrawScreen       (bank_0E.asm:2683-2696)
;   PtyGen_DrawBoxes / PtyGen_DrawText / PtyGen_DrawOneText
;   lut_PtyGenBuf
;
; Stubs supplied here:
;   LoadNewGameCHRPal   -- CHR/palette upload is done once at boot via
;                          HAL_LoadTiles + DrawPalette.
;   PtyGen_DrawChars    -- the four 2x3 class-preview sprites need CHR
;                          from BANK_BTLCHR which isn't wired up yet.
;                          Return immediately so the cursor is the only
;                          sprite on screen.
;
; The cur_pal+$1/$2/$3 writes at the top of NewGamePartyGeneration shuffle
; BG palette group 0 -- which isn't drawn to on the party-gen screen
; (FF1 draws boxes with group 3). The writes still land in cur_pal so the
; verbatim code runs unchanged; the HAL palette filter ignores group-0
; slots because they don't match the colour-3 slot mask.
; ---------------------------------------------------------------------------

.feature force_range

.import HAL_PPU_2000_Write
.import HAL_PPU_2001_Write
.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write
.import HAL_APU_4014_Write
.import HAL_APU_4015_Write
.import HAL_WaitVblank

.import ClearNT
.import ClearOAM
.import TurnMenuScreenOn_ClearOAM
.import DrawBox
.import DrawComplexString
.import DrawCursor
.import WaitForVBlank_L
.import CallMusicPlay
.import UpdateJoy
.import PlaySFX_MenuSel
.import PlaySFX_MenuMove
.import EnterMapTest

.importzp text_ptr
.importzp tmp
.import cur_bank, ret_bank
.import cur_pal
.import box_x, box_y, box_wd, box_ht
.import dest_x, dest_y
.import menustall
.import soft2000
.import format_buf
.import ptygen
.import char_index
.import cursor
.import namecurs_x, namecurs_y
.import name_selectedtile, name_cursoradd, name_buf
.import oam
.import spr_x, spr_y
.import joy, joy_a, joy_b, joy_prevdir

.export EnterNewGame
.export PtyGen_DrawScreen
.export PtyGen_DrawBoxes
.export PtyGen_DrawText
.export PtyGen_DrawOneText
.export NewGamePartyGeneration

; Field offsets within each 16-byte ptygen record.
ptygen_class   = ptygen + $0
ptygen_name    = ptygen + $2
ptygen_name_x  = ptygen + $6
ptygen_name_y  = ptygen + $7
ptygen_class_x = ptygen + $8
ptygen_class_y = ptygen + $9
ptygen_spr_x   = ptygen + $A
ptygen_spr_y   = ptygen + $B
ptygen_box_x   = ptygen + $C
ptygen_box_y   = ptygen + $D
ptygen_curs_x  = ptygen + $E
ptygen_curs_y  = ptygen + $F

; Flat address space -- any value satisfies cur_bank / ret_bank stores.
BANK_THIS = $00

.segment "CODE"

; EnterNewGame is the host-side replacement for the bank_0F.asm:157-161
; sequence (SwapPRG_L + NewGamePartyGeneration + NewGame_LoadStartingStats).
; NewGame_LoadStartingStats and the real overworld enter aren't wired
; up; we run the map-tile sampler harness instead so the runtime
; tileset swap and map-mode ppu_flush path get exercised. The DMA push
; after party-gen clears any stale sprites (e.g. the name-input cursor)
; before the map harness paints its tile atlas.
EnterNewGame:
    jsr NewGamePartyGeneration
    jsr ClearOAM
    lda #>oam
    jsr HAL_APU_4014_Write
    jmp EnterMapTest                    ; tail-jump: harness spins forever

LoadNewGameCHRPal:
    rts

PtyGen_DrawChars:
    rts

.include "pty_gen.inc"
