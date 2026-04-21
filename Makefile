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

# --- Shared sources (platform-agnostic) ------------------------------------
SHARED_SRCS = $(wildcard $(SRCDIR)/app/*.asm) \
              $(wildcard $(SRCDIR)/core/*.asm) \
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

$(BUILDDIR)/x16/%.o: $(SRCDIR)/%.asm
	@mkdir -p $(dir $@)
	$(CA65) --cpu 65C02 -D __X16__ -I $(SRCDIR) -o $@ $<

$(X16_OUT): $(X16_OBJS) $(X16_CFG)
	@mkdir -p $(dir $@)
	$(LD65) -C $(X16_CFG) -o $@ $(X16_OBJS)

run-x16: build-x16
	$(X16EMU) -prg $(X16_OUT)

# --- Neo6502 build ---------------------------------------------------------

build-neo: $(NEO_OUT)

$(BUILDDIR)/neo/%.o: $(SRCDIR)/%.asm
	@mkdir -p $(dir $@)
	$(CA65) --cpu 65C02 -D __NEO__ -I $(SRCDIR) -o $@ $<

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

# --- Housekeeping ----------------------------------------------------------

clean:
	rm -rf $(BUILDDIR) $(RELEASEDIR)
