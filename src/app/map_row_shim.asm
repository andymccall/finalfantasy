; ---------------------------------------------------------------------------
; map_row_shim.asm - Port-local LoadOWMapRow.
; ---------------------------------------------------------------------------
; FF1's LoadOWMapRow (bank_0F.asm:4178) walks lut_OWPtrTbl, rebases the row
; pointer into the $8000 PRG bank, then falls through into DecompressMap --
; which crosses the $C000 bank boundary mid-stream via BIT/BVC/@NextBank.
; Our flat port keeps the whole bank_owmap.dat blob in contiguous RODATA,
; so the verbatim code's bank-swapping is both unnecessary and actively
; wrong (there's no BANK_OWMAP to swap to).
;
; We replace it with a thin wrapper around MapDecompressRow (already port-
; local, lives in map_decompress.asm) that also writes the expanded row
; into FF1's mapdata cache at mapdata + (mapdraw_y & $0F) * 256. That is
; where PrepRowCol expects to find recently-decompressed rows -- it
; reconstructs the source pointer high byte as (mapdraw_y & $0F) |
; >mapdata and reads via (tmp),Y.
;
; Only the OW path is implemented. SM maps (cur_map != 0) will need a
; separate LoadStandardMap wrapper when Step 4+ adds the SM path.
; ---------------------------------------------------------------------------

.import MapDecompressRow
.import map_row_buf
.import mapdata
.import mapflags
.import mapdraw_y

.export LoadOWMapRow
.export PrepSMRowCol

.segment "ZEROPAGE"

map_dst: .res 2                         ; (zp),Y destination in mapdata cache

.segment "CODE"

; LoadOWMapRow --------------------------------------------------------------
; Decompress the OW map row indicated by mapdraw_y (0..255) into the right
; mapdata cache page. Matches FF1's contract: no-op when mapflags bit 0 set
; (standard map path); else load OW row and return.
; Clobbers A/X/Y.
.proc LoadOWMapRow
    lda mapflags
    lsr a                               ; SM flag -> C
    bcs @exit                           ; SM: not ours to handle

    lda mapdraw_y
    jsr MapDecompressRow                ; fills map_row_buf[0..255]

    ; Destination: mapdata + (mapdraw_y & $0F) * 256.
    stz map_dst + 0                     ; low byte is always 0 (page-aligned row)
    lda mapdraw_y
    and #$0F
    clc
    adc #>mapdata
    sta map_dst + 1

    ldy #0
@copy:
    lda map_row_buf, y
    sta (map_dst), y
    iny
    bne @copy

@exit:
    rts
.endproc

; PrepSMRowCol -- stub for the SM branch of PrepRowCol. We only drive the
; OW path in Step 3; mapflags bit 0 is always 0, so PrepRowCol never jumps
; here. The symbol has to resolve at link time, so provide an RTS.
.proc PrepSMRowCol
    rts
.endproc
