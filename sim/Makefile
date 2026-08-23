GHDL := ghdl
IVERILOG := iverilog
IVERILOG_VPI := iverilog-vpi
TOOLS_DIR := $(firstword $(wildcard ../../mcu_lib/tools) $(wildcard ../../../tools))

# jcore-soc supplies the cache/lib/targets VHDL the sim now pulls in. Default to
# the sibling checkout (works in CI and the worktree: ../../jcore-soc from sim/);
# an explicit JCORE_SOC env overrides. Error clearly only if neither is present.
JCORE_SOC ?= $(firstword $(wildcard ../../jcore-soc) $(wildcard ../../../jcore-soc))
ifeq ($(strip $(JCORE_SOC)),)
$(error JCORE_SOC is not set and no sibling jcore-soc found — export JCORE_SOC)
endif

CONFIG_RING_BUS=0
CONFIG_PREFETCHER=0
# CONFIG_PRIV_ARCH used to be a standalone flag callers set directly
# (CONFIG_PRIV_ARCH=1). It is now DERIVED from CPU_VARIANT's variants.toml
# generics (see the override below, after `include ../Makefile.inc`):
# CPU_VARIANT=j4 -> PRIV_ARCH=true -> CONFIG_PRIV_ARCH=1. Default 0 here only
# covers the window before that include; every real build gets the derived
# value.
CONFIG_PRIV_ARCH=0
# Enable SH-2A ("J2A") extensions generic. Currently inert plumbing only
# (no gated behavior yet). Like CONFIG_PRIV_ARCH above, this is now DERIVED
# from CPU_VARIANT's variants.toml generics (see the override below, after
# `include ../Makefile.inc`): CPU_VARIANT=j2a -> SH2A_ARCH=true ->
# CONFIG_SH2A_ARCH=1. Default 0 here only covers the window before that
# include.
CONFIG_SH2A_ARCH=0
# J1/iCESugar DSP-ALU verification variant ONLY: bind cpu_sim_dsp_alu (datapath
# DSP_ALU=>true, core/dsp_arith.vhd exercised) instead of cpu_sim. Default 0
# leaves the default sim config (and its DSP_ALU=false datapath) untouched.
CONFIG_DSP_ALU=0
# Base direct-vs-ROM decoder symmetry check: bind cpu_sim_rom (u_decode =
# cpu_decode_rom) instead of cpu_sim (direct decoder). Base J2 only -- the
# ROM decoder cannot runtime-discriminate two-word SH-2A ext_word ops, so
# never combine with CONFIG_SH2A_ARCH=1. Default 0 leaves cpu_sim unchanged.
CONFIG_DECODE_ROM ?= 0
# J1 sequential-multiplier functional guard: bind cpu_sim_mult_seq (u_mult =
# mult(seq), the slow iterative multiplier normally only used by cpu_j1)
# instead of cpu_sim (mult(stru)). Runs the same instruction-level testrom,
# including the multiply tests, against mult(seq) -- the only functional
# test of that unit, since cpu_j1 is never otherwise simulated. Default 0
# leaves cpu_sim unchanged.
CONFIG_MULT_SEQ ?= 0

GHDL_EXISTS := $(shell sh -c 'which $(GHDL) >/dev/null && echo true')
IVERILOG_EXISTS := $(shell sh -c 'which $(IVERILOG) >/dev/null && echo true')
CROSSCOMP_EXISTS := $(shell sh -c 'which sh2-elf-gcc >/dev/null && echo true')

UNAME := $(shell sh -c 'uname -s 2>/dev/null || echo no')
ifeq ($(UNAME),Linux)
	LDLIBS := -lutil
endif
ifeq ($(UNAME),Darwin)
	LDLIBS :=
endif

CFLAGS := -Wall -Werror -Isim -g -Wno-deprecated-declarations

# Makefile.inc (included below, transitively via ../cache/build.mk too) defines
# rules of its own (the variants.mk bootstrap, the decode regeneration rule)
# before this file's own `all:` target is reached, so without this, GNU Make's
# default goal (the first target defined anywhere) silently becomes one of
# ITS targets instead of `all`. Set it explicitly here, as Makefile.inc's own
# header comment instructs includers to do.
.DEFAULT_GOAL := all

VHDLS := CPU_VHDS
CPU_VARIANT ?= j2
# Must default the same as Makefile.inc's own CPU_ROM_WIDTH default (below,
# before DECODE_GEN_DIR's key can include it) -- this file sets
# DECODE_GEN_DIR itself (overriding Makefile.inc's own default computation)
# so it has to know the width up front too.
CPU_ROM_WIDTH ?= 72
# Keyed by CPU_VARIANT AND CPU_ROM_WIDTH (mirrors Makefile.inc's own
# default, $(CPU_INC_DIR)gen/$(CPU_VARIANT)-w$(CPU_ROM_WIDTH) -- see its
# comment for the full rationale): un-keyed sim/gen was letting a
# `make CPU_VARIANT=j4` run reuse a stale j2 decoder left behind by an
# earlier `make CPU_VARIANT=j2` in the same sim/ tree (the regeneration
# rule's prerequisites are variants.toml/spec/cpugen-source timestamps, not
# CPU_VARIANT's or CPU_ROM_WIDTH's value, so switching either alone never
# invalidates a shared directory). Folding both into the directory name
# (rather than a separate opt-in stamp file for the width) means a caller
# here that only ever names the six .vhd targets (never a stamp) still
# gets correct invalidation.
DECODE_GEN_DIR := $(CURDIR)/gen/$(CPU_VARIANT)-w$(CPU_ROM_WIDTH)
include ../Makefile.inc
# Derive CONFIG_PRIV_ARCH from the selected variant's generics (CPU_GENERICS
# comes from Makefile.inc, which reads variants.toml). This is the interface
# CI and developers use: CPU_VARIANT=j4 (not a raw CONFIG_PRIV_ARCH=1 flag).
CONFIG_PRIV_ARCH := $(if $(filter PRIV_ARCH=true,$(CPU_GENERICS)),1,0)
# Derive CONFIG_SH2A_ARCH the same way: CPU_VARIANT=j2a -> SH2A_ARCH=true (see
# variants.toml's [j2a]) -> CONFIG_SH2A_ARCH=1. Like CONFIG_PRIV_ARCH, a
# command-line CONFIG_SH2A_ARCH=... override still wins (GNU Make command-line
# variables take precedence over in-makefile `:=` assignments).
CONFIG_SH2A_ARCH := $(if $(filter SH2A_ARCH=true,$(CPU_GENERICS)),1,0)
# $(CPU_DECODE_GENERATED) paths are already rooted at DECODE_GEN_DIR (i.e.
# under sim/gen), so only ../-prefix the entries that are tree-relative to
# components/cpu/; prefixing the generated ones again would mangle them.
CPU_VHDS := $(foreach f,$(CPU_VHDS),$(if $(filter $(DECODE_GEN_DIR)/%,$(f)),$(f),../$(f)))

# including ring bus is optional
ifeq ($(CONFIG_RING_BUS),1)
RBUS_VHDS :=
VHDLS := RBUS_VHDS
include ../../ring_bus/build.mk
CPU_VHDS += $(addprefix ../../ring_bus/,$(RBUS_VHDS))
endif

#including instruction prefetcher is optional
ifeq ($(CONFIG_PREFETCHER),1)
PREFETCH_VHDS :=
VHDLS := PREFETCH_VHDS
include ../../prefetch/build.mk
CPU_VHDS += $(addprefix ../../prefetch/,$(PREFETCH_VHDS))
endif

VHDS := $(CPU_VHDS) bridge_pkg.vhd monitor_pkg.vhd bus_monitor.vhd timeout_cnt.vhd cpu_tb.vhh data_bus_pkg.vhd cpu_pure_tb.vhh cpusim_miniaic2.vhd cpu_cache_tb.vhh
# J1/iCESugar DSP-ALU prototype (see core/cpu_config_sim.vhd cpu_sim_dsp_alu):
# core/dsp_arith.vhd is only ever elaborated when CONFIG_DSP_ALU=1 selects
# that configuration, but must be analyzed unconditionally so the -obj93.cf
# library contains it. core/sb_mac16_sim.vhd binds SB_MAC16 in simulation
# (same idiom as core/mult_ice40dsp.vhd).
VHDS += ../core/dsp_arith.vhd ../core/sb_mac16_sim.vhd
# core/mult_seq.vhd (see core/cpu_config_sim.vhd cpu_sim_mult_seq): only ever
# elaborated when CONFIG_MULT_SEQ=1 selects that configuration, but must be
# analyzed unconditionally so the -obj93.cf library contains it (same idiom
# as dsp_arith.vhd above).
VHDS += ../core/mult_seq.vhd
# core/cpu_config_sim.vhd holds the sim-only cpu_sim/_sh2a/_dsp_alu/_rom
# configurations selected by CONFIG_* in cpu_tb.vhd. Sim-only: it must NOT
# be added to build_core.mk (FPGA/ASIC builds never bind these).
VHDS += ../core/cpu_config_sim.vhd
VHDS += mem/cpu_sram.vhd mem/asymmetric_ram.vhd
# core/tlb.vhd is only a CPU_VHDS member for the j4 variant (variants.toml
# extra_files); tlb_tb directly instantiates `entity work.tlb` as its DUT
# regardless of CPU_VARIANT, so analyze it unconditionally here (same idiom as
# core/dsp_arith.vhd above) rather than forcing the whole sim onto
# CPU_VARIANT=j4.
#
# tlb_match_tb.vhd was RETIRED 2026-08-23. It was an 8-test bench that had
# rotted twice over, precisely because nothing ran it: stale against the
# ITLB/DTLB split (f155124, it named the removed i_*/d_* port pairs), and stale
# in SEMANTICS -- repaired to the split entity it fails its own T1, "spurious
# prot on readable+executable entry", because that entry is U=1 fetched with
# MD=1, which is an SMEP violation the design now deliberately raises (mmusmep,
# tlb.vhd's I-side leaf predicate). Its expectations pre-date SMEP.
#
# It was NOT a pure subset of tlb_tb, and the properties it alone held were
# MOVED rather than dropped: T1/T1b (the C-bit export follows PTEL[3], in both
# states, on both sides -- tlb_tb connected i_c/d_c but never checked them) and
# T8 (concurrent I and D lookups of different entries return different PA tags)
# are now tlb_tb cases 26 and 27. Everything else it checked tlb_tb already
# covered. tlb_tb is wired into sim/mmu_sim.sh and CI.
VHDS += ../core/tlb.vhd
VHDS += tlb_tb.vhd
VHDS += seg_decode_tb.vhd
VHDS += ddrc_cnt_pkg_stub.vhd
VHDS += $(JCORE_SOC)/targets/data_bus_pkg.vhd
VHDS += $(JCORE_SOC)/lib/hwutils/attr_pkg.vhd
VHDS += $(JCORE_SOC)/lib/hwutils/util_pkg.vhd
VHDS += $(JCORE_SOC)/lib/hwutils/gray_pkg.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/memory_pkg.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/tech/sim/mem_sim_config.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/ram_1rw.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/ram_2x8x256_1rw.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/tech/sim/ram_2x8x256_1rw_sim.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/ram_1rw_mems.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/ram_2rw.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/ram_2x8x2048_2rw.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/tech/sim/ram_2x8x2048_2rw_sim.vhd
VHDS += $(JCORE_SOC)/lib/memory_tech_lib/ram_2rw_mems.vhd
CACHE_VHDS :=
VHDLS := CACHE_VHDS
include ../cache/build.mk
VHDS += $(addprefix ../cache/,$(CACHE_VHDS))
# Testbenches are sim-only; they stay hand-listed here rather than living in
# cache/build_core.mk (which FPGA/ASIC board builds also consume).
VHDS += ../cache/icache_cacheable_mux_tb.vhd
VHDS += ../cache/is_cacheable_tb.vhd
VHDS += ../cache/dcache_color_tb.vhd
VHDS += bus_mux_pkg.vhd multi_master_bus_mux.vhd
VHDS += dcache_snoop_cacheable_mux.vhd
VHDS += cpu_dualcore_tb.vhh
#UNISIM_VHDS := unisims/unisim_VCOMP.vhd unisims/unisim_VPKG.vhd $(wildcard unisims/primitive/*.vhd)

VHDL_TOPS := cpu_tb cpu_pure_tb tlb_tb seg_decode_tb is_cacheable_tb dcache_color_tb icache_cacheable_mux_tb cpu_cache_tb cpu_dualcore_tb
#VHDL_LIBS := unisim work
VHDL_LIBS := work

# sh2instr.c is a cpugen output, like the six CPU_DECODE_GENERATED VHDL
# files (Makefile.inc), but it is not one of CPU_DECODE_GEN_NAMES (that list
# is VHDL-only) -- cpugen writes it as a side effect of the same -o
# $(DECODE_GEN_DIR)/decode invocation. It therefore lives under
# DECODE_GEN_DIR too, keyed by CPU_VARIANT/CPU_ROM_WIDTH like everything
# else cpugen produces, so a CPU_VARIANT=j4 cosim gets j4's instruction
# table (sh4 overlay ops included) and a j2 cosim gets j2's, instead of
# whatever variant a stray in-tree decode/sh2instr.c happened to be built
# from last.
SH2INSTR_C := $(DECODE_GEN_DIR)/decode/sh2instr.c

SRCS := cpu_ctb.c $(SH2INSTR_C) delays.c debug.c debug_plan.c debug_skt.c recv_buf.c sim/uart.c sim/bitvec.c sim/mem_bus.c sim/packet_gen.c sim/simulator.c

all: pinst

ifeq ($(GHDL_EXISTS),true)
all: $(VHDL_TOPS) cpu_ctb cpu_tb.vhh
include $(TOOLS_DIR)/ghdl.mk
# tell simulator.c if mcode backend is being used
ifeq ($(GHDL_BACKEND_MCODE),y)
CFLAGS += -DGHDL_MCODE_BACKEND
endif
endif
ifeq ($(IVERILOG_EXISTS),true)
VPI_CFLAGS := $(shell $(IVERILOG_VPI) --cflags)
all: sim/vpibridge.vpi decodeop
endif
ifeq ($(CROSSCOMP_EXISTS),true)
all: ram.img
endif

#unisim-obj93.cf: $(UNISIM_VHDS)
work-obj93.cf: $(VHDS)

decodeop.o: decode_signals.h
decodeop: decodeop.o sim/simulator.o sim/bitvec.o sh2instr.o

pinst: pinst.o sh2instr.o
pinst.o: pinst.c sh2instr.h

# sh2instr.c is generated by cpugen into DECODE_GEN_DIR/decode/ (see
# SH2INSTR_C above); depending on $(CPU_DECODE_GENERATED) here piggybacks
# on the grouped cpugen regeneration rule in Makefile.inc so a stale or
# missing sh2instr.c for this CPU_VARIANT/CPU_ROM_WIDTH gets regenerated
# rather than silently reusing whatever a previous invocation left behind.
# -I. is needed so the #include "sh2instr.h" in the generated file resolves
# to the header in this directory.
$(SH2INSTR_C): $(CPU_DECODE_GENERATED)

sh2instr.o: $(SH2INSTR_C) sh2instr.h
	$(COMPILE.c) -I. -MD -o $@ $<
	@cp sh2instr.d sh2instr.P; \
	  sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
	  -e '/^$$/ d' -e 's/$$/ :/' < sh2instr.d >> sh2instr.P; \
	  rm -f sh2instr.d

sim/vpibridge.vpi: CFLAGS := $(CFLAGS) $(VPI_CFLAGS)
sim/vpibridge.vpi: sim/vpibridge.o

cpu_ctb: cpu_ctb.o sim/simulator.o sim/bitvec.o sim/mem_bus.o sim/uart.o sim/uartlite.o sh2instr.o delays.o debug.o debug_plan.o debug_skt.o recv_buf.o
cpu_pure_tb: ram.img

# compiles and creates dependency files
%.o : %.c
	$(COMPILE.c) -MD -o $@ $<
	@cp $*.d $*.P; \
	  sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
	  -e '/^$$/ d' -e 's/$$/ :/' < $*.d >> $*.P; \
	  rm -f $*.d

-include $(SRCS:.c=.P)

# ---------------------------------------------------------------------------
# CPU_VARIANT stamp. The .vhh preprocessing below bakes in -DCONFIG_PRIV_ARCH /
# -DCONFIG_SH2A_ARCH / ..., all DERIVED from CPU_VARIANT, but make compares only
# the .vhd/.h timestamps -- so `make CPU_VARIANT=j4 cpu_tb.vhh` over a tree built
# at j2 reports "up to date" and leaves a PRIV_ARCH=false testbench in place.
# MEASURED: without this, that exact sequence leaves `grep -c 'PRIV_ARCH => true'
# cpu_tb.vhh` at 0 after asking for j4.
#
# DECODE_GEN_DIR above already solves this for the generated decoder by keying
# its path on $(CPU_VARIANT)-w$(CPU_ROM_WIDTH); this is the same guarantee for
# the artifacts that are NOT path-keyed. sim/mmu_sim.sh's `rm -f cpu_tb.vhh
# cpu_ctb ...` and its defensive `grep -q 'PRIV_ARCH => true'` were both
# workarounds for this missing dependency.
#
# Rewritten only when the value CHANGES, so it does not force a rebuild on
# every invocation.
.PHONY: FORCE
.cpu-variant: FORCE
	@echo '$(CPU_VARIANT) $(CPU_ROM_WIDTH) $(CONFIG_PRIV_ARCH) $(CONFIG_SH2A_ARCH) $(CONFIG_DSP_ALU) $(CONFIG_DECODE_ROM) $(CONFIG_MULT_SEQ) $(CONFIG_PREFETCHER) $(CONFIG_RING_BUS)' > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else \
	  test ! -f $@ || echo "  CPU_VARIANT/config changed; rebuilding"; \
	  mv $@.tmp $@; fi

# Add dependencies to particular vhh files. TODO: how to avoid
# repeating this rule?
cpu_tb.vhh: cpu_tb.vhd cpu_signals.h sim/sim_macros.h .cpu-variant
	LD_LIBRARY_PATH='' gcc -x c-header -E -P -w -nostdinc -DVHDL -DCONFIG_PREFETCHER=$(CONFIG_PREFETCHER) -DCONFIG_RING_BUS=$(CONFIG_RING_BUS) -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH) -DCONFIG_SH2A_ARCH=$(CONFIG_SH2A_ARCH) -DCONFIG_DSP_ALU=$(CONFIG_DSP_ALU) -DCONFIG_DECODE_ROM=$(CONFIG_DECODE_ROM) -DCONFIG_MULT_SEQ=$(CONFIG_MULT_SEQ) -I. -I../config -Isim $< -o $@

cpu_cache_tb.vhh: cpu_cache_tb.vhd cpu_signals.h sim/sim_macros.h .cpu-variant
	LD_LIBRARY_PATH='' gcc -x c-header -E -P -w -nostdinc -DVHDL -DCONFIG_PREFETCHER=$(CONFIG_PREFETCHER) -DCONFIG_RING_BUS=$(CONFIG_RING_BUS) -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH) -DCONFIG_DSP_ALU=$(CONFIG_DSP_ALU) -I. -I../config -Isim $< -o $@

cpu_dualcore_tb.vhh: cpu_dualcore_tb.vhd cpu_signals.h sim/sim_macros.h .cpu-variant
	LD_LIBRARY_PATH='' gcc -x c-header -E -P -w -nostdinc -DVHDL -DCONFIG_PREFETCHER=$(CONFIG_PREFETCHER) -DCONFIG_RING_BUS=$(CONFIG_RING_BUS) -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH) -I. -I../config -Isim $< -o $@

%.vpi:
	$(IVERILOG_VPI) --name=$* $^

%.vvp:
	$(IVERILOG) $(IVFLAGS) -o$@ $^

ifeq ($(CROSSCOMP_EXISTS),true)
ram.img: ../testrom/main.elf
	sh2-elf-objcopy -v -S -O binary --srec-forceS3 $^ $@

../testrom/main.elf:
	make -C ../testrom main.elf
endif

PURE_SIM_VHDS := $(filter-out cpu_tb.vhh,$(VHDS))
PURE_SIM_VHDS := $(filter-out bridge_pkg.vhd,$(PURE_SIM_VHDS))
PURE_SIM_VHDS := $(sort $(PURE_SIM_VHDS))

cpu_sim_pkg: $(PURE_SIM_VHDS) ram.img
	rm -rf $@
	mkdir -p $@/vhd
	cp $(PURE_SIM_VHDS) $@/vhd
	(cd $@/vhd; rename .vhh .vhd *.vhh)
	mkdir -p $@/tools
	cp $(TOOLS_DIR)/*.mk $@/tools
	cp ram.img $@/
	cp Makefile_cpu_sim_pkg $@/Makefile

# Base direct-vs-ROM decoder symmetry check: the direct/simple decoder and
# the ROM decoder are generated from ONE microcode model, so for BASE J2 they
# must behave identically. This target builds the ROM-decoder cosim
# (cpu_sim_rom, CONFIG_DECODE_ROM=1) and runs representative BASE test images
# on it, asserting each prints "Test Passed" -- the same result the default
# direct-decoder build produces. Base J2 only: never combine with
# CONFIG_SH2A_ARCH=1 (the ROM decoder cannot runtime-discriminate the
# ext_word of two-word SH-2A ops, so those are DIRECT-decoder-only).
DECODE_SYMMETRY_TESTS := m8_macarith banktest
decode-symmetry:
	rm -f work-obj93.cf cpu_tb.vhh cpu_ctb
	$(MAKE) CONFIG_DECODE_ROM=1 cpu_ctb work-obj93.cf
	$(MAKE) -C tests $(addsuffix .img,$(DECODE_SYMMETRY_TESTS))
	@fail=0; for t in $(DECODE_SYMMETRY_TESTS); do \
	  echo "== decode-symmetry [ROM]: $$t =="; \
	  if ./cpu_ctb --stop-time=10us -i tests/$$t.img 2>&1 | grep -q 'Test Passed'; then \
	    echo "   PASS [$$t]"; \
	  else \
	    echo "   FAIL [$$t]: ROM decoder did not print 'Test Passed'" >&2; fail=1; \
	  fi; \
	done; \
	rm -f work-obj93.cf cpu_tb.vhh cpu_ctb; \
	$(MAKE) cpu_ctb work-obj93.cf >/dev/null; \
	if [ $$fail -ne 0 ]; then \
	  echo "decode-symmetry: base direct-vs-ROM decoder DESYNC detected" >&2; exit 1; \
	fi; \
	echo "decode-symmetry: base ROM decoder matches direct (all tests passed)"

.PHONY: decode-symmetry

clean:
	rm -f *.o *.P *.vpi *.vvp sim/*.o sim/*.P sim/*.vpi sim/*.vvp *.vhh
	rm -f *.cf $(VHDL_TOPS) cpu_ctb
	rm -f decodeop .cpu-variant
#	rm -f ram.img

.PHONY: clean cpu_sim_pkg
