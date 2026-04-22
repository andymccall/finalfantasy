; ---------------------------------------------------------------------------
; ppu.asm - Platform-agnostic NES PPU register emulation.
; ---------------------------------------------------------------------------
; The NES writes graphics memory through two memory-mapped registers:
;
;   $2006 (PPUADDR) - 14-bit address pointer, set by two successive byte
;                     writes (high byte first, then low). The register has
;                     an internal write-toggle (latch) that flips with each
;                     write, so callers are free to interleave other code
;                     between the two halves.
;
;   $2007 (PPUDATA) - reads/writes data at the address currently in PPUADDR,
;                     then increments the address by 1 (the NES can also be
;                     configured to increment by 32; FF1 doesn't use that
;                     mode for nametable writes, so the 1-byte stride is
;                     adequate for now).
;
; FF1's code writes to these ports inline throughout the disassembly, not
; only from clean leaf routines. Trapping them wholesale is what the host
; needs. This module is the trap: HAL_PPU_2006_Write runs the latch state
; machine, HAL_PPU_2007_Write routes the byte:
;
;   - address in $2000..$2FFF  -> 2KB nametable mirror (NT0+NT1)
;   - address in $3F00..$3F1F  -> 32-byte palette RAM, then pushed to host
;                                 palette hardware via HAL_PalettePush
;
; The address auto-increments in both cases.
;
; Register preservation: STA on the NES preserves A/X/Y. Because the hook
; script turns those stores into JSRs, the hooks here must preserve the
; same registers or surrounding NES code breaks -- most infamously any
; routine that holds a LUT index in X across a pair of STA $2006 writes.
;
; The platform-specific vblank handler flushes the nametable mirror out to
; the real display hardware. Palette entries go out immediately (no
; mirroring pass), which matches the NES's own behaviour of palette writes
; taking effect as soon as the PPU latches them.
; ---------------------------------------------------------------------------

.import HAL_PalettePush

.export HAL_PPUInit
.export HAL_PPU_2000_Write
.export HAL_PPU_2001_Write
.export HAL_PPU_2005_Write
.export HAL_PPU_2006_Write
.export HAL_PPU_2006_Write_X
.export HAL_PPU_2006_Write_Y
.export HAL_PPU_2007_Write
.export HAL_PPU_2007_Write_X
.export HAL_PPU_2007_Write_Y
.export ppu_nt_mirror
.export palette_ram
.export nt_dirty
.export row_dirty

.segment "ZEROPAGE"

ppu_nt_ptr:     .res 2                  ; indirect pointer for (ptr),Y writes

.segment "BSS"

ppu_nt_mirror:  .res $800               ; 2KB mirror of NES NT0 + NT1
palette_ram:    .res 32                 ; mirror of NES palette RAM $3F00-$3F1F
ppu_addr_lo:    .res 1
ppu_addr_hi:    .res 1
ppu_addr_latch: .res 1                  ; 0 = next write is high byte
                                        ; 1 = next write is low byte
nt_dirty:       .res 1                  ; non-zero iff the mirror has been
                                        ; written since the last flush. The
                                        ; HAL flush routine clears this when
                                        ; it has finished painting.
row_dirty:      .res 30                 ; per-row dirty bits for the 32x30
                                        ; visible nametable. Each entry is
                                        ; non-zero iff the corresponding NT
                                        ; row has cells that changed since
                                        ; the last flush (either a tile
                                        ; byte in that row, or an attribute
                                        ; byte whose metatile covers it).
                                        ; HALs that can paint partial
                                        ; frames (Neo) read this to skip
                                        ; unchanged rows. X16 ignores it
                                        ; and repaints the full grid via
                                        ; VERA, which is fast enough.

; ---------------------------------------------------------------------------

.segment "CODE"

; Called once from each platform's HAL_Init. Zeroes the mirrors and puts
; the address latch back to "high byte next", matching a PPU whose $2002
; has just been read.
.proc HAL_PPUInit
    stz ppu_addr_lo
    stz ppu_addr_hi
    stz ppu_addr_latch
    ; Start dirty so the very first flush paints the (zeroed) mirror, which
    ; overlays the firmware console clear with our black rectangle and
    ; establishes a known-good graphics plane.
    lda #1
    sta nt_dirty

    ldx #0
@zap_nt:
    stz ppu_nt_mirror + $000, x
    stz ppu_nt_mirror + $100, x
    stz ppu_nt_mirror + $200, x
    stz ppu_nt_mirror + $300, x
    stz ppu_nt_mirror + $400, x
    stz ppu_nt_mirror + $500, x
    stz ppu_nt_mirror + $600, x
    stz ppu_nt_mirror + $700, x
    inx
    bne @zap_nt

    ldx #31
@zap_pal:
    stz palette_ram, x
    dex
    bpl @zap_pal

    ; Start with every row dirty so the first flush paints the whole grid.
    ldx #29
@zap_rows:
    lda #1
    sta row_dirty, x
    dex
    bpl @zap_rows
    rts
.endproc

; $2000 (PPUCTRL) on a real NES selects the base nametable, VRAM
; increment direction, sprite/BG pattern tables, sprite size, and the NMI
; enable bit. Our virtual PPU only mirrors NT0 and always increments by
; 1; sprites, NMI, and pattern-table selection are handled out-of-band.
; So the hook is a no-op that consumes the write and preserves A/X/Y.
.proc HAL_PPU_2000_Write
    rts
.endproc

; $2001 (PPUMASK) controls rendering enable, monochrome, colour emphasis.
; The host display is always on, so this hook is a no-op; A/X/Y preserved.
.proc HAL_PPU_2001_Write
    rts
.endproc

; $2005 (PPUSCROLL) latches X then Y scroll across two successive writes
; on a real NES. FF1 writes it mainly to clear scroll after menu draws.
; The host viewport doesn't scroll, so we swallow both halves as a no-op;
; A/X/Y preserved.
.proc HAL_PPU_2005_Write
    rts
.endproc

; Accept A as the next byte latched into PPUADDR. Toggle which half is
; written based on ppu_addr_latch. A, X, Y preserved (see file header).
.proc HAL_PPU_2006_Write
    phx
    ldx ppu_addr_latch
    bne @low_byte
    sta ppu_addr_hi
    ldx #1
    stx ppu_addr_latch
    plx
    rts
@low_byte:
    sta ppu_addr_lo
    stz ppu_addr_latch
    plx
    rts
.endproc

; Route A to the correct backing store for the current 14-bit PPU address,
; then increment the address by 1 with carry from low into high. A, X, Y
; preserved (see file header).
;
; Palette range is detected by ppu_addr_hi == $3F (top 6 bits of the PPU
; address). The low 5 bits of ppu_addr_lo pick the palette slot, matching
; the NES hardware mirror of $3F00..$3FFF down to 32 entries.
.proc HAL_PPU_2007_Write
    phx                                 ; save caller's X
    phy                                 ; save caller's Y
    pha                                 ; save the input byte

    lda ppu_addr_hi
    and #$3F                            ; strip mirror bits above $3FFF
    cmp #$3F
    beq @palette

    ; --- nametable path ----------------------------------------------------
    ; ppu_nt_ptr = ppu_nt_mirror + ((ppu_addr_hi & $07) << 8) + ppu_addr_lo
    lda ppu_addr_hi
    and #$07                            ; clamp to NT0+NT1 (11-bit offset)
    clc
    adc #>ppu_nt_mirror
    sta ppu_nt_ptr + 1

    lda ppu_addr_lo
    clc
    adc #<ppu_nt_mirror
    sta ppu_nt_ptr + 0
    bcc @nt_store
    inc ppu_nt_ptr + 1

@nt_store:
    pla                                 ; restore input byte
    ldy #0
    ; Compare against current mirror byte: if unchanged, skip the dirty
    ; mark. The store itself is unconditional -- HALs may depend on the
    ; mirror always being current after a write path runs. Only the
    ; dirty flags gate on whether the write changed anything.
    ;
    ; Why the skip matters: FF1's IntroStory_WriteAttr rewrites 8 attr
    ; bytes every frame; most of those values already match the mirror,
    ; so marking them dirty would force a full per-frame repaint during
    ; the intro fade. Gating dirty marks on value-change collapses
    ; those redundant attr sweeps into no-ops for the Neo HAL (which
    ; repaints only when nt_dirty / row_dirty are set).
    cmp (ppu_nt_ptr), y
    php                                 ; remember Z (set iff value unchanged)
    sta (ppu_nt_ptr), y
    plp
    beq @advance                        ; value unchanged -- don't mark dirty
    ldx #1
    stx nt_dirty                        ; signal the HAL flush routine

    ; --- row-dirty tracking -------------------------------------------------
    ; Classify the write as tile or attr, then mark the appropriate NT row
    ; (or 4 rows for attr bytes) dirty in row_dirty[]. ppu_addr_hi/lo still
    ; hold the pre-increment PPU address.
    ;
    ; A MUST be preserved on return from HAL_PPU_2007_Write: FF1 holds the
    ; byte-to-write in A across tight $2007 loops (e.g. EnterIntroStory's
    ; LDA #$FF / 4x STA $2007 / DEX / BNE). A real NES STA leaves A
    ; untouched, so we must do the same. Stash A before the classification
    ; scratchwork and pull it back before falling into @advance.
    ;
    ; Tile byte: offset within NT = (ppu_addr_hi & 3) << 8 | ppu_addr_lo.
    ;   row = offset / 32 = (ppu_addr_hi & 3) << 3 | (ppu_addr_lo >> 5).
    ; Attr byte: (ppu_addr_hi & 3) == 3 AND ppu_addr_lo >= $C0.
    ;   index = ppu_addr_lo - $C0 (0..63)
    ;   attr_row = index >> 3 (0..7); NT rows = attr_row * 4 .. * 4 + 3.
    pha                                 ; save byte across classification
    lda ppu_addr_hi
    and #$03
    cmp #$03
    bne @mark_tile_row
    lda ppu_addr_lo
    cmp #$C0
    bcc @mark_tile_row
    ; --- attr path: mark 4 consecutive NT rows dirty ------------------------
    ; base NT row = attr_row * 4 = ((ppu_addr_lo - $C0) >> 3) << 2
    ;             = (ppu_addr_lo - $C0) >> 1  with low 2 bits masked.
    sec
    sbc #$C0                            ; A = attr index 0..63
    lsr                                 ; >> 1
    and #$1C                            ; mask to the attr_row * 4 bits
    tax                                 ; X = base NT row (0/4/8/.../28)
    lda #1
    sta row_dirty + 0, x
    sta row_dirty + 1, x
    ; attr_row 7 covers NT rows 28..31, but rows 30/31 don't exist in
    ; the visible grid -- skip those stores when base=28.
    cpx #28
    beq @row_done
    sta row_dirty + 2, x
    sta row_dirty + 3, x
    bra @row_done

@mark_tile_row:
    ; --- tile path: row = ((hi & 3) << 3) | (lo >> 5) -----------------------
    lda ppu_addr_lo
    lsr
    lsr
    lsr
    lsr
    lsr                                 ; lo >> 5 (0..7)
    sta ppu_nt_ptr                      ; zp scratch
    lda ppu_addr_hi
    and #$03
    asl
    asl
    asl                                 ; (hi & 3) << 3 (0/8/16/24)
    ora ppu_nt_ptr                      ; row (0..31)
    cmp #30
    bcs @row_done                       ; rows 30/31 aren't visible
    tax
    lda #1
    sta row_dirty, x

@row_done:
    pla                                 ; restore byte into A for caller
    bra @advance

    ; --- palette path ------------------------------------------------------
    ; slot = ppu_addr_lo & $1F; palette_ram[slot] = byte; push to host.
@palette:
    lda ppu_addr_lo
    and #$1F
    tax                                 ; X = slot (argument to HAL_PalettePush)
    pla                                 ; A = byte (argument to HAL_PalettePush)
    sta palette_ram, x
    jsr HAL_PalettePush                 ; contract: preserves A/X/Y

@advance:
    inc ppu_addr_lo
    bne @done
    inc ppu_addr_hi
@done:
    ply                                 ; restore caller's Y
    plx                                 ; restore caller's X
    rts
.endproc

; X/Y-sourced variants of the PPU port hooks. FF1 uses STX/STY against
; $2006/$2007 to avoid disturbing A (it holds the character being drawn).
; These wrappers save A, route X or Y through A to the main hook, and
; restore A on return so the original invariant -- NES store preserves
; all registers -- survives.
.proc HAL_PPU_2006_Write_X
    pha
    txa
    jsr HAL_PPU_2006_Write
    pla
    rts
.endproc

.proc HAL_PPU_2006_Write_Y
    pha
    tya
    jsr HAL_PPU_2006_Write
    pla
    rts
.endproc

.proc HAL_PPU_2007_Write_X
    pha
    txa
    jsr HAL_PPU_2007_Write
    pla
    rts
.endproc

.proc HAL_PPU_2007_Write_Y
    pha
    tya
    jsr HAL_PPU_2007_Write
    pla
    rts
.endproc
