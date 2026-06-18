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

.PHONY: generate generate-j4 generate-j1 check-j1-shared clean diff

generate:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -o ..

generate-j4:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -overlay spec/sh4 -o ..

generate-j1:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -profile spec/profiles/j1.toml -o ../j1
	$(MAKE) check-j1-shared

# check-j1-shared: verify J1 decoder consistency with the J2/J4 baseline.
# Files that are profile-independent must be byte-identical to root decode/.
# Files that encode the dropped instructions must differ (proves the drop
# actually took effect).
check-j1-shared:
	@set -e; \
	ok=1; \
	for f in decode.vhd decode_table.vhd decode_table_rom_config.vhd; do \
	  if ! diff -q $$f j1/$$f >/dev/null 2>&1; then \
	    echo "J1 SHARED FILE DIVERGED: $$f"; \
	    ok=0; \
	  fi; \
	done; \
	for f in decode_body.vhd decode_table_rom.vhd; do \
	  if diff -q $$f j1/$$f >/dev/null 2>&1; then \
	    echo "J1 ROM FILE UNCHANGED (drop ineffective): $$f"; \
	    ok=0; \
	  fi; \
	done; \
	if diff decode_pkg.vhd j1/decode_pkg.vhd | grep '^[<>]' | grep -vqE 'DEC_CORE_ROM_RESET|system_instr_rom_addrs'; then \
	  echo "J1 decode_pkg.vhd diverged beyond ROM-address constants:"; \
	  diff decode_pkg.vhd j1/decode_pkg.vhd | grep '^[<>]' | grep -vE 'DEC_CORE_ROM_RESET|system_instr_rom_addrs'; \
	  ok=0; \
	fi; \
	if [ $$ok -eq 0 ]; then exit 1; fi; \
	echo "check-j1-shared: OK"

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
