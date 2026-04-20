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
- [x16emu](https://www.commanderx16.com/) — Commander X16 emulator
- [Neo6502 emulator](https://www.olimex.com/Products/Retro-Computers/Neo6502/) + `exec.zip`

## Building

```sh
make build-x16    # Commander X16 binary
make build-neo    # Neo6502 binary
make all          # both
```

Each platform builds with its own define (`-D __X16__` or `-D __NEO__`) for conditional assembly where needed.

## Running

```sh
make run-x16      # launches x16emu with FF.PRG (type RUN at the BASIC prompt)
make run-neo      # launches the Neo6502 emulator with ff.neo
```

## Project Structure

```
finalfantasy/
├── cfg/                       # Linker configurations
│   ├── x16.cfg                #   Commander X16 memory map
│   └── neo.cfg                #   Neo6502 memory map
├── src/
│   ├── core/                  # Verbatim FF1 disassembly (read-only, copied in)
│   ├── app/
│   │   └── main.asm           # Entry point + main loop
│   └── system/
│       ├── hal.inc            # HAL interface contract
│       ├── x16/hal.asm        # X16 HAL implementation
│       └── neo/hal.asm        # Neo6502 HAL implementation
├── build/                     # Build output (generated)
├── release/                   # Release archives (generated)
├── Makefile
└── README.md
```

## Architecture

Three tiers, strict separation:

- **`src/core/`** — Verbatim files copied from the FF1 disassembly. Never edited. The original NES code, including its writes to PPU/APU registers, compiles as-is.
- **`src/app/`** — Translator layer. Hosts `main.asm`, the trampolines, and shims that intercept the NES hardware writes coming out of `core/` and dispatch them to the HAL.
- **`src/system/`** — HAL layer. `hal.inc` declares the platform-independent contract; each target directory provides an implementation. The translator never calls X16 or Neo registers directly.

### HAL contract

| Routine          | Purpose                                              |
|------------------|------------------------------------------------------|
| `HAL_Init`       | One-shot platform bring-up (called once at boot).    |
| `HAL_WaitVblank` | Block until the next vertical blank begins.          |

The contract grows as more NES hardware surfaces are intercepted (palette upload, VRAM writes, joypad, APU).

## Current state

- **Project scaffolding** — three-tier source tree, per-platform linker configs, shared Makefile.
- **Clean build & boot** on both platforms — `make run-x16` / `make run-neo` load and run.
- **Vblank-locked heartbeat** — `HAL_WaitVblank` synchronises to the display refresh on both targets and drives a one-cell glyph flicker at the top-left of the screen as a visible proof of life.
  - X16: polls VERA_ISR bit 0 under an SEI/CLI guard; writes to VRAM $1B000.
  - Neo6502: polls `API_FN_FRAME_COUNT`; redraws via `SET_CURSOR_POS` + `WriteCharacter`.

`src/core/` is currently empty. Verbatim disassembly files will be added as each NES subsystem is wired through the HAL.

## Credits

- *Final Fantasy* NES game: Square Enix (originally Square, 1990).
- FF1 NES disassembly this project derives from: [Disch](https://www.romhacking.net/community/1656/).
- Project structure pattern adapted from the `worm` exemplar: Andy McCall.

## Licence

Source code under this repository is published for personal and educational use. FF1 assets remain copyright Square Enix.
