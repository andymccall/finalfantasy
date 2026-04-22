#!/usr/bin/env python3
"""
extract_mapman_chr.py - Pull FF1's player mapman CHR from bank_02.dat.

LoadPlayerMapmanCHR (bank_0F.asm:9710) swaps BANK_MAPCHR ($02) in and
loads 1 row (16 tiles, 256 bytes of NES 2bpp) from source $9x00 into
PPU $1000, where x is the lead character's class. The $9000 base is
$1000 into the 16 KB bank file (bank $02's first 8 KB window maps to
CPU $8000..$9FFF when swapped).

Class offsets inside bank_02.dat:
    0  Fighter      $9000 -> offset $1000
    1  Thief        $9100 -> offset $1100
    2  BlackBelt    $9200 -> offset $1200
    3  RedMage      $9300 -> offset $1300
    4  WhiteMage    $9400 -> offset $1400
    5  BlackMage    $9500 -> offset $1500

For the first milestone we only need Fighter (class 0), so this script
emits a single 256-byte blob. A --class flag is provided for future use.
"""

import argparse
import sys

BANK_BASE_OFFSET = 0x1000           # $9000 inside bank_02.dat
TILES_PER_CLASS  = 16
TILE_BYTES       = 16               # NES 2bpp, 8x8
CLASS_BYTES      = TILES_PER_CLASS * TILE_BYTES  # 256


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("input", help="path to FF1Disassembly bank_02.dat")
    ap.add_argument("output", help="mapman CHR output (256 bytes)")
    ap.add_argument("--class", dest="cls", type=int, default=0,
                    help="class index 0..5 (default 0 = Fighter)")
    args = ap.parse_args()

    if args.cls < 0 or args.cls > 5:
        sys.exit(f"--class must be 0..5, got {args.cls}")

    with open(args.input, "rb") as f:
        data = f.read()

    start = BANK_BASE_OFFSET + args.cls * CLASS_BYTES
    end = start + CLASS_BYTES
    if end > len(data):
        sys.exit(f"{args.input}: too short ({len(data)} bytes) for class {args.cls}")

    with open(args.output, "wb") as f:
        f.write(data[start:end])


if __name__ == "__main__":
    main()
