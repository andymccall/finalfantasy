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
; machine, HAL_PPU_2007_Write captures the byte into a 2KB nametable mirror
; (NES NT0+NT1) at the latched address and auto-increments.
;
; The platform-specific vblank handler later flushes the mirror out to the
; real display hardware.
; ---------------------------------------------------------------------------

.export HAL_PPUInit
.export HAL_PPU_2006_Write
.export HAL_PPU_2007_Write
.export ppu_nt_mirror

.segment "ZEROPAGE"

ppu_nt_ptr:     .res 2                  ; indirect pointer for (ptr),Y writes

.segment "BSS"

ppu_nt_mirror:  .res $800               ; 2KB mirror of NES NT0 + NT1
ppu_addr_lo:    .res 1
ppu_addr_hi:    .res 1
ppu_addr_latch: .res 1                  ; 0 = next write is high byte
                                        ; 1 = next write is low byte

; ---------------------------------------------------------------------------

.segment "CODE"

; Called once from each platform's HAL_Init. Zeroes the mirror and puts the
; address latch back to "high byte next", matching a PPU whose $2002 has
; just been read.
.proc HAL_PPUInit
    stz ppu_addr_lo
    stz ppu_addr_hi
    stz ppu_addr_latch

    ldx #0
@zap:
    stz ppu_nt_mirror + $000, x
    stz ppu_nt_mirror + $100, x
    stz ppu_nt_mirror + $200, x
    stz ppu_nt_mirror + $300, x
    stz ppu_nt_mirror + $400, x
    stz ppu_nt_mirror + $500, x
    stz ppu_nt_mirror + $600, x
    stz ppu_nt_mirror + $700, x
    inx
    bne @zap
    rts
.endproc

; Accept A as the next byte latched into PPUADDR. Toggle which half is
; written based on ppu_addr_latch.
.proc HAL_PPU_2006_Write
    ldx ppu_addr_latch
    bne @low_byte
    sta ppu_addr_hi
    lda #1
    sta ppu_addr_latch
    rts
@low_byte:
    sta ppu_addr_lo
    stz ppu_addr_latch
    rts
.endproc

; Store A into the mirror at the current 14-bit PPU address, masked to
; the 2KB nametable window, then increment the address by 1 with carry
; from low into high.
.proc HAL_PPU_2007_Write
    pha                                 ; save the input byte

    ; ppu_nt_ptr = ppu_nt_mirror + ((ppu_addr_hi & $07) << 8) + ppu_addr_lo
    ; (16-bit add: low byte add may carry into the high byte)
    lda ppu_addr_hi
    and #$07                            ; clamp to NT0+NT1 (11-bit offset)
    clc
    adc #>ppu_nt_mirror
    sta ppu_nt_ptr + 1

    lda ppu_addr_lo
    clc
    adc #<ppu_nt_mirror
    sta ppu_nt_ptr + 0
    bcc @store
    inc ppu_nt_ptr + 1

@store:
    pla
    ldy #0
    sta (ppu_nt_ptr), y

    inc ppu_addr_lo
    bne @done
    inc ppu_addr_hi
@done:
    rts
.endproc
