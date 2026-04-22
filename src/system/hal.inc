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
;   HAL_PPU_2000_Write -- emulate a byte write to PPUCTRL. Nametable base
;   HAL_PPU_2001_Write    select, VRAM increment direction, sprite/BG
;   HAL_PPU_2005_Write    pattern tables, NMI enable, rendering mask, and
;                         X/Y scroll live behind these ports on a real
;                         NES. The host virtual PPU doesn't emulate any
;                         of those knobs, so all three hooks are no-ops
;                         that consume A and preserve A/X/Y (the NES STA
;                         invariant the hook script relies on).
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
;   HAL_PPU_2006_Write_X -- X-sourced variants of the PPUADDR/PPUDATA hooks.
;   HAL_PPU_2006_Write_Y    FF1 uses STX/STY against $2006/$2007 to avoid
;   HAL_PPU_2007_Write_X    disturbing A (e.g. DrawComplexString holds the
;   HAL_PPU_2007_Write_Y    character being drawn in A while latching the
;                           target address through X). The wrappers save A,
;                           route X or Y through A into the main hook, and
;                           restore A on return, so the NES "store preserves
;                           all registers" invariant holds for these callers
;                           too.
;   HAL_APU_4014_Write -- accept a byte write to $4014 (OAMDMA). On a real
;                         NES this starts a 256-byte OAM transfer from CPU
;                         page $BB00 into PPU OAM. FF1 uses it every frame
;                         during menu/title loops. The hook tail-calls into
;                         a platform-supplied HAL_OAMFlush (exported from
;                         src/system/<target>/sprites.asm) that reads the
;                         flat oam[] BSS buffer and updates the host's
;                         sprite plane. A/X/Y preserved.
;   HAL_APU_4015_Write -- accept a byte write to $4015 (APU channel
;                         enable). The re-host has no audio driver so the
;                         hook is a no-op; A/X/Y preserved.
;   HAL_LoadTiles      -- push the build-time-converted FF1 font into the
;                         host's tile/character memory. Subsequent mirror
;                         bytes within the font's source range render with
;                         FF1 glyphs. Clobbers A/X/Y.
;   HAL_LoadTileset    -- A = tileset id. Swap the resident tileset.
;                         IDs: 0 = font/menu, 1 = overworld map.
;                         Neo does a Group $03 Load File into
;                         gfxObjectMemory; X16 is a no-op after boot
;                         (both tilesets already uploaded to disjoint
;                         VRAM regions). Clobbers A/X/Y.
;   HAL_SetTileMode    -- A = tile-mode id. Tells ppu_flush how to map
;                         nametable bytes to host tile slots.
;                         0 = menu  (NES $00..$7F -> blank,
;                                    NES $80..$FF -> tile id byte-$80)
;                         1 = map   (NES $00..$7F -> tile id byte,
;                                    NES $80..$FF -> unused).
;                         Also disables the attribute-group gating used
;                         by the intro-story fade on Neo -- map mode
;                         draws every cell unconditionally.
;                         Clobbers A/X/Y.
;   HAL_PollJoy        -- sample the host's current controller/keyboard
;                         state and return an 8-bit NES-joypad mask in A:
;                           bit 0 Right, bit 1 Left, bit 2 Down, bit 3 Up,
;                           bit 4 Start, bit 5 Select, bit 6 B, bit 7 A.
;                         Non-blocking; always returns immediately.
;                         Clobbers A/X/Y.
; ---------------------------------------------------------------------------

.import HAL_Init
.import HAL_WaitVblank
.import HAL_PalettePush
.import HAL_PPU_2000_Write
.import HAL_PPU_2001_Write
.import HAL_PPU_2005_Write
.import HAL_PPU_2006_Write
.import HAL_PPU_2006_Write_X
.import HAL_PPU_2006_Write_Y
.import HAL_PPU_2007_Write
.import HAL_PPU_2007_Write_X
.import HAL_PPU_2007_Write_Y
.import HAL_APU_4014_Write
.import HAL_APU_4015_Write
.import HAL_LoadTiles
.import HAL_LoadTileset
.import HAL_SetTileMode
.import HAL_PollJoy
