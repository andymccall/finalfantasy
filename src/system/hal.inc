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
;   HAL_PalettePush    -- push a single palette entry to the host display.
;                         A = NES colour index (0..$3F), X = slot (0..31).
;                         Called from inside HAL_PPU_2007_Write's palette
;                         trap, so it must preserve A/X/Y.
;   HAL_PPU_2006_Write -- emulate a byte write to the NES PPU address port.
;                         Two successive calls latch a 14-bit address
;                         (high byte first, then low). A is the input byte.
;                         A/X/Y preserved -- NES STA preserves them, and
;                         FF1 code routinely holds indices in X across the
;                         high/low pair of STA $2006 writes.
;   HAL_PPU_2007_Write -- emulate a byte write to the NES PPU data port.
;                         Stores A at the current latched address:
;                           - $2000-$2FFF (any mirror) lands in the 2KB
;                             nametable mirror
;                           - $3F00-$3F1F lands in palette RAM and is
;                             immediately pushed to the host via
;                             HAL_PalettePush
;                         Then auto-increments the address. A/X/Y preserved
;                         (same reason as HAL_PPU_2006_Write).
;   HAL_LoadTiles      -- push the build-time-converted FF1 font into the
;                         host's tile/character memory. Subsequent mirror
;                         bytes within the font's source range render with
;                         FF1 glyphs. Clobbers A/X/Y.
; ---------------------------------------------------------------------------

.import HAL_Init
.import HAL_WaitVblank
.import HAL_PalettePush
.import HAL_PPU_2006_Write
.import HAL_PPU_2007_Write
.import HAL_LoadTiles
