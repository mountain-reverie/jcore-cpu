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

.PHONY: generate clean diff

generate:
	go -C $(GEN_DIR) run ./cmd/cpugen -w $(ROM_WIDTH) -o ..

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
