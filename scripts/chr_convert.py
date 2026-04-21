#!/usr/bin/env python3
"""
chr_convert.py - Convert NES 2bpp planar tile data to flat 1bpp byte streams.

NES CHR tile layout (16 bytes per 8x8 tile):
    bytes 0-7  : bit plane 0, one byte per row, MSB = leftmost pixel
    bytes 8-15 : bit plane 1, same layout

Both target platforms want 1bpp per-row bytes. FF1's menu/font CHR holds
the glyph shape in plane 0 and uses plane 1 as a solid-$FF "opaque box"
marker (so on the NES, palette colour 2 paints the cell background and
colour 3 the glyph itself). OR-ing both planes therefore makes every
tile solid; we keep only plane 0, which matches the visible letterform.

Output format:
    x16 - 8 bytes per tile, one byte per row. Drops straight into VERA
          text-mode character memory (1bpp, MSB = leftmost pixel).
"""

import argparse
import sys


def tile_1bpp(src):
    return bytes(src[:8])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("input", help="raw NES 2bpp blob")
    ap.add_argument("output", help="converted 1bpp output")
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
        out.extend(tile_1bpp(data[base:base + 16]))

    with open(args.output, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
