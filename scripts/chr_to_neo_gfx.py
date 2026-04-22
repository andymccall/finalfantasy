#!/usr/bin/env python3
"""
chr_to_neo_gfx.py - Pack FF1 CHR + cursor CHR as a Neo6502 .gfx.

Emits one of two tilesets based on --mode:
  font  : FF1's menu font glyphs (bank_09, offset $800, 128 tiles).
          Each glyph lives in the upper-left 8x8 of its 16x16 image.
  map   : FF1's overworld BG CHR (bank_02, offset $0, 128 tiles).
          Each NES 8x8 tile lives in the upper-left 8x8 of a 16x16
          image, same as font -- HAL_FlushNametable paints cells on
          an 8-pixel grid and the transparent quadrants overlap
          cleanly with neighbours.

Output layout (single .gfx, loaded to gfxObjectMemory at runtime):
    [0..255]  256-byte header
        [0]   = 1             (format version)
        [1]   = 128           (16x16 tile count)
        [2]   = N             (16x16 sprite count: 1 cursor, +8 mapman in map mode)
        [3]   = 0             (32x32 sprite count)
    [256..]   128 tile images (128 bytes each = 16384 bytes)
    [..]      1 cursor sprite (128 bytes)
    [..]      (map mode) 8 mapman pose images (128 bytes each)

Both modes ship the cursor sprite at the end so HAL_LoadTileset can
swap the tile region without losing the cursor image. Map mode also
appends 8 Fighter mapman poses (precomposed by mapman_to_neo_gfx.py)
so the on-foot player can render on the overworld.

Note: we cannot add a 129th "blank" tile because Neo Draw Image treats
image ids >= $80 as sprites, not tiles -- so any attempt to paint
Neo tile id $80 ends up drawing the cursor sprite instead. FF1's
$00 ClearNT cells are handled in ppu_flush.asm by a Draw Rectangle
call at palette slot 0 (black), sitting alongside the per-cell Draw
Image path for $80..$FF cells.

Each 16x16 image is flat 4bpp packed, 128 bytes per image (8 bytes per row,
MSN = left pixel, palette index 0 = transparent when composited).

NES 8x8 tile -> Neo 16x16 image
-------------------------------
The NES viewport is 32 8x8 cells wide (256 px). The Neo graphics plane is
320x240. We pack each NES 8x8 tile into the upper-left 8x8 of a Neo 16x16
image; the rest is transparent (nibble 0). HAL_FlushNametable then places
each tile on an 8-pixel grid -- the transparent lower-right of one tile
overlaps the upper-left of its neighbours without overwriting them.

Why a 16x16 image for an 8x8 source: the Neo Draw Image command only
handles 16x16 (tile) or 32x32 (sprite) sizes. A 16x16 slot is the smallest
available; the empty quadrants cost 96 bytes/tile of gfx memory, which
fits comfortably inside GFX_MEMORY_SIZE even at 128 tiles (16512 bytes).

Palette mapping
---------------
FF1 menu font uses a 4-colour subpalette. The NES 2bpp pixel value is
already the colour index into that 4-colour subpalette, so we pass it
through unchanged -- pixel 0 stays 0, pixel 1 stays 1, and so on --
and then the Neo palette reprogrammed by palette.asm at boot makes
Neo slots 0..3 resolve to NES colours $0F/$00/$01/$30 (black / grey /
blue / white).

FF1 font CHR: plane 0 holds the glyph shape, plane 1 is a solid-$FF
opaque-background marker the NES uses to paint colour 2 behind each
letter. We drop plane 1 and render glyphs as 0/1 pairs (background /
foreground) -- foreground pixel = 1 resolves to Neo slot 1 = NES $00
mid-grey, which is the actual FF1 menu font colour. (The three-shade
border falls out naturally from the 2bpp path because the border tiles
use plane 1 meaningfully, but we clamp them to the same 0/1 range when
in font mode; border tiles live under the same 128 slots and the font
pixels within border cells still read correctly.)

Cursor: same pass-through mapping. The four NES cursor tiles compose
into one 16x16 image per FF1's lutCursor2x2 layout (UL=0, UR=1, DL=2,
DR=3), then each 2bpp pixel value maps directly to a Neo palette slot.
"""

import argparse
import sys

HEADER_SIZE = 256
IMG16_BYTES = 128
FF1_TILE_COUNT = 128                # nametable bytes $80..$FF -> Neo ids $00..$7F

FONT_MAP = {0: 0, 1: 1, 2: 2, 3: 3}

# Map tiles use all four NES 2bpp values as genuine attribute-group
# colour indices. Pass through unchanged; the Neo palette is whatever
# DrawPalette last pushed (Phase 1 flat palette -- see palette.asm).
MAP_MAP = {0: 0, 1: 1, 2: 2, 3: 3}

# Cursor sprite palette on the title screen is FF1's sprite palette 3:
# NES $0F/$30/$10/$00 (black / white / light-grey / mid-grey). Our fixed
# Neo palette is slot 0=black, 1=mid-grey, 2=dark-blue, 3=white, 4=light-grey
# (see src/system/neo/palette.asm). So remap the cursor's 2bpp values so
# each pixel resolves to the NES colour FF1 intended, avoiding the shared
# slot 2 (dark blue) which tiles need for menu-box fills and $FF backdrops.
CURSOR_MAP = {0: 0, 1: 3, 2: 4, 3: 1}


def nes_tile_to_pixels(src):
    """Unpack a 16-byte NES 2bpp tile into an 8x8 array of 0..3 values."""
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


def pack_16x16(pixels16, palette_map):
    data = bytearray(IMG16_BYTES)
    i = 0
    for y in range(16):
        for x in range(0, 16, 2):
            lp = palette_map[pixels16[y][x]]
            rp = palette_map[pixels16[y][x + 1]]
            data[i] = (lp << 4) | rp
            i += 1
    return bytes(data)


def pack_tile_upper_left(src16, palette_map):
    """NES 8x8 tile in the upper-left of a 16x16 image; rest transparent."""
    nes = nes_tile_to_pixels(src16)
    pixels = [[0] * 16 for _ in range(16)]
    for y in range(8):
        for x in range(8):
            pixels[y][x] = nes[y][x]
    return pack_16x16(pixels, palette_map)


def pack_cursor(cursor_chr):
    tiles = [nes_tile_to_pixels(cursor_chr[i * 16:(i + 1) * 16]) for i in range(4)]
    ul, ur, dl, dr = tiles[0], tiles[1], tiles[2], tiles[3]
    pixels = [[0] * 16 for _ in range(16)]
    for y in range(8):
        for x in range(8):
            pixels[y][x] = ul[y][x]
            pixels[y][x + 8] = ur[y][x]
            pixels[y + 8][x] = dl[y][x]
            pixels[y + 8][x + 8] = dr[y][x]
    return pack_16x16(pixels, CURSOR_MAP)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--mode", choices=("font", "map"), required=True,
                    help="which tileset to pack into the tile region")
    ap.add_argument("--tiles", required=True,
                    help="source CHR blob (font: bank_09_data.bin; "
                         "map: bank_02.dat)")
    ap.add_argument("--tiles-offset", type=lambda x: int(x, 0), default=0,
                    help="byte offset into the tiles blob "
                         "(default 0; font mode typically uses 0x800)")
    ap.add_argument("--cursor", required=True, help="cursor CHR (64 bytes)")
    ap.add_argument("--mapman", help="precomposed mapman poses (8 * 128 bytes, "
                                      "map mode only; appended after cursor)")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    with open(args.tiles, "rb") as f:
        tile_data = f.read()
    with open(args.cursor, "rb") as f:
        cursor_data = f.read()

    need = args.tiles_offset + FF1_TILE_COUNT * 16
    if need > len(tile_data):
        sys.exit(f"{args.tiles}: need {need:#x} bytes, got {len(tile_data):#x}")
    if len(cursor_data) != 64:
        sys.exit(f"{args.cursor}: expected 64 bytes, got {len(cursor_data)}")

    mapman_data = b""
    if args.mapman:
        if args.mode != "map":
            sys.exit("--mapman only valid in --mode map")
        with open(args.mapman, "rb") as f:
            mapman_data = f.read()
        if len(mapman_data) != 8 * IMG16_BYTES:
            sys.exit(f"{args.mapman}: expected {8 * IMG16_BYTES} bytes, "
                     f"got {len(mapman_data)}")

    palette_map = FONT_MAP if args.mode == "font" else MAP_MAP

    sprite_count = 1 + (8 if mapman_data else 0)

    header = bytearray(HEADER_SIZE)
    header[0] = 1
    header[1] = FF1_TILE_COUNT
    header[2] = sprite_count
    header[3] = 0

    with open(args.output, "wb") as f:
        f.write(header)
        for t in range(FF1_TILE_COUNT):
            base = args.tiles_offset + t * 16
            f.write(pack_tile_upper_left(tile_data[base:base + 16], palette_map))
        f.write(pack_cursor(cursor_data))
        if mapman_data:
            f.write(mapman_data)


if __name__ == "__main__":
    main()
