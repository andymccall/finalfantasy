#!/usr/bin/env python3
"""
mapman_to_neo_gfx.py - Compose FF1's Fighter mapman into 8 Neo 16x16 sprites.

Input: 256 bytes of bank_02 $1000 (16 NES 2bpp tiles, Fighter class).
Output: 8 * 128 bytes = 1024 bytes of Neo 16x16 sprite images packed
tightly, in pose order:

    idx 0 = right frame 0
    idx 1 = right frame 1
    idx 2 = left  frame 0
    idx 3 = left  frame 1
    idx 4 = up    frame 0
    idx 5 = up    frame 1
    idx 6 = down  frame 0
    idx 7 = down  frame 1

Each pose composes four NES 8x8 tiles into one 16x16 Neo image using
FF1's (UL, DL, UR, DR) quadrant order. The LUT bakes per-tile H-flip
from attr bit 6 directly into the image -- Neo's Sprite Set P6 flip
would flip the WHOLE 16x16 block, which isn't what FF1 wants when
only some quadrants are flipped (e.g. up/down walk cycles).

Palette mapping is per-quadrant: each of the four 8x8 tiles that make
up a mapman pose carries its own NES sprite-palette selection (attr
bit 0 = palette 0 vs palette 1), so we pick the Neo palette slots
quadrant-by-quadrant when composing the 16x16 image.

FF1 OW sprite palettes (from load_map_pal sprite half):
    palette 0: $0F/$0F/$12/$36  (black / black / dark-blue / light-red)
    palette 1: $0F/$0F/$27/$36  (black / black / skin-orange / light-red)

Neo palette slots (see palette.asm):
    0 = transparent-black (sprite nibble 0 composites transparent)
    1 = mid-grey        2 = dark-blue       3 = white
    4 = light-grey      5 = skin-orange     6 = light-red
    7 = opaque black

Mapping:
    NES pixel 0 -> Neo slot 0  (transparent)
    NES pixel 1 -> Neo slot 7  (opaque black, both palettes)
    NES pixel 2 -> Neo slot 2 (palette 0) or slot 5 (palette 1)
    NES pixel 3 -> Neo slot 6  (light-red, both palettes)
"""

import argparse
import sys

IMG16_BYTES = 128
POSE_COUNT = 8

# (UL, UR, DL, DR) attr byte from lut_PlayerMapmanSprTbl. Bit 6 = H-flip.
# The LUT lays out (UL, DL, UR, DR) per 2x2 block; we list tiles + attrs
# in that same order here.
POSES = [
    # right frame 0
    [(0x09, 0x40), (0x0B, 0x41), (0x08, 0x40), (0x0A, 0x41)],
    # right frame 1
    [(0x0D, 0x40), (0x0F, 0x41), (0x0C, 0x40), (0x0E, 0x41)],
    # left  frame 0
    [(0x08, 0x00), (0x0A, 0x01), (0x09, 0x00), (0x0B, 0x01)],
    # left  frame 1
    [(0x0C, 0x00), (0x0E, 0x01), (0x0D, 0x00), (0x0F, 0x01)],
    # up    frame 0
    [(0x04, 0x00), (0x06, 0x01), (0x05, 0x00), (0x07, 0x01)],
    # up    frame 1
    [(0x04, 0x00), (0x07, 0x41), (0x05, 0x00), (0x06, 0x41)],
    # down  frame 0
    [(0x00, 0x00), (0x02, 0x01), (0x01, 0x00), (0x03, 0x01)],
    # down  frame 1
    [(0x00, 0x00), (0x03, 0x41), (0x01, 0x00), (0x02, 0x41)],
]

# 2bpp -> Neo palette slot, per NES sprite palette (attr byte bit 0).
# See module docstring for palette rationale.
PALETTE_MAPS = {
    0: {0: 0, 1: 7, 2: 2, 3: 6},        # palette 0: dark-blue + light-red
    1: {0: 0, 1: 7, 2: 5, 3: 6},        # palette 1: skin-orange + light-red
}


def nes_tile_to_slots(src, hflip, palette):
    pmap = PALETTE_MAPS[palette]
    pixels = [[0] * 8 for _ in range(8)]
    for row in range(8):
        p0 = src[row]
        p1 = src[row + 8]
        for col in range(8):
            bit = 7 - col
            lo = (p0 >> bit) & 1
            hi = (p1 >> bit) & 1
            pixels[row][col] = pmap[(hi << 1) | lo]
    if hflip:
        for row in range(8):
            pixels[row].reverse()
    return pixels


def pack_16x16(pixels16):
    data = bytearray(IMG16_BYTES)
    i = 0
    for y in range(16):
        for x in range(0, 16, 2):
            data[i] = (pixels16[y][x] << 4) | pixels16[y][x + 1]
            i += 1
    return bytes(data)


def compose_pose(chr_bytes, pose):
    # pose list order: UL, DL, UR, DR (FF1 LUT convention).
    (ul_tile, ul_attr), (dl_tile, dl_attr), (ur_tile, ur_attr), (dr_tile, dr_attr) = pose
    quads = {}
    for name, tile, attr in (("ul", ul_tile, ul_attr), ("dl", dl_tile, dl_attr),
                              ("ur", ur_tile, ur_attr), ("dr", dr_tile, dr_attr)):
        src = chr_bytes[tile * 16:(tile + 1) * 16]
        quads[name] = nes_tile_to_slots(src, bool(attr & 0x40), attr & 0x01)
    pixels = [[0] * 16 for _ in range(16)]
    for y in range(8):
        for x in range(8):
            pixels[y][x] = quads["ul"][y][x]
            pixels[y][x + 8] = quads["ur"][y][x]
            pixels[y + 8][x] = quads["dl"][y][x]
            pixels[y + 8][x + 8] = quads["dr"][y][x]
    return pack_16x16(pixels)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("input", help="bank_02_mapman_chr.bin (256 bytes)")
    ap.add_argument("output", help="packed 8 * 128 bytes")
    args = ap.parse_args()

    with open(args.input, "rb") as f:
        chr_bytes = f.read()
    if len(chr_bytes) != 256:
        sys.exit(f"{args.input}: expected 256 bytes, got {len(chr_bytes)}")

    with open(args.output, "wb") as f:
        for pose in POSES:
            f.write(compose_pose(chr_bytes, pose))


if __name__ == "__main__":
    main()
