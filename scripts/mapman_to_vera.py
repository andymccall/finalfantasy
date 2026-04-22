#!/usr/bin/env python3
"""
mapman_to_vera.py - Convert NES 2bpp mapman CHR to VERA 4bpp sprite pixels.

Input: 256 bytes (16 tiles, 8x8, NES 2bpp planar)
Output: 512 bytes (16 tiles, 8x8, VERA 4bpp packed; two pixels per byte,
        high nibble is left pixel)

Same per-tile conversion as cursor_to_vera.py; pulled into its own
script only because the input tile count differs. 2bpp colour index
maps directly into the low 2 bits of the 4bpp nibble (NES sprite
palette 0..3 -> VERA palette offset + 0..3).
"""

import sys

TILES = 16
TILE_BYTES_IN = 16
TILE_BYTES_OUT = 32


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
    if len(sys.argv) != 3:
        sys.exit("usage: mapman_to_vera.py input.chr output.bin")
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    expected = TILES * TILE_BYTES_IN
    if len(data) != expected:
        sys.exit(f"{sys.argv[1]}: expected {expected} bytes, got {len(data)}")

    out = bytearray()
    for t in range(TILES):
        out.extend(tile_to_vera(data[t * TILE_BYTES_IN:(t + 1) * TILE_BYTES_IN]))

    with open(sys.argv[2], "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
