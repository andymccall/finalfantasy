# Final Fantasy (X16 / Neo6502)

A personal, educational re-hosting of *Final Fantasy* (NES, 1990) onto the Commander X16 and the Neo6502, written in 65C02 assembly. Based on [Disch's FF1 disassembly](https://www.romhacking.net/community/1656/).

The approach is **re-hosting, not rewriting**: the original NES game logic is used verbatim from the disassembly, and a thin translator layer plus a Hardware Abstraction Layer (HAL) redirects every NES hardware write to the host platform.

*Final Fantasy* is &copy; Square Enix. This project does not contain any Square Enix ROM or artwork — only assembly code derived from a public disassembly, for educational/fan-project purposes.

## Supported Platforms

| Platform      | CPU    | Output     |
|---------------|--------|------------|
| Commander X16 | 65C02  | `FF.PRG`   |
| Neo6502       | 65C02  | `ff.neo`   |

## Prerequisites

- [cc65](https://cc65.github.io/) toolchain (`ca65`, `ld65`)
- Python 3 (build-time CHR converters + PPU hook script)
- [x16emu](https://www.commanderx16.com/) — Commander X16 emulator
- [Neo6502 emulator](https://www.olimex.com/Products/Retro-Computers/Neo6502/) + `exec.zip`
- A local checkout of the FF1 disassembly tree (path hard-coded in the Makefile as `FF1_DIS_ROOT`; point it at your copy).

## Building

```sh
make build-x16    # Commander X16 binary  -> build/x16/FF.PRG
make build-neo    # Neo6502 binary        -> build/neo/ff.neo (+ tiles.gfx)
make all          # both
make clean        # remove build output
```

Each platform builds with its own define (`-D __X16__` or `-D __NEO__`) for conditional assembly where needed.

## Running

```sh
make run-x16      # launch x16emu with FF.PRG and auto-RUN it
make load-x16     # launch x16emu with FF.PRG loaded but at the BASIC prompt
                  #   (type RUN yourself -- useful for recording)
make run-neo      # launch the Neo6502 emulator; ff.neo auto-runs
make load-neo     # stage ff.neo + tiles.gfx into ./storage/ and launch the
                  #   emulator without auto-running (for manual recording)
```

## Project Structure

```
finalfantasy/
├── assets/                    # Pre-staged binary inputs (intro text, etc.)
├── cfg/                       # Linker configurations
│   ├── x16.cfg                #   Commander X16 memory map
│   └── neo.cfg                #   Neo6502 memory map
├── scripts/                   # Build-time Python tools
│   ├── hook_ppu.py            #   Rewrite NES PPU/APU stores into HAL JSRs
│   ├── chr_convert.py         #   FF1 CHR -> X16 tile bitmap
│   ├── chr_to_neo_gfx.py      #   FF1 CHR -> Neo combined .gfx
│   ├── extract_cursor_chr.py  #   Pull cursor CHR out of bank_09.asm
│   └── cursor_to_vera.py      #   Cursor CHR -> VERA 4bpp sprite
├── src/
│   ├── core/                  # Verbatim FF1 disassembly files
│   ├── app/                   # Translator layer: main loop + per-routine shims
│   └── system/
│       ├── hal.inc            #   HAL interface contract (platform-agnostic)
│       ├── ppu.asm            #   Shared virtual NES PPU register emulation
│       ├── apu.asm            #   Shared APU write traps (currently no-ops)
│       ├── x16/               #   Commander X16 HAL implementation
│       └── neo/               #   Neo6502 HAL implementation
├── build/                     # Build output (generated)
├── Makefile
└── README.md
```

## Architecture

Three tiers, strict separation:

- **`src/core/`** — Verbatim files copied from the FF1 disassembly. Never edited. The original NES code, including its writes to PPU/APU registers, compiles as-is. A build-time pass (`scripts/hook_ppu.py`) rewrites each `STA $2006/$2007/$4014/$4015` into a `JSR HAL_PPU_2006_Write`-style call, producing `.inc` files alongside the originals; the `src/app/` shims `.include` those rewritten copies.
- **`src/app/`** — Translator layer. Hosts `main.asm` and one shim per FF1 routine that needs PPU-trapped rewriting (`title_screen_shim.asm`, `draw_box_shim` via `box_drawing_shim.asm`, `intro_story_shim.asm`, etc.). The shim is the only thing that includes the hooked `.inc` form of a core routine.
- **`src/system/`** — HAL layer. `hal.inc` declares the platform-independent contract; `ppu.asm` and `apu.asm` implement shared NES-register emulation (the virtual PPU has its own nametable mirror and palette RAM, drained to the host each vblank). Each target directory under `src/system/` provides platform-specific code: palette programming, tile/sprite upload, controller polling, and the nametable flush.

The translator never calls X16 or Neo registers directly — every host-side effect goes through a HAL symbol.

### HAL contract (summary)

See [src/system/hal.inc](src/system/hal.inc) for the authoritative list with full register/preservation rules.

| Routine                                                      | Purpose                                                   |
|--------------------------------------------------------------|-----------------------------------------------------------|
| `HAL_Init`                                                   | One-shot platform bring-up (palette, tiles, PPU state).   |
| `HAL_WaitVblank`                                             | Block until the next vertical blank; flush nametable.     |
| `HAL_PalettePush`                                            | Push a single palette entry (called from the $3F00 trap). |
| `HAL_PPU_2000/2001/2005_Write`                               | No-op traps for PPUCTRL/PPUMASK/PPUSCROLL.                |
| `HAL_PPU_2006_Write` + `_X` / `_Y` variants                  | Two-write latch for PPUADDR.                              |
| `HAL_PPU_2007_Write` + `_X` / `_Y` variants                  | Route to nametable mirror or palette RAM; auto-increment. |
| `HAL_APU_4014_Write`, `HAL_APU_4015_Write`                   | OAM DMA + APU channel enable traps (currently no-ops).    |
| `HAL_LoadTiles`                                              | Upload the converted FF1 font/border tiles to the host.   |
| `HAL_PollJoy`                                                | Return an 8-bit NES-joypad mask from the host input.      |

FF1 code uses `STX`/`STY` as well as `STA` against `$2006`/`$2007`; the hook script rewrites those too, and the `_X`/`_Y` wrappers preserve the NES "store leaves A untouched" invariant so tight inner loops (e.g. `LDA #$FF` / `STA $2007` × 4 / `DEX` / `BNE`) still work after re-hosting.

### Virtual PPU model

`src/system/ppu.asm` maintains:

- a 2 KB nametable mirror (NT0 + NT1) — `$2007` writes for addresses `$2000..$2FFF` land here,
- a 32-byte palette RAM mirror — `$2007` writes for `$3F00..$3F1F` update it and immediately call `HAL_PalettePush`,
- a write-toggle + 14-bit address latch driven by `$2006`,
- an `nt_dirty` flag that marks the mirror as modified since the last flush.

At vblank, each platform's `HAL_FlushNametable` (in `src/system/<target>/ppu_flush.asm`) walks the 32×30 visible region and redraws it via the host's native tile/draw API, then clears `nt_dirty`. Attribute-table writes (`$23C0..$23FF`) intentionally don't set the dirty flag, so routines that re-write the attribute table every frame (the intro-story palette fade) don't force a full repaint each tick.

## Current state

Boot sequence implemented end-to-end on both platforms:

1. **Platform bring-up** — HAL zeroes the virtual PPU, programs the host palette, and uploads the converted FF1 font + cursor CHR.
2. **Title screen** — `TitleCopyright` + `TitleScreen` run verbatim from `src/core/`; their PPU writes paint the FF1 copyright frame, menu box, "NEW GAME / CONTINUE" strings, and the sprite-plane cursor onto the host display.
3. **Intro story** — `EnterIntroStory` + `IntroStory` stream the 224-byte format-coded text blob through the hooked `DrawComplexString`, producing the scrolling intro text the same way the NES game does.
4. **Controller input** — `HAL_PollJoy` translates the host input (VERA/X16 keyboard + gamepad, Neo Group 7 controller) into an 8-bit NES joypad mask; `ProcessJoyButtons` reads it unchanged.
5. **Menu interaction** — the cursor moves between NEW GAME and CONTINUE; START advances into the story.

### Neo6502 specifics

- Graphics plane is 4bpp, 320×240. The FF1 32×30 nametable is centred with a 32-pixel horizontal gutter.
- Each NES 8×8 tile is packed into the upper-left 8×8 of a 16×16 Neo image (the smallest Draw Image supports); transparent quadrants let neighbouring cells overlap cleanly.
- Fixed 5-colour palette mirroring FF1's menu/title subpalettes (black / mid-grey / dark-blue / white / light-grey); see [src/system/neo/palette.asm](src/system/neo/palette.asm) for the rationale.
- The cursor is a single 16×16 sprite composed from FF1's 4-tile `lutCursor2x2` layout, remapped so it renders in sprite palette 3 (`$0F/$30/$10/$00`).

### Commander X16 specifics

- VERA tile mode drives the background plane; the cursor lives on VERA sprite layer 0.
- FF1 CHR is converted to VERA 4bpp at build time (`scripts/chr_convert.py` for tiles, `scripts/cursor_to_vera.py` for the cursor).
- Palette programming goes through VERA's palette RAM, using the same NES→RGB quantisation as the Neo path.

### Known gaps

- No audio: APU writes are trapped but discarded.
- Only the title / intro-story path of the original ROM is exercised by what's wired through so far. Overworld, battle, and save/continue code paths haven't been brought across yet.
- The intro-story palette fade-in isn't implemented yet — the text appears immediately instead of fading up.

## Credits

- *Final Fantasy* NES game: Square Enix (originally Square, 1990).
- FF1 NES disassembly this project derives from: [Disch](https://www.romhacking.net/community/1656/).
- Project structure pattern adapted from the `worm` exemplar: Andy McCall.

## Licence

Source code under this repository is published for personal and educational use. FF1 assets remain copyright Square Enix.
