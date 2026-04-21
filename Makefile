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
NEO_FONT       := $(BUILDDIR)/neo/font_converted.bin

# --- Core routines hooked through scripts/hook_ppu.py ----------------------
# Files listed here are verbatim FF1 extracts. They have no ca65 directives
# and no HAL imports, so the wildcard compile rule would fail on them. The
# hook script rewrites PPU port writes into JSRs and drops the result in
# build/core/; a matching shim in src/app/ supplies segment/imports/exports
# and .includes the generated file.
HOOK_SCRIPT    := $(SCRIPTDIR)/hook_ppu.py
CORE_HOOKED_SRCS = $(SRCDIR)/core/title_copyright.asm \
                   $(SRCDIR)/core/draw_palette.asm
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
.PHONY: all build-x16 build-neo run-x16 run-neo clean

all: build-x16 build-neo

# --- Commander X16 build ---------------------------------------------------

build-x16: $(X16_OUT)

$(BUILDDIR)/x16/%.o: $(SRCDIR)/%.asm $(X16_FONT)
	@mkdir -p $(dir $@)
	$(CA65) --cpu 65C02 -D __X16__ -I $(SRCDIR) -I $(BUILDDIR)/core \
	        --bin-include-dir $(BUILDDIR)/x16 -o $@ $<

$(BUILDDIR)/x16/app/title_copyright_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/x16/app/draw_palette_shim.o: $(CORE_HOOKED_INCS)

$(X16_OUT): $(X16_OBJS) $(X16_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(X16_CFG) -o $@ $(X16_OBJS)

run-x16: build-x16
	$(X16EMU) -prg $(X16_OUT)

# --- Neo6502 build ---------------------------------------------------------

build-neo: $(NEO_OUT)

$(BUILDDIR)/neo/%.o: $(SRCDIR)/%.asm $(NEO_FONT)
	@mkdir -p $(dir $@)
	$(CA65) --cpu 65C02 -D __NEO__ -I $(SRCDIR) -I $(BUILDDIR)/core \
	        --bin-include-dir $(BUILDDIR)/neo -o $@ $<

$(BUILDDIR)/neo/app/title_copyright_shim.o: $(CORE_HOOKED_INCS)
$(BUILDDIR)/neo/app/draw_palette_shim.o: $(CORE_HOOKED_INCS)

$(NEO_RAW): $(NEO_OBJS) $(NEO_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(NEO_CFG) -o $@ $(NEO_OBJS)

$(NEO_OUT): $(NEO_RAW)
	python3 $(NEO_HOME)/exec.zip $(NEO_RAW)@800 run@800 -o"$(NEO_OUT)"

run-neo: build-neo
	@mkdir -p storage
	@cp $(NEO_OUT) storage/
	$(NEOEMU) $(NEO_OUT) cold
	@rm -rf storage
	@rm -f memory.dump

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

$(NEO_FONT): $(CHR_SCRIPT) $(FF1_FONT_RAW)
	@mkdir -p $(dir $@)
	python3 $(CHR_SCRIPT) $(FF1_FONT_RAW) $@ \
	    --offset $(FF1_FONT_OFF) --tiles 64 --format neo

# --- Housekeeping ----------------------------------------------------------

clean:
	rm -rf $(BUILDDIR) $(RELEASEDIR)
