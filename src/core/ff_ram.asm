; ---------------------------------------------------------------------------
; ff_ram.asm - FF1 RAM buffers allocated for host-side re-hosting.
; ---------------------------------------------------------------------------
; Names mirror the FF1 disassembly so extracted core routines reference
; them unchanged. Layout is flat on the host (no page-1 stack split, no
; NES-style zero-page scarcity), so anything that isn't actually used in
; an indirect-indexed addressing mode can sit in regular BSS.
; ---------------------------------------------------------------------------

.export cur_pal
.export box_x, box_y, box_wd, box_ht
.export dest_x, dest_y
.export ppu_dest
.export tmp
.export soft2000
.export menustall
.exportzp text_ptr                      ; must be ZP for (text_ptr),Y addressing
.export cur_bank, ret_bank
.export tmp_hi
.export char_index
.export format_buf
.export ch_name, ch_class, ch_ailments, ch_weapons, ch_armor, ch_spells

.segment "ZEROPAGE"

; DrawComplexString reads the source string via LDA (text_ptr),Y so the
; pointer must live in zero page. Everything else that DrawComplexString
; touches is only loaded/stored directly, so the rest stays in BSS.
text_ptr:   .res 2

.segment "BSS"

cur_pal:    .res 32       ; FF1 "current palette" -- 32 NES colour indices

; --- Box-drawing inputs / outputs ------------------------------------------
box_x:      .res 1        ; box draw: top-left X in tiles
box_y:      .res 1        ; box draw: top-left Y in tiles
box_wd:     .res 1        ; box draw: width in tiles (incl. borders)
box_ht:     .res 1        ; box draw: height in tiles (incl. borders)
dest_x:     .res 1        ; CoordToNTAddr input / DrawBox inner-body output
dest_y:     .res 1        ; CoordToNTAddr input / DrawBox inner-body output
ppu_dest:   .res 2        ; 16-bit PPU target address (low, high)

; --- Scratch / shadow registers --------------------------------------------
tmp:        .res 16       ; FF1 tmp+0..tmp+15 scratch area
soft2000:   .res 1        ; shadow of PPUCTRL, restored after menu draws
menustall:  .res 1        ; non-zero = MenuCondStall should wait a frame

; --- DrawComplexString state ----------------------------------------------
; cur_bank is the PRG bank DrawComplexString believes it's in; ret_bank is
; the bank to return to on exit. The host has no banking, so SwapPRG_L is a
; stub -- these slots just have to exist and be writable for the verbatim
; code to store into them.
cur_bank:   .res 1
ret_bank:   .res 1
tmp_hi:     .res 3        ; Save/Restore slots for text_ptr (2 bytes) + cur_bank
char_index: .res 1        ; character * $40 -- indexes ch_name/ch_class/etc.

; format_buf is written via format_buf-4 .. format_buf-1 when drawing a
; character name (stat code $00), so it needs four bytes of headroom
; immediately before it. The pad also doubles as scratch for other
; PrintGold/PrintCharStat/PrintPrice stubs that write into the buffer.
            .res 4        ; headroom for format_buf-4..format_buf-1 writes
format_buf: .res 16

; Character stat arrays. Each character occupies $40 bytes, so ch_name+X
; (with X = character*$40) reaches the relevant slot. DrawComplexString
; only indexes with X values produced by char_index, and the title screen
; text doesn't reference any of them -- these are sized minimally to keep
; the symbols resolvable.
ch_name:     .res $100    ; 4 chars/name * 4 chars * $40 stride
ch_class:    .res $100
ch_ailments: .res $100
ch_weapons:  .res $100
ch_armor:    .res $100
ch_spells:   .res $100
