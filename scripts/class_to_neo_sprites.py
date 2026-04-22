#!/usr/bin/env python3
"""
class_to_neo_sprites.py - Compose FF1's 12 class portraits into 24 Neo
16x16 sprite images (top half + bottom half per class).

The NES draws each class portrait as a 2x3 8x8-tile arrangement (16 wide,
24 tall). The Neo only supports 16x16 or 32x32 sprite images. We split
each portrait into:

    top    : NES rows 0-1 -> 16x16 sprite (visible 16x16)
    bottom : NES row 2 padded with 8 transparent rows -> 16x16 sprite

The class-decoder in HAL_OAMFlush emits two Sprite Set calls per class,
the bottom positioned 16 px below the top.

Output layout (24 * 128 bytes = 3072 bytes total), in class order:
    class 0 top, class 0 bot, class 1 top, class 1 bot, ..., class 11 bot

Per-class palette is baked at compose time. Each class picks NES sprite
palette 0 or 1 from lutClassBatSprPalette (bank_0F.asm:10537):
    class:  0  1  2  3  4  5  6  7  8  9 10 11
    pal :   1  0  0  1  1  0  1  1  0  1  1  0

NES sprite palettes (LoadBattleSpritePalettes, bank_0F.asm:10347):
    pal 0: $0F $28 $18 $21  (transparent / yellow / dark-yellow / lt-blue)
    pal 1: $0F $16 $30 $36  (transparent / red / white / lt-peach)

Neo sprite-row mapping (must match palette.asm sprite_palette_rgb):
    pal 0 nibble (0,1,2,3) -> Neo slots (0, 8, 9, 10)
    pal 1 nibble (0,1,2,3) -> Neo slots (0, 11, 3, 6)

Bank 9 layout: bin/bank_09_data.bin holds CPU $8000..$9FFF (the first 8
KB of the 16 KB bank, INCBIN'd at the top of bank_09.asm). The rest
($A000..$BFFF) is embedded as .BYTE literals. Class CHR spans $9000..$A7FF
-- straddling that boundary. Reuses the same bank-reassembly logic as
extract_class_chr.py.
"""

import argparse
import re
import sys

BANK_CPU_BASE   = 0x8000
CLASS_CPU_BASE  = 0x9000
CLASSES         = 12
TILES_PER_CLASS = 32
TILE_BYTES_NES  = 16
IMG16_BYTES     = 128

# First 6 NES tiles per class compose the 2x3 portrait.
PORTRAIT_TILES_PER_CLASS = 6

# Per-class palette selection (lutClassBatSprPalette).
CLASS_PALETTE = [1, 0, 0, 1, 1, 0,
                 1, 1, 0, 1, 1, 0]

# NES sprite-palette pixel value -> Neo palette slot, per chosen palette.
# Slot 0 is always transparent.
PIXEL_TO_NEO_SLOT = {
    0: {0: 0, 1: 8,  2: 9, 3: 10},     # palette 0: $0F/$28/$18/$21
    1: {0: 0, 1: 11, 2: 3, 3: 6},      # palette 1: $0F/$16/$30/$36
}

BYTE_LITERAL = re.compile(r"\.BYTE\s+(.+)$", re.IGNORECASE)


def parse_byte_lines(asm_path):
    """Return bytes parsed from the first .BYTE block after the bank's
    leading INCBIN (the $A000..$BFFF fill in bank_09.asm). Same logic as
    extract_class_chr.py."""
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
                break
            if not after_first_incbin:
                continue
            m = BYTE_LITERAL.match(stripped)
            if not m:
                continue
            for raw in m.group(1).split(","):
                tok = raw.strip()
                if not tok:
                    continue
                if tok.startswith("$"):
                    out.append(int(tok[1:], 16))
                else:
                    out.append(int(tok, 10))
    return bytes(out)


def nes_tile_to_pixels(src):
    pixels = [[0] * 8 for _ in range(8)]
    for row in range(8):
        p0 = src[row]
        p1 = src[row + 8]
        for col in range(8):
            bit = 7 - col
            lo = (p0 >> bit) & 1
            hi = (p1 >> bit) & 1
            pixels[row][col] = (hi << 1) | lo
    return pixels


def pack_16x16(pixels16):
    data = bytearray(IMG16_BYTES)
    i = 0
    for y in range(16):
        for x in range(0, 16, 2):
            data[i] = (pixels16[y][x] << 4) | pixels16[y][x + 1]
            i += 1
    return bytes(data)


def compose_class(class_chr, palette):
    """class_chr: 6 * 16 bytes (UL, UR, ML, MR, DL, DR NES tiles).
    Returns (top_image_bytes, bot_image_bytes)."""
    pmap = PIXEL_TO_NEO_SLOT[palette]
    tiles = [nes_tile_to_pixels(class_chr[i * 16:(i + 1) * 16])
             for i in range(PORTRAIT_TILES_PER_CLASS)]
    ul, ur, ml, mr, dl, dr = tiles

    # Top: NES rows 0-1 (UL+UR over ML+MR).
    top = [[0] * 16 for _ in range(16)]
    for y in range(8):
        for x in range(8):
            top[y][x]         = pmap[ul[y][x]]
            top[y][x + 8]     = pmap[ur[y][x]]
            top[y + 8][x]     = pmap[ml[y][x]]
            top[y + 8][x + 8] = pmap[mr[y][x]]

    # Bottom: NES row 2 (DL+DR), top half of the 16x16; bottom 8 rows
    # left transparent so the sprite occupies 16x16 with content only
    # in the upper half.
    bot = [[0] * 16 for _ in range(16)]
    for y in range(8):
        for x in range(8):
            bot[y][x]     = pmap[dl[y][x]]
            bot[y][x + 8] = pmap[dr[y][x]]

    return pack_16x16(top), pack_16x16(bot)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("bank_bin", help="bin/bank_09_data.bin (first 8 KB of bank 9)")
    ap.add_argument("bank_asm", help="bank_09.asm (.BYTE fill for $A000+)")
    ap.add_argument("output", help="packed 24 * 128 bytes")
    args = ap.parse_args()

    with open(args.bank_bin, "rb") as f:
        bin_data = f.read()
    byte_data = parse_byte_lines(args.bank_asm)

    bank = bytearray(0x4000)
    bank[0:len(bin_data)] = bin_data
    bank[0x2000:0x2000 + len(byte_data)] = byte_data

    src_offset = CLASS_CPU_BASE - BANK_CPU_BASE  # 0x1000
    class_chr_total = CLASSES * TILES_PER_CLASS * TILE_BYTES_NES
    end_offset = src_offset + class_chr_total
    if len(bank) < end_offset:
        sys.exit(f"bank too short: {len(bank)} < {end_offset}")

    src = bank[src_offset:end_offset]

    if src[0x1000:0x1800] == b"\x00" * 0x800:
        sys.exit("class CHR upper half is all zeros -- .BYTE parsing missed it")

    out = bytearray()
    bytes_per_class = TILES_PER_CLASS * TILE_BYTES_NES   # 512
    for class_id in range(CLASSES):
        base = class_id * bytes_per_class
        portrait_bytes = src[base:base + PORTRAIT_TILES_PER_CLASS * TILE_BYTES_NES]
        palette = CLASS_PALETTE[class_id]
        top, bot = compose_class(portrait_bytes, palette)
        out.extend(top)
        out.extend(bot)

    expected = CLASSES * 2 * IMG16_BYTES
    assert len(out) == expected, f"output {len(out)} != {expected}"

    with open(args.output, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
