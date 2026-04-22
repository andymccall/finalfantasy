#!/usr/bin/env python3
# Extract BANK_OWMAP ($01) raw data: pointer table + RLE-compressed overworld
# map rows. Layout:
#   $8000..$9FFF : bin/bank_01_data.bin (8 KB INCBIN)
#   $A000..$BF3F : inline `.BYTE $xx` lines
#   $BF40..$BFFF : MinimapDecompress code (not needed by DecompressMap /
#                  LoadOWMapRow -- excluded)
#
# Emits one flat file of size $3F40 bytes that can be `.incbin`'d at offset
# $8000 so pointers in lut_OWPtrTbl resolve correctly.

import argparse
import pathlib
import re
import sys

BYTE_RE = re.compile(r"^\s*\.BYTE\s+\$([0-9A-Fa-f]{1,2})\s*$")
START_LINE = 10          # first inline byte after the INCBIN directive
END_LINE = 8009          # last inline byte before the MinimapDecompress block


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--asm", required=True,
                    help="path to bank_01.asm from the FF1 disassembly")
    ap.add_argument("--bin", required=True,
                    help="path to bin/bank_01_data.bin from the FF1 disassembly")
    ap.add_argument("--out", required=True, help="output flat-binary path")
    args = ap.parse_args()

    incbin = pathlib.Path(args.bin).read_bytes()
    if len(incbin) != 0x2000:
        print(f"unexpected INCBIN size {len(incbin):#x} (want $2000)",
              file=sys.stderr)
        return 1

    asm_lines = pathlib.Path(args.asm).read_text().splitlines()
    inline = bytearray()
    for i in range(START_LINE - 1, END_LINE):
        line = asm_lines[i]
        if not line.strip():
            continue
        m = BYTE_RE.match(line)
        if not m:
            print(f"{args.asm}:{i+1}: unexpected line {line!r}", file=sys.stderr)
            return 1
        inline.append(int(m.group(1), 16))

    if len(inline) != 0x3F40 - 0x2000:
        print(f"unexpected inline byte count {len(inline):#x} "
              f"(want {0x3F40 - 0x2000:#x})", file=sys.stderr)
        return 1

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(bytes(incbin) + bytes(inline))
    return 0


if __name__ == "__main__":
    sys.exit(main())
