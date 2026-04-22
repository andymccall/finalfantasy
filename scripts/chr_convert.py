#!/usr/bin/env python3
"""
chr_convert.py - Convert NES 2bpp planar tile data to VERA 4bpp packed tiles.

NES CHR tile layout (16 bytes per 8x8 tile):
    bytes 0-7  : bit plane 0, one byte per row, MSB = leftmost pixel
    bytes 8-15 : bit plane 1, same layout

VERA 4bpp tile layout (32 bytes per 8x8 tile):
    8 rows * 4 bytes per row, two pixels per byte, high nibble = left pixel.
    Each nibble is a palette index 0..15. The VERA renderer adds
    (palette_offset << 4) to a non-zero index before indexing the palette,
    so a nibble value of 0..3 naturally lines up with the four colours of
    an NES attribute group -- as long as the HAL splays NES palette slots
    so group G's four colours land at VERA palette indices (G*16 + 0..3).
    See src/system/x16/palette.asm for that mapping.

We pass the NES 2bpp colour index through unchanged: pixel value 0 -> nibble
0, 1 -> 1, 2 -> 2, 3 -> 3. FF1's font tiles use plane 1 as an opaque-$FF
"box" marker on the NES (so colour 2 paints the glyph background and colour
3 the glyph itself); border tiles use plane 1 meaningfully for grey/white
highlights. Keeping both planes gives us per-tile correct shading for
borders without hurting font glyphs -- the font's colour-2 background lands
on the same palette slot as the border fill, which matches the NES's own
menu palette.
"""

import argparse
import sys


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


def tile_4bpp(src):
    """Pack an 8x8 NES 2bpp tile as 32 bytes of VERA 4bpp packed pixels."""
    pixels = nes_tile_to_pixels(src)
    out = bytearray(32)
    i = 0
    for row in range(8):
        for col_pair in range(4):
            lp = pixels[row][col_pair * 2] & 0x0F
            rp = pixels[row][col_pair * 2 + 1] & 0x0F
            out[i] = (lp << 4) | rp
            i += 1
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("input", help="raw NES 2bpp blob")
    ap.add_argument("output", help="converted VERA 4bpp tile output")
    ap.add_argument("--offset", type=lambda x: int(x, 0), default=0,
                    help="byte offset into the input blob (default 0)")
    ap.add_argument("--tiles", type=int, default=128,
                    help="number of tiles to convert (default 128)")
    ap.add_argument("--format", choices=("x16",), required=True,
                    help="target platform format")
    args = ap.parse_args()

    with open(args.input, "rb") as f:
        data = f.read()

    need = args.offset + args.tiles * 16
    if need > len(data):
        sys.exit(
            f"{args.input}: need {need:#x} bytes, only {len(data):#x} present"
        )

    out = bytearray()
    for t in range(args.tiles):
        base = args.offset + t * 16
        out.extend(tile_4bpp(data[base:base + 16]))

    with open(args.output, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
