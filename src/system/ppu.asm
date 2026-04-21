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
    sta (ppu_nt_ptr), y

    ; nt_dirty only needs to be set for writes that affect the visible
    ; 32x30 tile grid -- PPU offsets $000..$3BF within each nametable.
    ; Attribute-table writes ($3C0..$3FF of each NT) change palette
    ; selection but not the tile bytes our flush routine looks at, so
    ; setting nt_dirty for them would force a repaint on every frame
    ; during the intro-story fade (IntroStory_WriteAttr runs each frame
    ; and writes only to $23C0..$23FF). That re-introduces the flicker
    ; from overrun scanout.
    ;
    ; Attribute region: (ppu_addr_hi & $03) == $03 AND ppu_addr_lo >= $C0.
    ; A must NOT be clobbered on return -- FF1 keeps the byte-to-write in
    ; A across tight $2007 loops (e.g. EnterIntroStory's LDA #$FF / loop:
    ; 4x STA $2007 / DEX / BNE), and a real NES STA leaves A untouched.
    ; We stash A on the stack for the duration of the classification and
    ; restore it before @advance. X is already saved on entry (phx/plx).
    pha
    lda ppu_addr_hi
    and #$03
    cmp #$03
    bne @mark_dirty
    lda ppu_addr_lo
    cmp #$C0
    bcs @nt_done                        ; attribute byte -- skip nt_dirty

@mark_dirty:
    ldx #1
    stx nt_dirty                        ; signal the HAL flush routine
@nt_done:
    pla                                 ; restore caller's A
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
