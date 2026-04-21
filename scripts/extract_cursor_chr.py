#!/usr/bin/env python3
"""
extract_cursor_chr.py - Pull FF1's cursor-sprite CHR from bank_09.asm.

The 2x2 "pointing hand" cursor is 4 tiles (64 bytes of NES 2bpp CHR),
held inline in bank_09.asm as .BYTE directives at lines 3856-3919.
It sits past the end of bin/bank_09_data.bin (which only covers the
first $2000 of the bank), so it's not reachable via a simple INCBIN
offset. We parse the .BYTE lines and emit the raw 64 bytes.

The tile arrangement matches lutCursor2x2SpriteTable (bank_0F.asm):
    tile 0 = UL, tile 1 = UR, tile 2 = DL, tile 3 = DR
"""

import argparse
import re
import sys

START_LINE = 3856   # 1-based inclusive
END_LINE   = 3919   # 1-based inclusive
EXPECTED_BYTES = 64


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("input", help="path to FF1Disassembly bank_09.asm")
    ap.add_argument("output", help="64-byte cursor CHR output")
    args = ap.parse_args()

    with open(args.input) as f:
        lines = f.readlines()

    pat = re.compile(r'\$([0-9A-Fa-f]{2})')
    out = bytearray()
    for ln in lines[START_LINE - 1:END_LINE]:
        m = pat.search(ln)
        if m:
            out.append(int(m.group(1), 16))

    if len(out) != EXPECTED_BYTES:
        sys.exit(f"{args.input}: extracted {len(out)} bytes, expected {EXPECTED_BYTES}")

    with open(args.output, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
