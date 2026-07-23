# Decoder regeneration via the Go cpugen tool.
#
# Usage:
#   make -C decode generate          # regenerate VHDL files (default ROM width 72)
#   make -C decode generate ROM_WIDTH=64
#   make -C decode clean              # remove generated VHDL files

GEN_DIR := gen-go
ROM_WIDTH ?= 72

#
# Note: decode_core.vhd is NOT in GENERATED. It is a C-preprocessor
# output of decode_core.vhm produced by sim/Makefile, not by cpugen.
# Including it here would let `make clean` delete it without `make
# generate` being able to restore it.
GENERATED := \
    decode_pkg.vhd \
    decode.vhd \
    decode_body.vhd \
    decode_table_simple.vhd \
    decode_table_direct.vhd \
    decode_table_rom.vhd \
    sh2instr.c

.PHONY: generate generate-j4 generate-j2a m8gen clean diff insns insns-check

generate:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -o ..

generate-j4:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -overlay spec/sh4 -o ..

generate-j2a:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -overlay spec/sh2a -o ..

insns:
	go -C $(GEN_DIR) run ./cmd/cpugen insns -json ../../docs/insns.json

insns-check:
	go -C $(GEN_DIR) run ./cmd/cpugen insns -check -json ../../docs/insns.json

# measure-timing: rebuild each variant's cosim and sweep every instruction's
# real issue/latency on it, regenerating the measured timing tables + insns.json.
# SLOW (a GHDL build + ~150 cosim runs per variant) -> run ON DEMAND, not in CI.
# Requires TOOLS_DIR (shared GHDL build makefiles) + the sh2-elf toolchain. Each
# variant's GHDL work library (work-obj93.cf) has a fixed name, so variants are
# built-then-swept sequentially (make clean between). J1 is NOT measured -- its
# sequential shifter/mult aren't bound in any cosim config (Finding B) -- so it
# keeps its hand-authored timing/j1.toml.
#
# IMPORTANT: the sim compiles the *committed* decode/*.vhd verbatim -- it does
# NOT regenerate them. The committed tables are the BASE (no-overlay) generation,
# so a variant-specific op (e.g. SH-2A divs/divu, decoded only under the sh2a
# overlay) has NO microcode in them: on the J2A cosim such an op mis-decodes, the
# functional unit never engages, and the microbenchmark faults instead of
# measuring. So each variant must regenerate decode/*.vhd WITH its overlay
# ($(gen) below) BEFORE building the sim, then we restore the base generation at
# the end so the working tree is not left dirty. Fields: name|CONFIG flag|gen target.
measure-timing:
	@set -e; root=$$(cd .. && pwd); \
	for cfg in "j2||generate" "j2a|CONFIG_SH2A_ARCH=1|generate-j2a" "j4|CONFIG_PRIV_ARCH=1|generate-j4"; do \
	  v=$${cfg%%|*}; rest=$${cfg#*|}; flag=$${rest%%|*}; gen=$${rest##*|}; \
	  V=$$(echo $$v | tr a-z A-Z); \
	  echo "=== $$V: regen decode ($$gen) + build ($$flag) + sweep ==="; \
	  $(MAKE) $$gen ROM_WIDTH=$(ROM_WIDTH); \
	  $(MAKE) -C $$root/sim clean >/dev/null 2>&1; \
	  $(MAKE) -C $$root/sim $$flag TOOLS_DIR=$(TOOLS_DIR) >/dev/null; \
	  go -C $(GEN_DIR) run ./cmd/measure -variant $$V \
	    -cosim $$root/sim/cpu_ctb -simdir $$root/sim \
	    -out $$root/decode/$(GEN_DIR)/timing/$$v.measured.toml; \
	done; \
	$(MAKE) generate ROM_WIDTH=$(ROM_WIDTH); \
	$(MAKE) insns

# m8gen: regenerate the M8 batched fault-test images + manifest into sim/tests.
# A different generator than the decoder: classifies every instruction and
# emits self-checking fault-transparency cases (see gen-go/internal/faultgen).
m8gen:
	go -C $(GEN_DIR) run ./cmd/m8gen -overlay spec/sh4 -o ../../sim/tests

clean:
	rm -f $(GENERATED)

# diff: regenerate into a temp dir and compare against working-tree files.
# Exits non-zero (and prints a unified diff excerpt) if any generated file
# differs. Skips files that are not in GENERATED (configs, decode_core, etc.).
diff:
	@set -e; \
	tmp=$$(mktemp -d); \
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -o $$tmp >/dev/null; \
	ok=1; \
	for f in $(GENERATED); do \
	  if [ ! -f $$f ]; then \
	    echo "DIFF: $$f is missing from working tree (run 'make generate')"; \
	    ok=0; \
	  elif ! diff -q $$f $$tmp/$$f >/dev/null 2>&1; then \
	    echo "DIFF: $$f differs from regenerated output"; \
	    diff $$f $$tmp/$$f | head -20; \
	    ok=0; \
	  fi; \
	done; \
	rm -rf $$tmp; \
	if [ $$ok -eq 0 ]; then exit 1; fi; \
	echo "OK: all generated files up to date"
