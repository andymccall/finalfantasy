#!/usr/bin/env python3
"""
hook_ppu.py - Rewrite NES PPU register writes into HAL trampoline calls.

The re-host keeps FF1Disassembly/ verbatim and pulls isolated routines into
src/core/ unchanged. This script is the one sanctioned edit: it replaces
literal writes to the NES PPU ports with JSRs into the HAL, so the original
6502 code can drive our virtual PPU without any hand-patching.

Substitutions (case-insensitive, whole-mnemonic match, comments preserved):
    STA $2000  ->  JSR HAL_PPU_2000_Write   (PPUCTRL  -- host no-op)
    STA $2001  ->  JSR HAL_PPU_2001_Write   (PPUMASK  -- host no-op)
    STA $2005  ->  JSR HAL_PPU_2005_Write   (PPUSCROLL -- host no-op)
    STA $2006  ->  JSR HAL_PPU_2006_Write   (PPUADDR latch)
    STA $2007  ->  JSR HAL_PPU_2007_Write   (PPUDATA to nametable / palette)
    STX $2006  ->  JSR HAL_PPU_2006_Write_X (X-sourced PPUADDR write)
    STY $2006  ->  JSR HAL_PPU_2006_Write_Y (Y-sourced PPUADDR write)
    STX $2007  ->  JSR HAL_PPU_2007_Write_X (X-sourced PPUDATA write)
    STY $2007  ->  JSR HAL_PPU_2007_Write_Y (Y-sourced PPUDATA write)
    STA $4014  ->  JSR HAL_APU_4014_Write   (OAMDMA -- host no-op)
    STA $4015  ->  JSR HAL_APU_4015_Write   (APU channel enable -- host no-op)

The _X / _Y variants exist because FF1 occasionally uses STX/STY against
the PPU ports specifically to avoid disturbing A (e.g. DrawComplexString
holds the character to draw in A while it latches the address via X).
The wrappers preserve A across the call so the original invariant holds.

Everything after a ';' on a line is left untouched so FF1's original
annotations keep referring to "$2006" / "$2007" by name.
"""

import re
import sys

PATTERNS = (
    (re.compile(r"\bsta\s+\$2000\b", re.IGNORECASE), "JSR HAL_PPU_2000_Write"),
    (re.compile(r"\bsta\s+\$2001\b", re.IGNORECASE), "JSR HAL_PPU_2001_Write"),
    (re.compile(r"\bsta\s+\$2005\b", re.IGNORECASE), "JSR HAL_PPU_2005_Write"),
    (re.compile(r"\bsta\s+\$2006\b", re.IGNORECASE), "JSR HAL_PPU_2006_Write"),
    (re.compile(r"\bsta\s+\$2007\b", re.IGNORECASE), "JSR HAL_PPU_2007_Write"),
    (re.compile(r"\bstx\s+\$2006\b", re.IGNORECASE), "JSR HAL_PPU_2006_Write_X"),
    (re.compile(r"\bsty\s+\$2006\b", re.IGNORECASE), "JSR HAL_PPU_2006_Write_Y"),
    (re.compile(r"\bstx\s+\$2007\b", re.IGNORECASE), "JSR HAL_PPU_2007_Write_X"),
    (re.compile(r"\bsty\s+\$2007\b", re.IGNORECASE), "JSR HAL_PPU_2007_Write_Y"),
    (re.compile(r"\bsta\s+\$4014\b", re.IGNORECASE), "JSR HAL_APU_4014_Write"),
    (re.compile(r"\bsta\s+\$4015\b", re.IGNORECASE), "JSR HAL_APU_4015_Write"),
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
