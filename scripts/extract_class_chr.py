#!/usr/bin/env python3
"""
extract_class_chr.py - Pull FF1's class-portrait battle CHR and convert it
to VERA 4bpp sprite pixel layout.

LoadBatSprCHRPalettes_NewGame (bank_0F.asm:10128) uploads class CHR from
BANK_BTLCHR ($09) source $9000 into PPU $1000. Each class occupies 32
tiles (2 pattern-table rows). Party-gen shows 6 unpromoted classes at
tile base $00/$20/$40/$60/$80/$A0; the 6 promoted classes (tile base
$C0..$17F) live in the same CHR region.

Bank 9 layout in the disassembly is split: bin/bank_09_data.bin holds
CPU $8000..$9FFF (the first 8 KB of the 16 KB bank, INCBIN'd at the
top of bank_09.asm). The rest ($A000..$BFFF) is embedded as .BYTE
literals and .INCBIN blocks further down in bank_09.asm. Class CHR
spans $9000..$A7FF -- straddling that boundary -- so we reassemble
the bank by concatenating the bin file with the post-INCBIN .BYTE
stream, then slice out the class-CHR window.

Layout inside the extracted 6 KB:
    offset $0000..$01FF   class 0 (fighter, 32 tiles, 2x16 layout)
    offset $0200..$03FF   class 1 (thief)
    offset $0400..$05FF   class 2 (black belt)
    ...
    offset $1600..$17FF   class 11 (master ninja)

Each class's 2x3 preview sprite is the first 6 tiles of its 32-tile
block, laid out sequentially (DrawSimple2x3Sprite walks tile_id, +1, +2,
+3, +4, +5 -> UL, UR, ML, MR, DL, DR). The remaining 26 tiles in each
block are battle animation frames.

Output: VERA 4bpp sprite pixels, 192 tiles * 32 bytes = 12288 bytes.
Each source 2bpp colour index (0..3) maps directly into the low 2 bits
of the 4bpp nibble (VERA palette-offset-relative index).
"""

import argparse
import re
import sys

# Bank 9 window of class CHR: CPU $9000..$A7FF.
BANK_CPU_BASE   = 0x8000         # bank starts mapping at $8000
CLASS_CPU_BASE  = 0x9000
CLASSES         = 12
TILES_PER_CLASS = 32             # 2 pattern-table rows of 16 tiles each
TILE_BYTES_IN   = 16             # NES 2bpp
TILE_BYTES_OUT  = 32             # VERA 4bpp, 2 pixels per byte

TOTAL_TILES = CLASSES * TILES_PER_CLASS   # 384
SRC_BYTES   = TOTAL_TILES * TILE_BYTES_IN # 6144
DST_BYTES   = TOTAL_TILES * TILE_BYTES_OUT # 12288

BYTE_LITERAL = re.compile(r"\.BYTE\s+(.+)$", re.IGNORECASE)
HEX_VALUE    = re.compile(r"\$([0-9A-Fa-f]{1,2})")
DEC_VALUE    = re.compile(r"(?<![\$A-Fa-f0-9])(\d+)(?![A-Fa-f0-9])")


def parse_byte_lines(asm_path, skip_lines_with_incbin=True):
    """Return a bytes object of every .BYTE literal in the file, in order.

    Strips inline comments. Accepts $HH hex and decimal values. Stops at
    the next .INCBIN so we capture only the .BYTE stream that fills the
    $A000..$AFFF gap between bank_09_data.bin and lut_MinimapNT.
    """
    out = bytearray()
    after_first_incbin = False
    with open(asm_path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.split(";", 1)[0].strip()
            if not stripped:
                continue
            low = stripped.lower()
            if low.startswith(".incbin"):
                if not after_first_incbin:
                    after_first_incbin = True
                    continue
                # Second INCBIN -> stop; whatever followed is NT/CHR data, not our bank fill.
                break
            if not after_first_incbin:
                continue
            m = BYTE_LITERAL.match(stripped)
            if not m:
                continue
            payload = m.group(1)
            # Split on commas (allowing whitespace).
            for raw in payload.split(","):
                tok = raw.strip()
                if not tok:
                    continue
                if tok.startswith("$"):
                    out.append(int(tok[1:], 16))
                else:
                    # decimal
                    out.append(int(tok, 10))
    return bytes(out)


def tile_to_vera(src):
    out = bytearray(TILE_BYTES_OUT)
    for row in range(8):
        plane0 = src[row]
        plane1 = src[row + 8]
        for col_pair in range(4):
            left_bit  = 7 - col_pair * 2
            right_bit = 6 - col_pair * 2
            lp = ((plane0 >> left_bit) & 1) | (((plane1 >> left_bit) & 1) << 1)
            rp = ((plane0 >> right_bit) & 1) | (((plane1 >> right_bit) & 1) << 1)
            out[row * 4 + col_pair] = (lp << 4) | rp
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("bank_bin", help="bin/bank_09_data.bin (first 8 KB of bank 9)")
    ap.add_argument("bank_asm", help="bank_09.asm (supplies .BYTE literals for $A000..)")
    ap.add_argument("output", help="VERA class sprite output (12288 bytes)")
    args = ap.parse_args()

    with open(args.bank_bin, "rb") as f:
        bin_data = f.read()

    byte_data = parse_byte_lines(args.bank_asm)

    # Assemble the bank as CPU $8000..$BFFF. bin_data fills $8000..$9FFF;
    # byte_data fills $A000 onward (first .BYTE stream, up to the minimap
    # INCBIN). We only need through $A800.
    bank = bytearray(0x4000)      # 16 KB
    bank[0:len(bin_data)] = bin_data
    bank[0x2000:0x2000 + len(byte_data)] = byte_data

    src_offset = CLASS_CPU_BASE - BANK_CPU_BASE  # 0x1000
    end_offset = src_offset + SRC_BYTES          # 0x2800
    if len(bank) < end_offset:
        sys.exit(f"bank too short: {len(bank)} < {end_offset}")

    src = bank[src_offset:end_offset]

    # Sanity: reject if the second-half region (past bin_data) is all zero.
    # That would mean byte_data parsing missed the class CHR.
    if src[0x1000:0x1800] == b"\x00" * 0x800:
        sys.exit("class CHR upper half is all zeros -- .BYTE parsing missed it")

    out = bytearray()
    for t in range(TOTAL_TILES):
        out.extend(tile_to_vera(src[t * TILE_BYTES_IN:(t + 1) * TILE_BYTES_IN]))

    assert len(out) == DST_BYTES, f"output size {len(out)} != expected {DST_BYTES}"

    with open(args.output, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
