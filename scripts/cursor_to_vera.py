#!/usr/bin/env python3
"""
cursor_to_vera.py - Convert NES 2bpp cursor CHR to VERA 4bpp sprite pixels.

Input: 64 bytes (4 tiles, 8x8, NES 2bpp planar)
Output: 128 bytes (4 tiles, 8x8, VERA 4bpp packed: two pixels per byte,
        high nibble is left pixel)

VERA sprite pixels are indices into a 16-colour palette. We map the
2bpp colour index straight into the low 2 bits of the 4bpp nibble:
    0 -> $0 (transparent on VERA)
    1 -> $1
    2 -> $2
    3 -> $3

Palette slot configuration is the HAL's job -- it just needs slots
1/2/3 populated with something visible (white is fine for the cursor).
"""

import sys


def tile_to_vera(src):
    out = bytearray(32)
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
        sys.exit("usage: cursor_to_vera.py input.chr output.bin")
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    if len(data) != 64:
        sys.exit(f"{sys.argv[1]}: expected 64 bytes, got {len(data)}")

    out = bytearray()
    for t in range(4):
        out.extend(tile_to_vera(data[t * 16:(t + 1) * 16]))

    with open(sys.argv[2], "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
