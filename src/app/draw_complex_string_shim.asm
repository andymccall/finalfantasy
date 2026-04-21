; ---------------------------------------------------------------------------
; draw_complex_string_shim.asm - Translator wrapper for FF1's DrawComplexString.
; ---------------------------------------------------------------------------
; The verbatim extract in draw_complex_string.inc walks a format-coded
; string, dispatching on control codes ($01-$19) and DTE byte pairs. The
; title-screen strings only use plain tiles ($7A+), so the DTE and item-
; pointer tables are never read and the PrintGold/PrintCharStat/PrintPrice
; branches are never taken. Those symbols still have to link: this shim
; supplies RODATA placeholders for the tables and RTS stubs for the
; subroutines.
;
; Bank-switching (SwapPRG_L + BANK_THIS/BANK_ITEMS/BANK_MENUS) collapses to
; a no-op on the host -- there's one flat address space, so cur_bank and
; ret_bank are just scratch slots and SwapPRG_L is RTS. The DrawComplexString
; code still writes cur_bank / reads ret_bank unchanged; we only need those
; writes to land somewhere.
;
; One subtle contract: DrawComplexString_Exit ends with
;   LDA ret_bank
;   JMP SwapPRG_L
; It expects SwapPRG_L to RTS, which then returns to DrawComplexString's
; caller. An RTS stub satisfies that exactly.
;
; The PPU hooks imported here cover every port that DrawComplexString
; touches: $2002 reads, $2005 double-writes (scroll reset), $2006 STA/STX
; pairs (PPUADDR latch), $2007 STA/STX/STY (PPUDATA, pushed through the
; virtual PPU's palette/nametable trap). $2002 reads are discarded by the
; NES-side code (they exist solely to reset the hardware write-toggle,
; which our virtual PPU doesn't have), so we don't need to trap reads --
; the `LDX $2002` / `LDA $2002` instructions are just harmless loads from
; an unmapped host address.
; ---------------------------------------------------------------------------

.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2006_Write_X
.import HAL_PPU_2006_Write_Y
.import HAL_PPU_2007_Write
.import HAL_PPU_2007_Write_X
.import HAL_PPU_2007_Write_Y

.import CoordToNTAddr
.import MenuCondStall

.importzp text_ptr                      ; must be ZP for (text_ptr),Y addressing
.import cur_bank, ret_bank
.import tmp, tmp_hi
.import dest_x
.import ppu_dest
.import menustall
.import char_index
.import format_buf
.import ch_name, ch_class, ch_ailments, ch_weapons, ch_armor, ch_spells

.export DrawComplexString

; Any non-zero value is fine; DrawComplexString stores the constant into
; cur_bank then calls SwapPRG_L, which is a no-op on the host.
BANK_ITEMS = $00
BANK_MENUS = $00

.segment "RODATA"

; FF1's DTE tables (Dual-Tile Encoding). Indexed by (char - $1A) for chars
; in $1A..$69. Each byte in the source text that falls in that range expands
; to a pair of tiles: lut_DTE1[idx] drawn first, then lut_DTE2[idx]. Copied
; byte-for-byte from bank_0F.asm:11303-11315. Bytes $6A..$79 also route
; through DTE but the original comment notes that range "will draw crap" --
; we pad to the full $60 range with $FF (blank-space tile) so overruns
; stay visually inert instead of drawing whatever the next RODATA byte is.
;
; lut_ItemNamePtrTbl is indexed by item_id * 2 (8-bit item IDs). The intro
; story and title screen never reach a control code that consults it, so
; zeros are fine.
lut_DTE1:
    .byte $A8,$FF,$B7,$AB, $B6,$AC,$FF,$B7, $A4,$B5,$FF,$A8, $B2,$A7,$B7,$B1
    .byte $B1,$A8,$A8,$FF, $B2,$A4,$AC,$FF, $B9,$FF,$B0,$B2, $FF,$B6,$FF,$A4
    .byte $A8,$B1,$B2,$AB, $B6,$A4,$A8,$AB, $FF,$FF,$B5,$AF, $B2,$AA,$A6,$B2
    .byte $90,$BC,$B2,$B5, $AF,$FF,$FF,$A6, $96,$B7,$A9,$B8, $BC,$B7,$AF,$FF
    .byte $B1,$AC,$B5,$BA, $A4,$A4,$BA,$AC, $A5,$B5,$B8,$FF, $AA,$FF,$AF,$C3
    .res  $60 - 80, $FF

lut_DTE2:
    .byte $FF,$B7,$AB,$A8, $FF,$B1,$A4,$FF, $B1,$A8,$B6,$B5, $B8,$FF,$B2,$FF
    .byte $AA,$A4,$B6,$AC, $FF,$B5,$B6,$A5, $A8,$BA,$A8,$B5, $B2,$B7,$A6,$B7
    .byte $B1,$A7,$B1,$AC, $A8,$B6,$A7,$A4, $B0,$A9,$FF,$A8, $BA,$FF,$A8,$B0
    .byte $92,$FF,$A9,$B2, $AF,$B3,$BC,$A4, $8A,$A8,$FF,$B5, $B2,$AC,$FF,$AB
    .byte $A8,$B7,$AC,$A4, $A6,$AF,$A8,$AF, $A8,$B6,$FF,$AF, $A8,$A7,$AC,$C3
    .res  $60 - 80, $FF

lut_ItemNamePtrTbl:
    .res $200

.segment "CODE"

; Bank swap is a no-op on the host. The verbatim code calls this after
; loading the target bank into A; we just return and ignore A.
SwapPRG_L:
    rts

; PrintGold / PrintCharStat / PrintPrice live in BANK_MENUS on the NES.
; DrawComplexString only reaches them via control codes $04 (gold),
; $10-$13 with stat sub-code $02-0B or $2C+ (stat), and $03 (price). None
; of those codes appear in the title text, so the stubs are unreachable
; and just have to link.
PrintGold:
    rts
PrintCharStat:
    rts
PrintPrice:
    rts

.include "draw_complex_string.inc"
