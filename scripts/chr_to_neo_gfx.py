#!/usr/bin/env python3
"""
chr_to_neo_gfx.py - Pack FF1 CHR + cursor CHR as a Neo6502 .gfx.

Emits one of three tilesets based on --mode:
  font        : FF1's menu font glyphs (bank_09, offset $800, 128 tiles).
                Each glyph lives in the upper-left 8x8 of its 16x16 image.
  map         : FF1's overworld BG CHR (bank_02, offset $0, 128 tiles).
                Flat 4-colour bake (nibbles 0..3) for all tiles.
  map-groups  : OW tiles baked with per-attribute-group variants. Reads
                the map + tileset blobs, ranks (tile_id, group) pairs by
                actual OW usage, and bakes the top 128 pairs into Neo
                tile slots. Group G's pixels are encoded as nibbles
                G*4..G*4+3, so the Neo palette needs slots $00..$0F
                programmed as 4 groups x 4 colours. A 256-byte lookup
                blob keyed on (tile_id * 4 + group) is emitted alongside
                the .gfx so ppu_flush can translate at paint time.

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
from collections import Counter, defaultdict

HEADER_SIZE = 256
IMG16_BYTES = 128
FF1_TILE_COUNT = 128                # nametable bytes $80..$FF -> Neo ids $00..$7F
MAP_GROUPS_BUDGET = 128             # Neo Draw Image tile-slot cap

FONT_MAP = {0: 0, 1: 1, 2: 2, 3: 3}

# Map tiles use all four NES 2bpp values as genuine attribute-group
# colour indices. Pass through unchanged; the Neo palette is whatever
# DrawPalette last pushed (Phase 1 flat palette -- see palette.asm).
MAP_MAP = {0: 0, 1: 1, 2: 2, 3: 3}

# Luminance weights (Rec.709) used to pick nearest-luminance fallback
# group for rare (tile_id, group) pairs that miss the top-128 bake.
LUMA = (0.2126, 0.7152, 0.0722)

# Minimal NES 2C02 palette, enough to compute perceptual luminance for
# slot-2/slot-3 colours when ranking fallback candidates. Indexed by
# the 6-bit NES colour number (0x00..0x3F).
NES_RGB = [
    (0x74,0x74,0x74),(0x24,0x18,0x8C),(0x00,0x00,0xA8),(0x44,0x00,0x9C),
    (0x8C,0x00,0x74),(0xA8,0x00,0x10),(0xA4,0x00,0x00),(0x7C,0x08,0x00),
    (0x40,0x2C,0x00),(0x00,0x44,0x00),(0x00,0x50,0x00),(0x00,0x3C,0x14),
    (0x18,0x3C,0x5C),(0x00,0x00,0x00),(0x00,0x00,0x00),(0x00,0x00,0x00),
    (0xBC,0xBC,0xBC),(0x00,0x70,0xEC),(0x20,0x38,0xEC),(0x80,0x00,0xF0),
    (0xBC,0x00,0xBC),(0xE4,0x00,0x58),(0xD8,0x28,0x00),(0xC8,0x4C,0x0C),
    (0x88,0x70,0x00),(0x00,0x94,0x00),(0x00,0xA8,0x00),(0x00,0x90,0x38),
    (0x00,0x80,0x88),(0x00,0x00,0x00),(0x00,0x00,0x00),(0x00,0x00,0x00),
    (0xFC,0xFC,0xFC),(0x3C,0xBC,0xFC),(0x5C,0x94,0xFC),(0xCC,0x88,0xFC),
    (0xF4,0x78,0xFC),(0xFC,0x74,0xB4),(0xFC,0x74,0x60),(0xFC,0x98,0x38),
    (0xF0,0xBC,0x3C),(0x80,0xD0,0x10),(0x4C,0xDC,0x48),(0x58,0xF8,0x98),
    (0x00,0xE8,0xD8),(0x78,0x78,0x78),(0x00,0x00,0x00),(0x00,0x00,0x00),
    (0xFC,0xFC,0xFC),(0xA8,0xE4,0xFC),(0xC4,0xD4,0xFC),(0xD4,0xC8,0xFC),
    (0xFC,0xC4,0xFC),(0xFC,0xC4,0xD8),(0xFC,0xBC,0xB0),(0xFC,0xD8,0xA8),
    (0xFC,0xE4,0xA0),(0xE0,0xFC,0xA0),(0xA8,0xF0,0xBC),(0xB0,0xFC,0xCC),
    (0x9C,0xFC,0xF0),(0xC4,0xC4,0xC4),(0x00,0x00,0x00),(0x00,0x00,0x00),
]


def nes_luma(idx):
    r, g, b = NES_RGB[idx & 0x3F]
    return LUMA[0]*r + LUMA[1]*g + LUMA[2]*b

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


def pack_tile_group_variant(src16, group):
    """Bake an NES 8x8 tile into a 16x16 Neo image using palette slots
    (group * 4)..(group * 4 + 3). Rest of the 16x16 stays nibble 0
    (transparent)."""
    nes = nes_tile_to_pixels(src16)
    pixels = [[0] * 16 for _ in range(16)]
    base = group * 4
    for y in range(8):
        for x in range(8):
            v = nes[y][x]
            if v == 0:
                pixels[y][x] = 0          # shared black across all groups
            else:
                pixels[y][x] = base + v
    # Pack identity map because we already wrote slot-space values.
    return pack_16x16(pixels, {i: i for i in range(16)})


def decompress_ow_rows(ow_map_data):
    """Yield 256 rows of up to 256 metatile ids from the FF1-style RLE
    overworld map. Matches src/app/map_decompress.asm semantics."""
    ptr_tbl = ow_map_data[:512]
    for row in range(256):
        base = ptr_tbl[row*2] | (ptr_tbl[row*2+1] << 8)
        off = base - 0x8000
        buf = []
        while off < len(ow_map_data) and len(buf) < 256:
            b = ow_map_data[off]; off += 1
            if b == 0xFF:
                break
            if b & 0x80:
                tid = b & 0x7F
                n = ow_map_data[off]; off += 1
                if n == 0:
                    n = 256
                for _ in range(n):
                    buf.append(tid)
                    if len(buf) >= 256:
                        break
            else:
                buf.append(b)
        yield buf[:256]


def build_map_groups_bake(tile_data, cursor_data, mapman_data,
                          ow_map_data, ow_tileset_data,
                          bake_output, lut_output):
    """Bake the top-128 (tile_id, group) variants into a .gfx and emit
    a 256-byte slot lookup blob keyed on (tile_id * 4 + group)."""

    # tileset layout (see src/app/tileset_data.asm)
    tsa_ul   = ow_tileset_data[0x100:0x180]
    tsa_ur   = ow_tileset_data[0x180:0x200]
    tsa_dl   = ow_tileset_data[0x200:0x280]
    tsa_dr   = ow_tileset_data[0x280:0x300]
    tsa_attr = ow_tileset_data[0x300:0x380]
    load_map_pal = ow_tileset_data[0x380:0x380+48]

    # Per-group (slot 2, slot 3) luminance, used for fallback ranking.
    group_slot23_lum = [
        (nes_luma(load_map_pal[g*4 + 2]), nes_luma(load_map_pal[g*4 + 3]))
        for g in range(4)
    ]

    # Build two rankings:
    #   pair_count: (tile_id, group) -> cell count.
    #   tile_total: tile_id -> cell count across all groups.
    # Budget allocation:
    #   1) One slot per tile_id for the top-N tile_ids by total usage,
    #      baked in that tile's dominant (most-cells) group. This
    #      guarantees every baked tile has *a* variant so rare pairs
    #      can fall back to same-tile alternate-group.
    #   2) Remaining slots go to the most-popular additional (tile,
    #      group) pairs -- i.e. second/third groups for tiles that
    #      appear prominently across multiple groups.
    # With budget 128 and 235 distinct tile_ids, step 1 consumes all
    # 128 slots (127 baked tiles -> 108 dropped; 0.096% of cells
    # unrendered for the dropped tiles). Any future budget expansion
    # spills naturally into step 2.
    pair_count = Counter()
    tile_total = Counter()
    tile_dominant_group = {}
    tile_group_counts = defaultdict(Counter)
    for row in decompress_ow_rows(ow_map_data):
        for col in range(256):
            mt = row[col] if col < len(row) else 0
            grp = tsa_attr[mt] & 0x03
            for tsa in (tsa_ul, tsa_ur, tsa_dl, tsa_dr):
                tid = tsa[mt]
                pair_count[(tid, grp)] += 1
                tile_total[tid] += 1
                tile_group_counts[tid][grp] += 1

    for tid, grp_counts in tile_group_counts.items():
        tile_dominant_group[tid] = grp_counts.most_common(1)[0][0]

    # Step 1: top-N tile_ids by total usage, one variant each.
    tile_rank = [tid for tid, _ in tile_total.most_common()]
    kept = []                      # list of (tile_id, group) in bake order
    pair_to_slot = {}
    for tid in tile_rank:
        if len(kept) >= MAP_GROUPS_BUDGET:
            break
        g = tile_dominant_group[tid]
        pair = (tid, g)
        pair_to_slot[pair] = len(kept)
        kept.append(pair)

    # Step 2: fill leftover budget with most-popular *additional* pairs.
    for (tid, g), _ in pair_count.most_common():
        if len(kept) >= MAP_GROUPS_BUDGET:
            break
        if (tid, g) in pair_to_slot:
            continue
        pair_to_slot[(tid, g)] = len(kept)
        kept.append((tid, g))

    pad_needed = MAP_GROUPS_BUDGET - len(kept)
    dropped_tiles = [tid for tid in tile_rank
                     if not any((tid, g) in pair_to_slot for g in range(4))]
    dropped_cells = sum(tile_total[tid] for tid in dropped_tiles)

    # For every (tile_id, group) pair across the full NES 256-tile range,
    # resolve the Neo slot. The OW references tile ids up to $F5, so we
    # size the LUT as 256 tiles x 4 groups = 1024 bytes keyed on
    # (tile_id * 4 + group). Fallback order:
    #   1) exact pair baked -> that slot.
    #   2) same tile, any baked group -> nearest-luminance group's slot.
    #   3) tile has no baked variant at all -> slot 0 (universal
    #      fallback). Slot 0 is guaranteed by step 1 of the bake to be
    #      the most-used tile on the OW (currently the ocean tile $3B
    #      in group 2), which is the least-surprising failure mode for
    #      an unrenderable cell.
    lut = bytearray(1024)
    missing = 0
    for tid in range(256):
        for g in range(4):
            if (tid, g) in pair_to_slot:
                lut[tid*4 + g] = pair_to_slot[(tid, g)]
                continue
            candidates = [(cg, pair_to_slot[(tid, cg)])
                          for cg in range(4) if (tid, cg) in pair_to_slot]
            if candidates:
                L2w, L3w = group_slot23_lum[g]
                def dist(c):
                    cg, _ = c
                    L2, L3 = group_slot23_lum[cg]
                    return (L2-L2w)**2 + (L3-L3w)**2
                candidates.sort(key=dist)
                lut[tid*4 + g] = candidates[0][1]
            else:
                lut[tid*4 + g] = 0
                missing += 1

    sprite_count = 1 + (8 if mapman_data else 0)
    header = bytearray(HEADER_SIZE)
    header[0] = 1
    header[1] = FF1_TILE_COUNT
    header[2] = sprite_count
    header[3] = 0

    with open(bake_output, "wb") as f:
        f.write(header)
        for (tid, g) in kept:
            base = tid * 16
            f.write(pack_tile_group_variant(tile_data[base:base+16], g))
        # Pad the bake out to 128 slots with blank tiles so the header
        # count matches the slots present on disk. The LUT never points
        # at these padding slots, so they are purely placeholder.
        blank = bytes(IMG16_BYTES)
        for _ in range(pad_needed):
            f.write(blank)
        f.write(pack_cursor(cursor_data))
        if mapman_data:
            f.write(mapman_data)

    with open(lut_output, "wb") as f:
        f.write(bytes(lut))

    # Diagnostics to stdout so the build log carries them.
    kept_tiles = set(t for t, _ in kept)
    print(f"map-groups bake: {len(kept)} pairs baked (budget {MAP_GROUPS_BUDGET}).")
    print(f"  distinct tiles baked : {len(kept_tiles)}")
    print(f"  pad slots            : {pad_needed}")
    print(f"  distinct pairs used  : {len(pair_count)}")
    print(f"  dropped tile_ids     : {len(dropped_tiles)} "
          f"({dropped_cells} cells, "
          f"{100*dropped_cells/sum(tile_total.values()):.3f}%)")
    cells_covered = sum(pair_count[p] for p in kept)
    cells_total   = sum(pair_count.values())
    print(f"  exact-pair coverage  : {cells_covered}/{cells_total} "
          f"({100*cells_covered/cells_total:.3f}%)")
    if missing:
        print(f"  LUT entries routed to slot-0 fallback: {missing}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--mode", choices=("font", "map", "map-groups"), required=True,
                    help="which tileset to pack into the tile region")
    ap.add_argument("--tiles", required=True,
                    help="source CHR blob (font: bank_09_data.bin; "
                         "map/map-groups: bank_02.dat)")
    ap.add_argument("--tiles-offset", type=lambda x: int(x, 0), default=0,
                    help="byte offset into the tiles blob "
                         "(default 0; font mode typically uses 0x800)")
    ap.add_argument("--cursor", required=True, help="cursor CHR (64 bytes)")
    ap.add_argument("--mapman", help="precomposed mapman poses (8 * 128 bytes, "
                                      "map/map-groups only; appended after cursor)")
    ap.add_argument("--owmap", help="bank_owmap.dat (map-groups only)")
    ap.add_argument("--owtileset", help="lut_ow_tileset.dat (map-groups only)")
    ap.add_argument("--lut-output", help="path to write 256-byte (tile,group) "
                                          "-> Neo slot LUT (map-groups only)")
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
        if args.mode == "font":
            sys.exit("--mapman only valid for map/map-groups modes")
        with open(args.mapman, "rb") as f:
            mapman_data = f.read()
        if len(mapman_data) != 8 * IMG16_BYTES:
            sys.exit(f"{args.mapman}: expected {8 * IMG16_BYTES} bytes, "
                     f"got {len(mapman_data)}")

    if args.mode == "map-groups":
        if not (args.owmap and args.owtileset and args.lut_output):
            sys.exit("--mode map-groups requires --owmap, --owtileset, --lut-output")
        if args.tiles_offset != 0:
            sys.exit("--mode map-groups expects --tiles-offset 0 (bank_02 base)")
        with open(args.owmap, "rb") as f:
            ow_map_data = f.read()
        with open(args.owtileset, "rb") as f:
            ow_tileset_data = f.read()
        if len(ow_tileset_data) < 0x400:
            sys.exit(f"{args.owtileset}: expected >= $400 bytes")
        build_map_groups_bake(tile_data, cursor_data, mapman_data,
                              ow_map_data, ow_tileset_data,
                              args.output, args.lut_output)
        return

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
