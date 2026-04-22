; ---------------------------------------------------------------------------
; pty_gen_shim.asm - Translator wrapper for NewGamePartyGeneration screen.
; ---------------------------------------------------------------------------
; The verbatim extract in pty_gen.inc pulls four routines from bank_0E.asm:
;
;   PtyGen_DrawScreen   (bank_0E.asm:2683-2696)
;   PtyGen_DrawBoxes    (bank_0E.asm:3016-3044)
;   PtyGen_DrawText     (bank_0E.asm:3055-3070)  -- falls through into...
;   PtyGen_DrawOneText  (bank_0E.asm:3093-3144)
;   lut_PtyGenBuf       (bank_0E.asm:3380-3384)
;
; EnterNewGame seeds the ptygen buffer from lut_PtyGenBuf, calls
; PtyGen_DrawScreen once, then spins on HAL_WaitVblank. The four class
; boxes render with class-name strings inside; no input loop, no cursor,
; no name-input sub-screen.
;
; DrawComplexString's $02 control code ("item name") is what paints the
; class names. Item IDs $F0..$F5 in lut_ItemNamePtrTbl (populated in
; draw_complex_string_shim.asm) resolve to the six class strings.
; ---------------------------------------------------------------------------

.import HAL_PPU_2001_Write
.import HAL_APU_4014_Write
.import HAL_WaitVblank

.import ClearNT
.import TurnMenuScreenOn_ClearOAM
.import DrawBox
.import DrawComplexString

.importzp text_ptr
.importzp tmp
.import cur_bank, ret_bank
.import box_x, box_y, box_wd, box_ht
.import dest_x, dest_y
.import menustall
.import soft2000
.import format_buf
.import ptygen
.import oam
.import joy, joy_a, joy_b, joy_prevdir

.export EnterNewGame
.export NewGamePartyGeneration
.export PtyGen_DrawScreen
.export PtyGen_DrawBoxes
.export PtyGen_DrawText
.export PtyGen_DrawOneText

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
; NewGame_LoadStartingStats and everything downstream (overworld start)
; isn't wired up yet, so we spin on HAL_WaitVblank after the draw.
EnterNewGame:
    jsr NewGamePartyGeneration
    ; PtyGen_DrawScreen ends in TurnMenuScreenOn_ClearOAM, which fills
    ; the oam BUFFER with $F8 but doesn't DMA it to the host sprite
    ; plane. Push the cleared buffer through the sprite HAL now so the
    ; title-screen cursor stops being visible.
    lda #>oam
    jsr HAL_APU_4014_Write
@spin:
    jsr HAL_WaitVblank
    bra @spin

; Slimmed-down host version of NewGamePartyGeneration
; (bank_0E.asm:2581-2673). The NES original loops over 4 characters with
; full input handling; this version stages the ptygen buffer and draws
; the screen once. Class-cycling + name input are not implemented here.
NewGamePartyGeneration:
    ; Seed the ptygen buffer from the LUT ($40 bytes).
    ldx #$3F
@copy:
    lda lut_PtyGenBuf, x
    sta ptygen, x
    dex
    bpl @copy

    jmp PtyGen_DrawScreen

.include "pty_gen.inc"
