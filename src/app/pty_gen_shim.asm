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
; The cur_pal+$1/$2/$3 writes at the top of NewGamePartyGeneration populate
; BG palette group 0. FF1 uses it on the name-input sub-screen: the
; DrawNameInputScreen routine writes attribute $00 into $23C0..$23CF so
; the top box (the player's name box) picks group-0 colours, which the
; palette shuffle makes orange against the blue group-3 main box. X16
; renders that via VERA per-tile palette offset. Neo renders the top box
; in group-3 colours -- Neo's global-LUT scanout can't do per-cell
; palette swaps, and baking dual-group font glyphs to work around that
; is more engineering than the cosmetic gain is worth.
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
.import HAL_SetSpriteMode

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
.import spr_x, spr_y, sprindex
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
; after party-gen clears any stale sprites before the map harness paints
; its tile atlas. The sprite mode is restored to mapman so the OW harness
; picks up mapman CHR from the shared VERA tile region.
EnterNewGame:
    jsr LoadNewGameCHRPal               ; push class sprite palettes
    lda #1
    jsr HAL_SetSpriteMode               ; route tile IDs to class CHR VRAM
    jsr NewGamePartyGeneration
    jsr ClearOAM
    lda #>oam
    jsr HAL_APU_4014_Write
    lda #0
    jsr HAL_SetSpriteMode               ; restore mapman dispatch for OW
    jmp EnterMapTest                    ; tail-jump: harness spins forever

; Push the four battle-sprite palettes into cur_pal slots $10..$1F. On
; the NES this would be LoadBattleSpritePalettes; here the cur_pal
; stores route through the virtual PPU to HAL_PalettePush which splays
; slots $10..$1F into VERA palette slices $40/$50/$60/$70.
LoadNewGameCHRPal:
    ldx #$0F
@loop:
    lda ClassBatSprPalettes, x
    sta cur_pal+$10, x
    dex
    bpl @loop
    rts

; PtyGen_DrawChars verbatim from bank_0E.asm:3205-3232. Walks the four
; ptygen entries, loads each class's palette + tile base, and tail-calls
; DrawSimple2x3Sprite. The resulting OAM holds six 8x8 sprite slots per
; party member at tile IDs class*$20..class*$20+5.
PtyGen_DrawChars:
    LDX #$00
    JSR @DrawOne
    LDX #$10
    JSR @DrawOne
    LDX #$20
    JSR @DrawOne
    LDX #$30
@DrawOne:
    LDA ptygen_spr_x, X
    STA spr_x
    LDA ptygen_spr_y, X
    STA spr_y

    LDA ptygen_class, X
    TAX
    LDA lutClassBatSprPalette, X
    STA tmp+1

    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A                     ; class index * $20
    STA tmp
    JMP DrawSimple2x3Sprite

.include "pty_gen.inc"
.include "draw_simple_2x3_sprite.inc"

.segment "RODATA"

ClassBatSprPalettes:
    .BYTE $0F,$28,$18,$21      ; palette 0 (white/red)
    .BYTE $0F,$16,$30,$36      ; palette 1 (blue/brown)
    .BYTE $0F,$30,$22,$12      ; palette 2 (unused during party-gen)
    .BYTE $0F,$30,$10,$00      ; palette 3 (unused during party-gen)

.include "lut_class_bat_spr_palette.inc"
