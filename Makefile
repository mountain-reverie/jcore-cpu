# Top-level convenience targets.
#
# NOT part of the FPGA/sim build graph: jcore-soc's mk_utils.mk includes
# build.mk / build_{sim,fpga,asic}.mk by name and never this file, so adding
# targets here cannot perturb a synthesis or simulation build.

TOOLS_DIR ?= $(CURDIR)/../jcore-soc/tools
V2P       := $(TOOLS_DIR)/v2p

# Generated files that are ALSO committed. These can silently drift from their
# sources: a stale copy builds and simulates perfectly well, so a fully green
# test suite cannot detect one. That is not hypothetical -- synthesis was
# broken for a stretch by a stale v2p output while every test stayed green,
# because sim/mmu_sim.sh regenerates at build time and therefore never reads
# the committed copy.
#
# Two generator families, checked the same way (regenerate, compare, never
# overwrite the working tree):
#   cpugen -> decode/*.vhd            (delegated to `make -C decode diff`)
#   v2p    -> core/datapath.vhd       (the only committed v2p output; every
#                                      other .vhm output is untracked and so
#                                      is regenerated from source every build)
V2P_TRACKED := core/datapath.vhd

.PHONY: verify-generated verify-v2p verify-decode

verify-generated: verify-decode verify-v2p
	@echo "OK: committed generated files match their sources"

verify-decode:
	@$(MAKE) --no-print-directory -C decode diff

verify-v2p:
	@set -e; ok=1; \
	for f in $(V2P_TRACKED); do \
	  src=$${f%.vhd}.vhm; \
	  if [ ! -f "$$src" ]; then echo "VERIFY: $$src missing"; ok=0; continue; fi; \
	  tmp=$$(mktemp); \
	  LD_LIBRARY_PATH='' perl $(V2P) < "$$src" > "$$tmp"; \
	  if ! diff -q "$$f" "$$tmp" >/dev/null 2>&1; then \
	    echo "VERIFY: $$f differs from a fresh v2p run of $$src"; \
	    echo "        (regenerate it and commit, or the committed copy will"; \
	    echo "         keep diverging from the .vhm that is the real source)"; \
	    diff "$$f" "$$tmp" | head -20; \
	    ok=0; \
	  fi; \
	  rm -f "$$tmp"; \
	done; \
	if [ $$ok -eq 0 ]; then exit 1; fi
