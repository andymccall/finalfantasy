# AM3 — Andy McCall's Memory Mapper (Commander X16)

## Status

Draft v0.1 — design document for the banking layer that will be implemented
as Milestone 3 of the Final Fantasy port. Intended to be reusable across
other Commander X16 game projects.

## Summary in one paragraph

AM3 is a small (~100 LOC) 6502 runtime that exposes the Commander X16's
banked-RAM window at `$A000-$BFFF` as a pool of 8KB banks that can hold
either code or data. Application code asks AM3 to "call routine X in bank
N"; AM3 saves the current bank register, switches to bank N, jumps to the
routine, and restores the previous bank on return. This is the same mental
model as the NES MMC1 mapper or a C64 REU pager: your program runs mostly
in resident RAM and reaches into banked RAM when it needs one of the many
things that don't all fit at once.

## Why this exists

The X16 only has ~39KB of contiguous RAM below the I/O region at
`$9F00-$9FFF`. Non-trivial game ports (especially NES titles with multiple
map banks, party state, battle engine, menu system, music, etc.) blow past
that ceiling quickly. The X16 has up to 2MB of banked RAM at `$A000-$BFFF`
swapped through a single byte at `$00`; AM3 gives that a principled
developer-facing API instead of scattering raw `sta $00` calls through the
codebase.

Design goals, in priority order:

1. **Correctness under IRQs.** The bank register is machine-global state;
   we must preserve it across interrupts.
2. **Low friction to adopt.** A caller should be able to replace `jsr
   SomeBigRoutine` with `AM3_CallBanked #BANK_X, SomeBigRoutine` and be
   done.
3. **No hidden cost on the hot path.** Routines that never leave resident
   RAM should pay zero overhead.
4. **Reusable across X16 game projects.** The module should live in its
   own directory with a public header and a short integration guide.

Non-goals:

- **Hot-swapping code from disk.** AM3 assumes all banks are already
   populated in RAM at boot. Disk-based overlay loading is a separate
   feature.
- **Automatic partitioning.** AM3 doesn't decide which functions go in
   which bank; the game author describes that in their ca65 linker config.
- **Neo6502 support.** Neo has no banking analogue; see the dedicated
   Neo section below.

## Commander X16 memory recap

```
$0000-$00FF  Zero page (registers 0/1 are bank selectors)
$0100-$01FF  CPU stack
$0200-$07FF  KERNAL / system reserved
$0801-$9EFF  "Main RAM" — always visible, always the same bytes
$9F00-$9FFF  I/O registers (VERA, YM2151, VIA, SD card, etc.)
$A000-$BFFF  Banked RAM window — 8KB slot, bank N selected by writing N to $00
$C000-$FFFF  ROM (KERNAL and friends)
```

With a 2MB expansion the banked-RAM pool is 256 banks × 8KB = 2MB. Stock
X16 ships with 64 banks = 512KB. AM3 treats the bank count as a
compile-time constant that can be adjusted per project.

The bank-select register is at address `$00` (zero-page location 0). In
ca65 terms this is the symbol typically named `BANK_RAM` or `RAM_BANK`.
Writing a value there causes the next memory access in `$A000-$BFFF` to
map to that 8KB slice of physical RAM.

(Location `$01` selects the ROM bank visible at `$C000-$DFFF`; AM3 does
not currently touch ROM banking, because application code runs out of
low RAM and has no reason to call into swappable ROM.)

**Bank 0 is reserved by the X16 KERNAL** for its own scratch use -- any
data the program writes into bank 0 at `$A000-$BFFF` is liable to be
overwritten by KERNAL IRQ activity between frames, so bank 0 must NOT
be used for game state. AM3's "resident bank" (the bank pinned at
`AM3_Init` and restored after banked calls) is bank 1 by default, and
the first switchable bank is bank 2. Adjust via `AM3_RESIDENT_BANK` /
`AM3_FIRST_USER_BANK` in `am3_cfg.inc` if a project has different
reservations.

## How MMC1 compares

FF1 on NES used MMC1 to swap PRG chunks. Two differences worth flagging,
because they shape AM3's design:

- **MMC1 swaps into the code region itself** (`$8000-$BFFF`), so the
   currently-executing instructions can vanish mid-stream if you're not
   careful. AM3 only swaps the data region at `$A000-$BFFF`; the caller
   always runs from always-visible RAM, so the executing PC never drops
   out from under us when we write the bank register.
- **MMC1 was slow to switch** (serial shift register, 5 writes per swap).
   AM3 is one `sta $00` — effectively free.

The practical upshot: AM3 can afford to be invoked eagerly at call
boundaries, whereas MMC1 games had to batch banked work to amortize
switching cost. If a banked routine in AM3 itself calls into another
banked routine, that's fine — switch, return, switch back, each is one
store.

## Public API

All symbols live in the `am3` namespace (ca65 supports this via
`.scope`). Public entry points are exported.

### `AM3_Init`

```
AM3_Init
  inputs:  none
  outputs: none
  trashes: A
```

Initialise runtime state. Must be called exactly once at program start,
before any other AM3 call. Stores `0` in the bank register so early
references to `$A000-$BFFF` land in a well-defined bank.

### `AM3_SwitchBank`

```
AM3_SwitchBank
  inputs:  A = target bank number
  outputs: none
  trashes: nothing (A is preserved)
```

Raw bank switch. Saves the previous bank into the AM3 one-slot save stack
(so `AM3_RestoreBank` can undo it) and writes the new bank to `$00`. This
is the low-level primitive; most callers use `AM3_CallBanked` instead.

### `AM3_RestoreBank`

```
AM3_RestoreBank
  inputs:  none
  outputs: none
  trashes: A
```

Pop the saved bank off AM3's one-slot save stack and restore it.

### `AM3_CallBanked`

```
AM3_CallBanked
  inputs:  A = target bank number
           X:Y = 16-bit address of routine in that bank (X=hi, Y=lo)
                 ... (or via a small trampoline macro, see below)
  outputs: whatever the callee returned (A/X/Y carry through unchanged
           except as modified by the callee)
  trashes: A/X/Y as per the callee
```

Wrapper around switch + JSR + restore. The typical ca65 macro form is:

```asm
    .macro CALL_BANKED routine
        lda #.bankbyte(routine)
        ldx #>routine
        ldy #<routine
        jsr AM3_CallBanked
    .endmacro
```

`.bankbyte` is a ca65 linker-side operator that yields the bank number
the linker assigned to `routine`'s segment. This means the author writes
`CALL_BANKED PartyMenuOpen` and the correct bank is filled in at link
time — no manual bank-number bookkeeping in the caller.

### `AM3_CopyFromBank`

```
AM3_CopyFromBank
  inputs:  A    = source bank
           $R0  = source address in $A000-$BFFF (16-bit, ZP pair)
           $R2  = dest address in resident RAM  (16-bit, ZP pair)
           $R4  = byte count (16-bit)
  outputs: none
  trashes: A, X, Y, $R0, $R2, $R4 (consumed)
```

Bulk copy helper. Switches to the source bank, copies `count` bytes from
`(source)` to `(dest)`, restores the previous bank. Used when a banked
resource (map row, sprite frame, music pattern) needs to be materialised
into a resident buffer for code that doesn't itself know how to page.

### IRQ safety

The KERNAL's IRQ handler touches the bank register in its own right
(for jiffy-clock / keyboard scan). If a user IRQ handler is installed
(we currently don't install one, but other projects might), it MUST
save/restore `$00` across its body, or call `AM3_IrqEnter` /
`AM3_IrqLeave` to do that for it. AM3's own calls run with interrupts
enabled because the KERNAL IRQ does preserve `$00` before returning.

## Linker integration

Each bank is a separate ca65 memory region and segment. A project-level
config fragment looks like:

```
# cfg/x16_am3.cfg
MEMORY {
    ZP:      start = $0022, size = $0030, type = rw;
    HEADER:  start = $0000, size = $0002, file = %O, fill = yes;
    MAIN:    start = $0801, size = $8700, file = %O;
    BSSAREA: start = $8A00, size = $1500, type = rw;

    # Bank 0 is KERNAL scratch -- do NOT touch. Bank 1 is AM3's resident
    # bank: MAPDATA lives here and AM3_Init pins $00 to 1. Switchable
    # banks start at bank 2.
    MAPAREA: start = $A000, size = $1000, type = rw, bank = 1;

    # Banked RAM (switchable): one region per bank. File output is still
    # one .PRG, padded with fill bytes at the bank boundaries. A loader
    # helper reads this and uploads each bank to RAM at boot.
    BANK02:  start = $A000, size = $2000, file = %O, fill = yes, bank = 2;
    BANK03:  start = $A000, size = $2000, file = %O, fill = yes, bank = 3;
    # ... up to BANKFF for a full 2MB build
}

SEGMENTS {
    ZEROPAGE:   load = ZP,       type = zp,  define = yes;
    STARTUP:    load = MAIN,     type = ro;
    CODE:       load = MAIN,     type = ro;
    RODATA:     load = MAIN,     type = ro;
    DATA:       load = MAIN,     type = rw;
    BSS:        load = BSSAREA,  type = bss, define = yes;
    MAPDATA:    load = MAPAREA,  type = bss, define = yes;

    BANKED_02:  load = BANK02,   type = ro;
    BANKED_03:  load = BANK03,   type = ro;
    # ...
}
```

In source files, routines that should live in a bank use
`.segment "BANKED_XX"` instead of `.segment "CODE"`. The linker
arranges placement; `.bankbyte(symbol)` resolves to the bank number
at link time so callers don't have to track it by hand.

### Boot loader

At program entry, AM3 needs the banked regions populated. One approach:

1. Build produces a single `.PRG` file padded to `header + main +
   banks * 8KB`.
2. A ~100-byte boot stub in `STARTUP` reads the bank blobs from disk
   sector-by-sector into the right banks using KERNAL file I/O + one
   `AM3_SwitchBank` per bank.
3. Once banks are populated, jump to `main`.

Alternative: load all banks as separate files via a build-time
multi-file loader; cleaner for development iteration, uglier for
shipping. TBD when we implement.

## Directory layout

```
src/mbc/am3/
├── am3.asm           ; runtime implementation (~100 LOC)
├── am3.inc           ; public API declarations (.import block)
├── am3_macros.inc    ; CALL_BANKED and friends
└── am3_cfg.inc       ; project-level bank count, symbol names
```

`am3_cfg.inc` is the single file a new project edits to adopt AM3:

```asm
AM3_BANK_COUNT     = 64          ; or 256 for 2MB
AM3_BANK_REGISTER  = $00
AM3_STACK_DEPTH    = 4           ; max nested banked calls
```

The module itself (`am3.asm`, `am3.inc`, `am3_macros.inc`) is copied
unchanged into `src/mbc/am3/` of the adopting project.

## FF port integration plan

Ordered so each step is independently testable.

1. **Scaffolding.** Create `src/mbc/am3/`, add the empty module skeleton
   + `AM3_Init` stub that just stores `0` to `$00`. Wire it into the
   X16 `HAL_Init` path so every build calls it. No behaviour change.

2. **Pin resident bank.** `AM3_Init` writes `AM3_RESIDENT_BANK` (bank 1)
   to `$00`. MAPDATA at `$A000-$AFFF` lives in that bank; the row cache
   is therefore always visible between frames and the KERNAL's bank-0
   scratch activity never touches it.

3. **Primitives.** Implement the real `AM3_SwitchBank`, `AM3_RestoreBank`,
   `AM3_CallBanked`, and `AM3_CopyFromBank`. Add the saved-bank stack in
   BSS. No callers yet; unit-test via a scratch banked segment.

4. **Config fragment.** Extend `cfg/x16.cfg` with a `BANK02` region and
   `BANKED_02` segment mapped at bank 2 (first user bank; bank 0 is
   KERNAL, bank 1 is the resident MAPDATA slab). Verify the build still
   produces working bytes for resident code; the new region will be
   empty for now.

5. **First victim: party-gen portrait/name lookup table.** Move
   `lut_ItemNamePtrTbl` into `BANKED_02`. Rewrite its one caller to go
   through `AM3_CopyFromBank` (or a tiny inline switch/restore wrapper
   since the caller is read-only). Verify party-gen still works.

6. **Battle engine.** (When we get there.) Battle code is self-contained
   and called from a single entry point, so it's the canonical banked
   feature. Lives entirely in `BANKED_03`.

7. **Menu system, shops, etc.** Each lives in its own bank.

## Open questions

- **Nested banked calls.** Do we need a stack of saved banks (so routine
   A in bank 0 can call B in bank 1, which calls C in bank 2, all
   returning cleanly)? MMC1 games handled this with an explicit push/pop
   of the "current bank" variable. First draft assumes a depth of 4 is
   enough; revisit if we hit a case.
- **Shared RODATA across banks.** If two banks both need access to the
   font, do we duplicate it (simple, wastes a few KB) or have a
   "resident RODATA" partition that's always visible (more alignment
   work)? First draft duplicates.
- **Disk loader details.** Spelled out once the X16 KERNAL file-I/O
   wrappers settle (we currently don't touch the file system).

## Neo6502 — why AM3 doesn't apply

The Neo6502 exposes a flat 62KB address space (`$0800-$FEFF`) with no
hardware bank-switching register. There is no equivalent of `$00` to
write. The Neo's 2MB of flash lives behind the firmware's SD-card API
and must be pulled into RAM via `API_GROUP_FILE` calls, one file at a
time, which is a very different model from AM3's instant-switch.

When the Neo port eventually runs out of room, the answer will be a
separate overlay-loading module — something like `NEO_OVERLAY_Load` that
reads a blob from SD into a reserved RAM region, with the application
agreeing at design time that "calling overlay X will clobber overlay
region". That's a different enough problem to warrant its own design
doc when we get there; AM3 is deliberately scoped to X16.

## Version history

- **v0.1 (2026-04-22).** Initial draft, written before implementation.
  Decisions may shift as real code gets written.
