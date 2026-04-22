; ---------------------------------------------------------------------------
; map_decompress.asm - Overworld map RLE decompression (port-local).
; ---------------------------------------------------------------------------
; FF1's LoadOWMapRow + DecompressMap (bank_0F.asm:4178, 4227) walk a 256-byte
; RLE stream per map row. On the NES the compressed stream can straddle the
; $C000 bank boundary; our flat port keeps the whole bank_owmap.dat blob in
; RODATA as one contiguous region, so the bank-crossing dance isn't needed.
;
; This file hosts two port-tier helpers rather than verbatim extracts:
;   MapDecompressRow   : decompress the N-th OW row into map_row_buf[0..255].
;   ow_ptr_tbl         : the 256-entry row pointer table, rebased to the
;                        linker's RODATA address for the blob.
;
; The on-disk pointers in bank_owmap.dat are ROM-absolute ($8200..$BEA6
; inside the original $8000-based bank). We relocate them by subtracting
; $8000 at use-time and adding the link-time address of ow_map_data. That
; keeps the map blob identical to ROM while making the decoder linker-
; position-independent.
;
; RLE encoding (same as FF1):
;   byte $00..$7F : single tile; emit once, advance stream.
;   byte $80..$FE : run. Low 7 bits = tile; next stream byte = run length
;                   (length 0 == 256 and terminates the row).
;   byte $FF      : row terminator.
; ---------------------------------------------------------------------------

.export MapDecompressRow
.export map_row_buf

.segment "ZEROPAGE"

map_src: .res 2                              ; (zp) indirect pointer into ow_map_data

.segment "BSS"

map_row_buf: .res 256

.segment "RODATA"

; The 512-byte pointer table lives at the very start of bank_owmap.dat.
; We INCBIN the whole blob with ow_map_data as the blob-start label.
; ow_ptr_tbl aliases that same address for readability.
ow_map_data:
    .incbin "bank_owmap.dat"
ow_map_data_end:

ow_ptr_tbl = ow_map_data

.segment "CODE"

; MapDecompressRow(row_in_A) ---------------------------------------------
; Reads 2-byte little-endian pointer from ow_ptr_tbl[A*2], rebases it from
; bank-$8000 to ow_map_data, then RLE-expands up to 256 tiles into
; map_row_buf. Stops at the first $FF or once 256 tiles have been written.
; Clobbers A/X/Y.
.proc MapDecompressRow
    ; --- fetch (lo,hi) from ow_ptr_tbl[A * 2] ------------------------------
    asl                                      ; row * 2 (pointer table stride)
    tax
    lda ow_ptr_tbl, x
    sta map_src + 0
    lda ow_ptr_tbl + 1, x
    sta map_src + 1

    ; --- rebase pointer from $8000-relative to ow_map_data-relative --------
    sec
    lda map_src + 0
    sbc #<$8000
    sta map_src + 0
    lda map_src + 1
    sbc #>$8000
    sta map_src + 1
    clc
    lda map_src + 0
    adc #<ow_map_data
    sta map_src + 0
    lda map_src + 1
    adc #>ow_map_data
    sta map_src + 1

    ldy #0                                   ; Y walks the source stream
    ldx #0                                   ; X = dest index into map_row_buf
@next:
    lda (map_src), y
    cmp #$FF
    beq @done                                ; $FF: row terminator
    bmi @run                                 ; $80..$FE: tile run (bit 7 set)

    ; --- single tile --------------------------------------------------------
    sta map_row_buf, x
    inx
    beq @done                                ; wrapped 256 tiles -> row full
    jsr advance_src
    bra @next

@run:
    and #$7F                                 ; strip bit 7 -> tile id
    pha                                      ; stash tile under the length byte
    jsr advance_src
    lda (map_src), y                         ; A = run length
    tay                                      ; Y = length (0 means 256)
    pla                                      ; A = tile id
@run_loop:
    sta map_row_buf, x
    inx
    beq @done                                ; dest wrapped -> row full
    dey
    bne @run_loop
    ldy #0                                   ; restore Y for source indexing
    jsr advance_src
    bra @next

@done:
    rts
.endproc

; Advance the source pointer by 1 byte, keeping Y = 0 so (zp),Y always
; addresses the "current" source byte. ca65 has no zero-page 16-bit INC,
; so we emit it inline.
.proc advance_src
    inc map_src + 0
    bne :+
    inc map_src + 1
:   rts
.endproc
