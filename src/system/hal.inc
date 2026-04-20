; ---------------------------------------------------------------------------
; hal.inc - Hardware Abstraction Layer interface.
; ---------------------------------------------------------------------------
; The only contract between the app/core tiers and the platform. Any file in
; src/app/ or src/core/ that needs hardware must go through the symbols
; declared here; platform files under src/system/<target>/ provide the
; matching .export'd implementations.
;
; Contract:
;   HAL_Init       -- one-shot platform bring-up. Clobbers A/X/Y.
;   HAL_WaitVblank -- block until the next vertical blank begins.
;                     Clobbers A/X/Y.
; ---------------------------------------------------------------------------

.import HAL_Init
.import HAL_WaitVblank
