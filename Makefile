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

# Neo graphics plane artefact. Single .gfx file holds 128 FF1 font tiles
# (16x16 images, glyph in upper-left) and 1 cursor sprite. Loaded into
# gfxObjectMemory once at boot and addressed by Draw Image + Sprite Set.
NEO_TILES_GFX   := $(BUILDDIR)/neo/tiles.gfx
NEO_TILES_CONV  := $(SCRIPTDIR)/chr_to_neo_gfx.py

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
                   $(SRCDIR)/core/pty_gen.asm
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

$(BUILDDIR)/x16/%.o: $(SRCDIR)/%.asm $(X16_FONT) $(X16_INTRO_BIN) $(X16_CURSOR_VERA)
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

$(X16_OUT): $(X16_OBJS) $(X16_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(X16_CFG) -o $@ $(X16_OBJS)

run-x16: build-x16
	$(X16EMU) -prg $(X16_OUT) -run

# load-x16: launch x16emu with FF.PRG loaded but not auto-run. Type RUN
# at the BASIC prompt when ready (useful for recording the boot sequence).
load-x16: build-x16
	$(X16EMU) -prg $(X16_OUT)

# --- Neo6502 build ---------------------------------------------------------

build-neo: $(NEO_OUT)

$(BUILDDIR)/neo/%.o: $(SRCDIR)/%.asm $(NEO_INTRO_BIN)
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

$(NEO_RAW): $(NEO_OBJS) $(NEO_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(NEO_CFG) -o $@ $(NEO_OBJS)

$(NEO_OUT): $(NEO_RAW) $(NEO_TILES_GFX)
	python3 $(NEO_HOME)/exec.zip $(NEO_RAW)@800 run@800 -o"$(NEO_OUT)"

run-neo: build-neo
	@mkdir -p storage
	@cp $(NEO_OUT) storage/
	@cp $(NEO_TILES_GFX) storage/
	$(NEOEMU) $(NEO_OUT) cold
	@rm -rf storage
	@rm -f memory.dump

# load-neo: stage storage/ with ff.neo + tiles.gfx and launch Morpheus
# without auto-running the binary. Use this when recording the boot
# sequence manually from the monitor.
load-neo: build-neo
	@mkdir -p storage
	@cp $(NEO_OUT) storage/
	@cp $(NEO_TILES_GFX) storage/
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

$(NEO_TILES_GFX): $(NEO_TILES_CONV) $(FF1_FONT_RAW) $(CURSOR_CHR)
	@mkdir -p $(dir $@)
	python3 $(NEO_TILES_CONV) --font $(FF1_FONT_RAW) --font-offset $(FF1_FONT_OFF) \
	    --cursor $(CURSOR_CHR) --output $@

# --- Housekeeping ----------------------------------------------------------

clean:
	rm -rf $(BUILDDIR) $(RELEASEDIR)
