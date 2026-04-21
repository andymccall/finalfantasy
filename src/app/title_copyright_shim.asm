; ---------------------------------------------------------------------------
; title_copyright_shim.asm - Translator wrapper around verbatim FF1 routine.
; ---------------------------------------------------------------------------
; The core file src/core/title_copyright.asm is a byte-for-byte extract of
; TitleScreen_Copyright from bank_0E.asm. It deliberately carries no ca65
; directives (no .segment, no .import/.export), because every addition would
; drift it from the disassembly. The hook script rewrites its PPU port
; writes into HAL JSRs; this shim supplies everything else ca65 needs to
; link that extract into our build:
;
;   - .segment "CODE" so the routine lands in the code bank
;   - .import for the HAL hooks the rewritten source now JSRs into
;   - .export for TitleScreen_Copyright so app/main.asm can call it
;
; The .include pulls in the hook-script output from build/core/.
;
; IntroTitlePrepare / ClearNT:
;   On the NES, TitleScreen_Copyright's first action is JSR IntroTitlePrepare,
;   which JMPs to ClearNT (bank_0E.asm:2504). ClearNT walks PPU addresses
;   $2000..$23BF writing $00 (blank nametable) and then $23C0..$23FF writing
;   $FF (attribute table -- every quadrant = palette group 3). The title
;   screen is drawn on top of this, so every cell on the NES resolves to
;   group 3 for its palette -- including the copyright row, the boxes, and
;   the area around them.
;
;   We don't need the $2000..$23BF pass (HAL_PPUInit zeroes the mirror on
;   boot), but we do need the attribute-table fill. Ported as-is modulo
;   the NT-clear loop. The remainder of the NES IntroTitlePrepare -- music,
;   joypad catchers, cursor state -- is out of scope for this milestone.
; ---------------------------------------------------------------------------

.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write

.export TitleScreen_Copyright

.segment "CODE"

IntroTitlePrepare:
    ; Set PPU address to $23C0 (start of attribute table) and fill the
    ; final $40 bytes with $FF. This matches ClearNT's attribute-table
    ; pass on the NES. The shim isn't processed by scripts/hook_ppu.py
    ; (that only runs on src/core/ files), so we JSR the HAL hooks
    ; directly here instead of writing to $2006/$2007 literally.
    lda #$23
    jsr HAL_PPU_2006_Write
    lda #$C0
    jsr HAL_PPU_2006_Write

    ldx #$40
    lda #$FF
@AttrLoop:
    jsr HAL_PPU_2007_Write
    dex
    bne @AttrLoop
    rts

.include "title_copyright.inc"
