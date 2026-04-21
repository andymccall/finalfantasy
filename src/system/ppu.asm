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
.export HAL_PPU_2006_Write
.export HAL_PPU_2007_Write
.export ppu_nt_mirror
.export palette_ram

.segment "ZEROPAGE"

ppu_nt_ptr:     .res 2                  ; indirect pointer for (ptr),Y writes

.segment "BSS"

ppu_nt_mirror:  .res $800               ; 2KB mirror of NES NT0 + NT1
palette_ram:    .res 32                 ; mirror of NES palette RAM $3F00-$3F1F
ppu_addr_lo:    .res 1
ppu_addr_hi:    .res 1
ppu_addr_latch: .res 1                  ; 0 = next write is high byte
                                        ; 1 = next write is low byte

; ---------------------------------------------------------------------------

.segment "CODE"

; Called once from each platform's HAL_Init. Zeroes the mirrors and puts
; the address latch back to "high byte next", matching a PPU whose $2002
; has just been read.
.proc HAL_PPUInit
    stz ppu_addr_lo
    stz ppu_addr_hi
    stz ppu_addr_latch

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
