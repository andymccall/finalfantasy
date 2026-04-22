# ---------------------------------------------------------------------------
# Final Fantasy (X16 / Neo6502) - re-hosting build
# ---------------------------------------------------------------------------
# Three-tier source tree:
#   src/core/        verbatim FF1 disassembly files (source of truth)
#   src/app/         translator layer (main, trampolines, shims)
#   src/system/      HAL interface + per-platform implementations
# ---------------------------------------------------------------------------

# --- Tools -----------------------------------------------------------------
CA65       = ca65
LD65       = ld65
X16EMU     = x16emu
NEOEMU     = neo
NEO_HOME   = ~/development/tools/neo6502

# --- Directories -----------------------------------------------------------
SRCDIR     = src
CFGDIR     = cfg
BUILDDIR   = build
RELEASEDIR = release
SCRIPTDIR  = scripts

# --- Build-time font conversion --------------------------------------------
# BANK_MENUCHR (bank $09) holds FF1's menu/font CHR. LoadMenuCHR in the
# original ROM reads from source $8800 for $800 bytes (128 tiles), so the
# font starts $800 into bin/bank_09_data.bin. Copy the source blob into
# build/ first so the converter input path has no shell-hostile spaces.
FF1_DIS_ROOT   := /home/andymccall/development/FF1Disassembly/Final Fantasy Disassembly
FF1_FONT_SRC   := $(FF1_DIS_ROOT)/bin/bank_09_data.bin
FF1_FONT_OFF   := 0x0800
FF1_FONT_COUNT := 128
FF1_FONT_RAW   := $(BUILDDIR)/bank_09_data.bin
CHR_SCRIPT     := $(SCRIPTDIR)/chr_convert.py
X16_FONT       := $(BUILDDIR)/x16/font_converted.bin

# --- Build-time map-tile conversion (overworld BG CHR) ---------------------
# BANK_MAPCHR (bank $02) holds the full 4KB pattern table for overworld
# BG tiles. LoadOWBGCHR (bank_0F.asm:9750) reads $8000..$8FFF of that
# bank, which corresponds to offset $0 in the 8KB bank_02.dat file
# (first PRG page). Same space-in-path staging as the font.
FF1_MAP_OW_SRC   := $(FF1_DIS_ROOT)/bank_02.dat
FF1_MAP_OW_OFF   := 0x0000
FF1_MAP_OW_COUNT := 128
FF1_MAP_OW_RAW   := $(BUILDDIR)/bank_02.dat
X16_MAP_OW       := $(BUILDDIR)/x16/maptiles_ow.bin

# --- Build-time OW map-data extraction (BANK_OWMAP = $01) ------------------
# bank_01 is the compressed overworld map + its 256-entry row pointer
# table at $8000. Pointers reach into $BEA6, so we need the full first
# $3F40 bytes of the bank (everything up to MinimapDecompress code at
# $BF40). The extraction script stitches bin/bank_01_data.bin with the
# inline `.BYTE` rows that follow it in bank_01.asm.
FF1_OWMAP_ASM    := $(FF1_DIS_ROOT)/bank_01.asm
FF1_OWMAP_BIN    := $(FF1_DIS_ROOT)/bin/bank_01_data.bin
OWMAP_EXTRACT    := $(SCRIPTDIR)/extract_bank_01.py
OWMAP_DAT        := $(BUILDDIR)/bank_owmap.dat
X16_OWMAP        := $(BUILDDIR)/x16/bank_owmap.dat
NEO_OWMAP        := $(BUILDDIR)/neo/bank_owmap.dat

# --- Build-time OW tileset-data extraction (BANK_OWINFO = $00) -------------
# lut_OWTileset lives at $8000 in BANK_OWINFO (= offset 0 in bank_00.dat)
# and is exactly $400 bytes covering tileset_prop, tsa_ul/ur/dl/dr,
# tsa_attr, and load_map_pal. We slice the first 1 KB of the bank into
# a standalone blob that src/app/tileset_data.asm can .incbin at runtime.
FF1_OWTILESET_SRC := $(FF1_DIS_ROOT)/bank_00.dat
FF1_OWTILESET_OFF := 0
FF1_OWTILESET_LEN := 1024
OWTILESET_DAT     := $(BUILDDIR)/lut_ow_tileset.dat
X16_OWTILESET     := $(BUILDDIR)/x16/lut_ow_tileset.dat
NEO_OWTILESET     := $(BUILDDIR)/neo/lut_ow_tileset.dat

# The intro story text is a 224-byte format-coded blob FF1 ships in
# bin/0D_BF20_introtext.bin. lut_IntroStoryText INCBIN's it through the
# ca65 --bin-include-dir, so the blob has to be reachable under that
# dir. Staging a copy keeps the pristine disassembly tree untouched.
FF1_INTRO_SRC   := $(FF1_DIS_ROOT)/bin/0D_BF20_introtext.bin
X16_INTRO_BIN   := $(BUILDDIR)/x16/introtext.bin
NEO_INTRO_BIN   := $(BUILDDIR)/neo/introtext.bin

# Cursor sprite CHR. 4 tiles (64 bytes of NES 2bpp) live inline in
# bank_09.asm past the end of bank_09_data.bin, so we extract them via
# a script, then a platform converter turns the 2bpp CHR into whatever
# native sprite format the HAL wants. X16 wants VERA 4bpp packed
# (128 bytes). Neo folds the cursor into the combined tiles.gfx.
FF1_BANK_09_ASM := $(FF1_DIS_ROOT)/bank_09.asm
CURSOR_CHR      := $(BUILDDIR)/cursor.chr
CURSOR_EXTRACT  := $(SCRIPTDIR)/extract_cursor_chr.py
X16_CURSOR_VERA := $(BUILDDIR)/x16/cursor_vera.bin
X16_CURSOR_CONV := $(SCRIPTDIR)/cursor_to_vera.py

# Player mapman sprite CHR. Lives inside bank_02.dat at offset $1000
# ($9000 when the bank is swapped in). 1 row = 16 tiles = 256 bytes
# per class; LoadPlayerMapmanCHR (bank_0F.asm:9710) picks the class
# based on ch_class. First milestone only needs class 0 (Fighter).
MAPMAN_CHR       := $(BUILDDIR)/bank_02_mapman_chr.bin
MAPMAN_EXTRACT   := $(SCRIPTDIR)/extract_mapman_chr.py
X16_MAPMAN_VERA  := $(BUILDDIR)/x16/mapman_vera.bin
X16_MAPMAN_CONV  := $(SCRIPTDIR)/mapman_to_vera.py
NEO_MAPMAN_POSES := $(BUILDDIR)/neo/mapman_poses.bin
NEO_MAPMAN_CONV  := $(SCRIPTDIR)/mapman_to_neo_gfx.py

# Neo graphics plane artefacts. One .gfx per tileset; each file holds
# 128 16x16 tile images + the cursor sprite. Neo's gfxObjectMemory only
# has 128 tile slots total, so HAL_LoadTileset swaps files at runtime
# (see memory/project_map_tileset_strategy.md).
NEO_TILES_FONT_GFX := $(BUILDDIR)/neo/tiles_font.gfx
NEO_TILES_OW_GFX   := $(BUILDDIR)/neo/tiles_ow.gfx
NEO_TILES_CONV     := $(SCRIPTDIR)/chr_to_neo_gfx.py

# --- Core routines hooked through scripts/hook_ppu.py ----------------------
# Files listed here are verbatim FF1 extracts. They have no ca65 directives
# and no HAL imports, so the wildcard compile rule would fail on them. The
# hook script rewrites PPU port writes into JSRs and drops the result in
# build/core/; a matching shim in src/app/ supplies segment/imports/exports
# and .includes the generated file.
HOOK_SCRIPT    := $(SCRIPTDIR)/hook_ppu.py
CORE_HOOKED_SRCS = $(SRCDIR)/core/title_copyright.asm \
                   $(SRCDIR)/core/draw_palette.asm \
                   $(SRCDIR)/core/coord_to_nt_addr.asm \
                   $(SRCDIR)/core/nt_row_luts.asm \
                   $(SRCDIR)/core/draw_box.asm \
                   $(SRCDIR)/core/menu_cond_stall.asm \
                   $(SRCDIR)/core/draw_complex_string.asm \
                   $(SRCDIR)/core/title_screen.asm \
                   $(SRCDIR)/core/title_music.asm \
                   $(SRCDIR)/core/clear_nt.asm \
                   $(SRCDIR)/core/process_joy_buttons.asm \
                   $(SRCDIR)/core/enter_intro_story.asm \
                   $(SRCDIR)/core/intro_story.asm \
                   $(SRCDIR)/core/intro_story_joy.asm \
                   $(SRCDIR)/core/draw_2x2_sprite.asm \
                   $(SRCDIR)/core/draw_cursor.asm \
                   $(SRCDIR)/core/lut_cursor_2x2_sprite_table.asm \
                   $(SRCDIR)/core/pty_gen.asm \
                   $(SRCDIR)/core/map_draw.asm \
                   $(SRCDIR)/core/ow_player_sprite.asm \
                   $(SRCDIR)/core/lut_ow_player_sprite.asm
CORE_HOOKED_INCS = $(patsubst $(SRCDIR)/core/%.asm,$(BUILDDIR)/core/%.inc,$(CORE_HOOKED_SRCS))

# --- Shared sources (platform-agnostic) ------------------------------------
SHARED_SRCS = $(wildcard $(SRCDIR)/app/*.asm) \
              $(filter-out $(CORE_HOOKED_SRCS),$(wildcard $(SRCDIR)/core/*.asm)) \
              $(wildcard $(SRCDIR)/system/*.asm)

# --- Commander X16 ---------------------------------------------------------
X16_SRCS = $(wildcard $(SRCDIR)/system/x16/*.asm)
X16_OBJS = $(patsubst $(SRCDIR)/%.asm,$(BUILDDIR)/x16/%.o,$(SHARED_SRCS) $(X16_SRCS))
X16_CFG  = $(CFGDIR)/x16.cfg
X16_OUT  = $(BUILDDIR)/x16/FF.PRG

# --- Neo6502 ---------------------------------------------------------------
NEO_SRCS = $(wildcard $(SRCDIR)/system/neo/*.asm)
NEO_OBJS = $(patsubst $(SRCDIR)/%.asm,$(BUILDDIR)/neo/%.o,$(SHARED_SRCS) $(NEO_SRCS))
NEO_CFG  = $(CFGDIR)/neo.cfg
NEO_RAW  = $(BUILDDIR)/neo/ff.bin
NEO_OUT  = $(BUILDDIR)/neo/ff.neo

# --- Targets ---------------------------------------------------------------
.PHONY: all build-x16 build-neo run-x16 load-x16 run-neo load-neo clean

all: build-x16 build-neo

# --- Commander X16 build ---------------------------------------------------

build-x16: $(X16_OUT)

$(BUILDDIR)/x16/%.o: $(SRCDIR)/%.asm $(X16_FONT) $(X16_MAP_OW) $(X16_OWMAP) $(X16_OWTILESET) $(X16_INTRO_BIN) $(X16_CURSOR_VERA) $(X16_MAPMAN_VERA)
	@mkdir -p $(dir $@)
	$(CA65) --cpu 65C02 -D __X16__ -I $(SRCDIR) -I $(BUILDDIR)/core \
	        --bin-include-dir $(BUILDDIR)/x16 -o $@ $<

$(BUILDDIR)/x16/app/title_copyright_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/draw_palette_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/box_drawing_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/draw_complex_string_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/title_screen_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/joy_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/intro_story_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/sprite_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/pty_gen_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/map_draw_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/ow_player_sprite_shim.o: $(CORE_HOOKED_INCS)

$(X16_OUT): $(X16_OBJS) $(X16_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(X16_CFG) -o $@ $(X16_OBJS)

# HAL_SpritesInit issues a KERNAL LOAD for mapman_vera.bin at boot, so
# the file has to sit alongside FF.PRG in whatever directory x16emu
# treats as device 8 (the CWD when launched without -fsroot). cd into
# build/x16 so PRG + bin assets are colocated.
run-x16: build-x16
	cd $(dir $(X16_OUT)) && $(X16EMU) -prg FF.PRG -run

# load-x16: launch x16emu with FF.PRG loaded but not auto-run. Type RUN
# at the BASIC prompt when ready (useful for recording the boot sequence).
load-x16: build-x16
	cd $(dir $(X16_OUT)) && $(X16EMU) -prg FF.PRG

# --- Neo6502 build ---------------------------------------------------------

build-neo: $(NEO_OUT)

$(BUILDDIR)/neo/%.o: $(SRCDIR)/%.asm $(NEO_INTRO_BIN) $(NEO_OWMAP) $(NEO_OWTILESET)
	@mkdir -p $(dir $@)
	$(CA65) --cpu 65C02 -D __NEO__ -I $(SRCDIR) -I $(BUILDDIR)/core \
	        --bin-include-dir $(BUILDDIR)/neo -o $@ $<

$(BUILDDIR)/neo/app/title_copyright_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/draw_palette_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/box_drawing_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/draw_complex_string_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/title_screen_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/joy_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/intro_story_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/sprite_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/pty_gen_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/map_draw_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/ow_player_sprite_shim.o: $(CORE_HOOKED_INCS)

$(NEO_RAW): $(NEO_OBJS) $(NEO_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(NEO_CFG) -o $@ $(NEO_OBJS)

$(NEO_OUT): $(NEO_RAW) $(NEO_TILES_FONT_GFX) $(NEO_TILES_OW_GFX)
	python3 $(NEO_HOME)/exec.zip $(NEO_RAW)@800 run@800 -o"$(NEO_OUT)"

run-neo: build-neo
	@mkdir -p storage
	@cp $(NEO_OUT) storage/
	@cp $(NEO_TILES_FONT_GFX) storage/
	@cp $(NEO_TILES_OW_GFX) storage/
	$(NEOEMU) $(NEO_OUT) cold
	@rm -rf storage
	@rm -f memory.dump

# load-neo: stage storage/ with ff.neo + tileset .gfx files and launch
# Morpheus without auto-running the binary. Use this when recording the
# boot sequence manually from the monitor.
load-neo: build-neo
	@mkdir -p storage
	@cp $(NEO_OUT) storage/
	@cp $(NEO_TILES_FONT_GFX) storage/
	@cp $(NEO_TILES_OW_GFX) storage/
	$(NEOEMU) cold

# --- PPU hook rules --------------------------------------------------------

$(BUILDDIR)/core/%.inc: $(SRCDIR)/core/%.asm $(HOOK_SCRIPT)
	@mkdir -p $(dir $@)
	python3 $(HOOK_SCRIPT) $< $@

# --- Font conversion rules -------------------------------------------------

$(FF1_FONT_RAW):
	@mkdir -p $(dir $@)
	@cp "$(FF1_FONT_SRC)" $@

$(X16_FONT): $(CHR_SCRIPT) $(FF1_FONT_RAW)
	@mkdir -p $(dir $@)
	python3 $(CHR_SCRIPT) $(FF1_FONT_RAW) $@ \
	    --offset $(FF1_FONT_OFF) --tiles $(FF1_FONT_COUNT) --format x16

# --- Map-tile conversion rules ---------------------------------------------
# Same space-in-path staging as the font.

$(FF1_MAP_OW_RAW):
	@mkdir -p $(dir $@)
	@cp "$(FF1_MAP_OW_SRC)" $@

$(X16_MAP_OW): $(CHR_SCRIPT) $(FF1_MAP_OW_RAW)
	@mkdir -p $(dir $@)
	python3 $(CHR_SCRIPT) $(FF1_MAP_OW_RAW) $@ \
	    --offset $(FF1_MAP_OW_OFF) --tiles $(FF1_MAP_OW_COUNT) --format x16

# --- OW map-data extraction + staging --------------------------------------
# Script parses bank_01.asm's inline bytes (no space-in-path staging needed
# because the script takes the path directly; make never sees it as a target).

$(OWMAP_DAT): $(OWMAP_EXTRACT)
	@mkdir -p $(dir $@)
	python3 $(OWMAP_EXTRACT) --asm "$(FF1_OWMAP_ASM)" \
	    --bin "$(FF1_OWMAP_BIN)" --out $@

$(X16_OWMAP): $(OWMAP_DAT)
	@mkdir -p $(dir $@)
	@cp $< $@

$(NEO_OWMAP): $(OWMAP_DAT)
	@mkdir -p $(dir $@)
	@cp $< $@

# --- OW tileset-data extraction + staging ----------------------------------
# Slices the first 1 KB from bank_00.dat. dd keeps the rule simple; the
# space-in-path source is fine here since dd takes the path as a string.

$(OWTILESET_DAT):
	@mkdir -p $(dir $@)
	dd if="$(FF1_OWTILESET_SRC)" of=$@ bs=1 count=$(FF1_OWTILESET_LEN) \
	    skip=$(FF1_OWTILESET_OFF) status=none

$(X16_OWTILESET): $(OWTILESET_DAT)
	@mkdir -p $(dir $@)
	@cp $< $@

$(NEO_OWTILESET): $(OWTILESET_DAT)
	@mkdir -p $(dir $@)
	@cp $< $@

# --- Intro text staging ----------------------------------------------------
# No prerequisite on FF1_INTRO_SRC -- the path contains a space that
# GNU make would split into two targets (same reason FF1_FONT_RAW has
# no source-file dep). The file is shipped with the disassembly and
# effectively immutable, so a one-shot copy is correct.

$(X16_INTRO_BIN):
	@mkdir -p $(dir $@)
	@cp "$(FF1_INTRO_SRC)" $@

$(NEO_INTRO_BIN):
	@mkdir -p $(dir $@)
	@cp "$(FF1_INTRO_SRC)" $@

# --- Cursor CHR extraction + conversion ------------------------------------
# Same space-in-path workaround as the font rules: no file-dep on the
# bank_09.asm source, only on the script.

$(CURSOR_CHR): $(CURSOR_EXTRACT)
	@mkdir -p $(dir $@)
	python3 $(CURSOR_EXTRACT) "$(FF1_BANK_09_ASM)" $@

$(X16_CURSOR_VERA): $(X16_CURSOR_CONV) $(CURSOR_CHR)
	@mkdir -p $(dir $@)
	python3 $(X16_CURSOR_CONV) $(CURSOR_CHR) $@

# Mapman CHR extraction + conversion. Same space-in-path workaround:
# the extract script takes the disassembly path directly, so make only
# depends on the script, not the source .dat.

$(MAPMAN_CHR): $(MAPMAN_EXTRACT)
	@mkdir -p $(dir $@)
	python3 $(MAPMAN_EXTRACT) "$(FF1_DIS_ROOT)/bank_02.dat" $@

$(X16_MAPMAN_VERA): $(X16_MAPMAN_CONV) $(MAPMAN_CHR)
	@mkdir -p $(dir $@)
	python3 $(X16_MAPMAN_CONV) $(MAPMAN_CHR) $@

$(NEO_MAPMAN_POSES): $(NEO_MAPMAN_CONV) $(MAPMAN_CHR)
	@mkdir -p $(dir $@)
	python3 $(NEO_MAPMAN_CONV) $(MAPMAN_CHR) $@

$(NEO_TILES_FONT_GFX): $(NEO_TILES_CONV) $(FF1_FONT_RAW) $(CURSOR_CHR)
	@mkdir -p $(dir $@)
	python3 $(NEO_TILES_CONV) --mode font \
	    --tiles $(FF1_FONT_RAW) --tiles-offset $(FF1_FONT_OFF) \
	    --cursor $(CURSOR_CHR) --output $@

$(NEO_TILES_OW_GFX): $(NEO_TILES_CONV) $(FF1_MAP_OW_RAW) $(CURSOR_CHR) $(NEO_MAPMAN_POSES)
	@mkdir -p $(dir $@)
	python3 $(NEO_TILES_CONV) --mode map \
	    --tiles $(FF1_MAP_OW_RAW) --tiles-offset $(FF1_MAP_OW_OFF) \
	    --cursor $(CURSOR_CHR) --mapman $(NEO_MAPMAN_POSES) --output $@

# --- Housekeeping ----------------------------------------------------------

clean:
	rm -rf $(BUILDDIR) $(RELEASEDIR)
