; ---------------------------------------------------------------------------
; intro_story_shim.asm - Translator wrapper for EnterIntroStory + friends.
; ---------------------------------------------------------------------------
; Bundles three verbatim extracts under one compilation unit:
;
;   enter_intro_story.inc -- EnterIntroStory       (bank_0E.asm:3393-3455)
;   intro_story.inc       -- IntroStory_MainLoop, _AnimateBlock,
;                            _AnimateRow, _WriteAttr, _Frame
;                            (bank_0E.asm:3682-3892)
;   intro_story_joy.inc   -- IntroStory_Joy        (bank_0E.asm:92-101)
;
; The intro story draws text from lut_IntroStoryText (224 bytes from
; FF1's bin/0D_BF20_introtext.bin, INCBIN'd here) via DrawComplexString,
; then animates the attribute table to fade each block in. Our virtual
; PPU has no per-cell palette animation in text mode, so the fade is
; invisible and the text pops on -- but every routine stays byte-for-byte
; FF1 code. Replacing the text-mode renderer with a real CHR tile
; backend later will restore the fade automatically.
;
; Stubs:
;   BANK_INTROTEXT -- the NES ROM bank that holds lut_IntroStoryText.
;                     Flat build has no banks; the constant just has to
;                     exist and be stored somewhere (cur_bank) that
;                     DrawComplexString's eventual SwapPRG_L can consume
;                     as a no-op.
;   BTN_START      -- $10, the NES joypad Start-button bit. Same value
;                     as FF1's Constants.inc uses.
;
; GameStart_L is re-exported by main.asm; we .import it here so
; IntroStory_Joy can JMP to it on Start-press for the "restart to title
; screen" behaviour.
; ---------------------------------------------------------------------------

.import HAL_WaitVblank
.import HAL_PPU_2000_Write
.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write
.import HAL_APU_4015_Write

.import DrawComplexString
.import DrawPalette
.import CallMusicPlay
.import IntroTitlePrepare
.import TurnMenuScreenOn_ClearOAM
.import WaitForVBlank_L
.import UpdateJoy
.import GameStart_L

.importzp text_ptr
.import cur_bank, ret_bank
.import menustall
.import soft2000
.import respondrate
.import joy
.import joy_a, joy_b
.import cur_pal
.import intro_ataddr, intro_atbyte, intro_color
.import framecounter
.import dest_x, dest_y

.export EnterIntroStory
.export IntroStory_Joy

BANK_INTROTEXT = $00                    ; flat build: SwapPRG_L is RTS
BANK_THIS      = $00
BTN_START      = $10                    ; NES joypad Start-button bit

.segment "RODATA"

lut_IntroStoryText:
    .INCBIN "introtext.bin"

.segment "CODE"

.include "enter_intro_story.inc"
.include "intro_story.inc"
.include "intro_story_joy.inc"
