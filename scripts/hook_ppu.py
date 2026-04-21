#!/usr/bin/env python3
"""
hook_ppu.py - Rewrite NES PPU register writes into HAL trampoline calls.

The re-host keeps FF1Disassembly/ verbatim and pulls isolated routines into
src/core/ unchanged. This script is the one sanctioned edit: it replaces
literal writes to the NES PPU ports with JSRs into the HAL, so the original
6502 code can drive our virtual PPU without any hand-patching.

Substitutions (case-insensitive, whole-mnemonic match, comments preserved):
    STA $2006  ->  JSR HAL_PPU_2006_Write
    STA $2007  ->  JSR HAL_PPU_2007_Write

Everything after a ';' on a line is left untouched so FF1's original
annotations keep referring to "$2006" / "$2007" by name.
"""

import re
import sys

PATTERNS = (
    (re.compile(r"\bsta\s+\$2006\b", re.IGNORECASE), "JSR HAL_PPU_2006_Write"),
    (re.compile(r"\bsta\s+\$2007\b", re.IGNORECASE), "JSR HAL_PPU_2007_Write"),
)


def hook_line(line):
    code, sep, comment = line.partition(";")
    for pattern, replacement in PATTERNS:
        code = pattern.sub(replacement, code)
    return code + sep + comment


def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <input.asm> <output.asm>")
    src_path, dst_path = sys.argv[1], sys.argv[2]
    with open(src_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    with open(dst_path, "w", encoding="utf-8") as f:
        f.writelines(hook_line(line) for line in lines)


if __name__ == "__main__":
    main()
