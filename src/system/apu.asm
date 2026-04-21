; ---------------------------------------------------------------------------
; apu.asm - Platform-agnostic NES APU register stubs.
; ---------------------------------------------------------------------------
; The NES APU registers live at $4000..$4017. FF1's code writes to a couple
; of them outside of the audio driver's own bank, and the hook script
; rewrites those writes into JSRs so host platforms don't trap unmapped
; addresses:
;
;   $4014 (OAMDMA) - writing a byte B triggers a 256-byte transfer from
;                    CPU $BB00..$BBFF into PPU OAM. FF1 calls this every
;                    frame during menu/title loops, right after building
;                    sprites in a page-aligned RAM buffer. The re-host
;                    doesn't have an OAM plane (sprites come back with the
;                    tile/bitmap renderer), so the hook is a no-op.
;
;   $4015 (APU status / channel enable) - FF1's EnterTitleScreen writes
;                    $0F here to force-enable all four pulse/noise/triangle
;                    channels. The music driver redoes this itself, and
;                    we have no music driver, so the hook is a no-op.
;
; Register preservation: same contract as ppu.asm -- an NES STA preserves
; A/X/Y, and the hook script turns these stores into JSRs, so the hooks
; here must preserve the same registers.
; ---------------------------------------------------------------------------

.export HAL_APU_4014_Write
.export HAL_APU_4015_Write

.segment "CODE"

.proc HAL_APU_4014_Write
    rts
.endproc

.proc HAL_APU_4015_Write
    rts
.endproc
