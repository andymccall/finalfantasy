; ---------------------------------------------------------------------------
; hal.inc - Hardware Abstraction Layer interface.
; ---------------------------------------------------------------------------
; The only contract between the app/core tiers and the platform. Any file in
; src/app/ or src/core/ that needs hardware must go through the symbols
; declared here; platform files under src/system/<target>/ provide the
; matching .export'd implementations.
;
; Contract:
;   HAL_Init           -- one-shot platform bring-up. Clobbers A/X/Y.
;   HAL_WaitVblank     -- block until the next vertical blank begins.
;                         Clobbers A/X/Y.
;   HAL_UploadPalette  -- push the 32 NES colour indices currently in
;                         cur_pal to the platform's display palette,
;                         converting each via a platform-specific LUT.
;                         Clobbers A/X/Y.
;   HAL_ShowPaletteStrip -- paint a horizontal strip of solid cells/rects,
;                         one per uploaded palette slot, so the NES->host
;                         mapping can be verified visually. Clobbers A/X/Y.
; ---------------------------------------------------------------------------

.import HAL_Init
.import HAL_WaitVblank
.import HAL_UploadPalette
.import HAL_ShowPaletteStrip
