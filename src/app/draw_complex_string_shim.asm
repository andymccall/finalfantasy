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

; Placeholder LUTs. lut_DTE1/lut_DTE2 are indexed by (char - $1A) for chars
; in $1A..$79, and lut_ItemNamePtrTbl is indexed by (item_id * 2) for 8-bit
; item IDs. Title-screen strings stay in the $7A+ plain-tile range and use
; no control codes, so none of these are actually read -- they exist so the
; linker can resolve the symbols and so any accidental overrun goes to
; deterministic zeroes.
lut_DTE1:
    .res $60
lut_DTE2:
    .res $60
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
