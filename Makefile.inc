# Makefile.inc -- the Make-side reader of variants.toml.
#
# Inputs (set by the includer BEFORE including this file):
#   CPU_VARIANT     j1 | j2 | j2a | j4   (default j2)
#   TARGET_KIND     sim | fpga | asic    (default fpga)
#   DECODE_GEN_DIR  out-of-tree root for regenerated decode sources
#   VHDLS           name of the variable to append paths to (mk_utils.mk idiom)
#
# Paths appended to $(VHDLS) are relative to components/cpu/, matching what
# mk_utils.mk expects; it prefixes them with the directory it is scanning.
#
# NOTE TO INCLUDERS: this file defines Make rules (the variants.mk bootstrap,
# the decode regeneration rule). GNU Make's default goal is the first target
# defined anywhere it has read so far -- so if you `include` this file before
# your own first target, one of ITS rules silently becomes your default goal.
# Either include this file AFTER your own first target, or set
# .DEFAULT_GOAL yourself beforehand. This file deliberately does not set
# .DEFAULT_GOAL, since doing so here would override the includer's intent.

# This file uses GNU Make 4.3's grouped-target ("&:") syntax below for the
# decode regeneration rule. Pre-4.3 Make has no idea what "&:" means: it
# tokenizes the target side on whitespace and treats the literal "&" as a
# spurious extra ordinary target, silently falling back to classic
# multi-target semantics -- i.e. the exact `make -jN` race this file exists
# to prevent, with no syntax error and no warning. Fail loudly instead.
ifeq ($(filter grouped-target,$(.FEATURES)),)
$(error Makefile.inc requires GNU Make 4.3+ for grouped-target '&:' support \
  (needed so `make -jN` runs the decode-regeneration recipe exactly once \
  instead of racing N-way across the six generated decode files). \
  Found: $(MAKE_VERSION). Install GNU Make >= 4.3 (e.g. from https://www.gnu.org/software/make/ \
  or your distro's newer make package, such as Ubuntu 22.04+))
endif

CPU_INC_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
CPU_VARIANT ?= j2
TARGET_KIND ?= fpga
# Per-variant subdirectory (not just $(CPU_INC_DIR)gen): jcore-soc's top-level
# Makefile builds one board at a time, but each board can select a different
# CPU_VARIANT while sharing this same components/cpu working tree. The
# regeneration rule below only depends on variants.toml/spec/cpugen-source
# timestamps, NOT on CPU_VARIANT's value -- so a single shared DECODE_GEN_DIR
# would let a stale OTHER variant's decoder (e.g. j2's, with no LDTLB) survive
# untouched across a `make ulx3s && make gf180_j4mmu` sequence, since none of
# the rule's prerequisites changed. Keying the directory by $(CPU_VARIANT)
# gives every variant its own persistent, never-confused output location.
DECODE_GEN_DIR ?= $(CPU_INC_DIR)gen/$(CPU_VARIANT)

# variants.mk is generated from variants.toml. GNU Make remakes included files
# and re-execs, so this bootstraps on a clean tree. Go is a baseline build
# requirement (see the spec's D7) -- fail loudly rather than guess.
$(DECODE_GEN_DIR)/variants.mk: $(CPU_INC_DIR)variants.toml
	@command -v go >/dev/null 2>&1 || { \
	  echo "ERROR: go is required to read variants.toml. Install Go (https://go.dev/dl/)." >&2; \
	  exit 1; }
	@mkdir -p $(dir $@)
	@go -C $(CPU_INC_DIR)decode/gen-go run ./cmd/cpugen variants \
	    -format=make -variants $(abspath $(CPU_INC_DIR)variants.toml) -o $(abspath $@)

# The ifeq/$(error) guard just below (checking CPU_VARIANT against
# CPU_VARIANT_ALL) runs during Make's *first* read pass, before Make's normal
# "remake a missing included makefile, then restart" cycle ever gets a chance
# to run -- that cycle only fires once a full read pass has completed without
# a fatal $(error). On a clean tree, without this bootstrap, $(error) would
# abort before the rule above ever runs. So generate eagerly at parse time on
# a clean tree; the rule above still exists and still fires normally (via
# make's own prerequisite/remake machinery) to regenerate variants.mk once
# variants.toml changes on a tree that already has one.
ifeq ($(wildcard $(DECODE_GEN_DIR)/variants.mk),)
ifeq ($(shell command -v go >/dev/null 2>&1 && echo yes),)
$(error ERROR: go is required to read variants.toml. Install Go (https://go.dev/dl/))
endif
$(shell mkdir -p $(DECODE_GEN_DIR) && go -C $(CPU_INC_DIR)decode/gen-go run ./cmd/cpugen variants \
    -format=make -variants $(abspath $(CPU_INC_DIR)variants.toml) -o $(abspath $(DECODE_GEN_DIR)/variants.mk))
endif

include $(DECODE_GEN_DIR)/variants.mk

ifeq ($(filter $(CPU_VARIANT),$(CPU_VARIANT_ALL)),)
$(error CPU_VARIANT '$(CPU_VARIANT)' is not one of: $(CPU_VARIANT_ALL))
endif

CPU_OVERLAY     := $(CPU_VARIANT_$(CPU_VARIANT)_OVERLAY)
CPU_GENERICS    := $(CPU_VARIANT_$(CPU_VARIANT)_GENERICS)
CPU_EXTRA_FILES := $(CPU_VARIANT_$(CPU_VARIANT)_EXTRA_FILES)
CPU_CONFIG_FILE := $(CPU_VARIANT_$(CPU_VARIANT)_CONFIG_FILE)

# CONFIG_* defines for the C-preprocessor (.vhm -> .vhd) step. Derived from the
# variant's generics: PRIV_ARCH=true -> -DCONFIG_PRIV_ARCH=1.
CPU_CONFIG_DEFINES := $(foreach g,$(CPU_GENERICS),\
  -DCONFIG_$(word 1,$(subst =, ,$(g)))=$(if $(filter true,$(word 2,$(subst =, ,$(g)))),1,0))

# Decode sources are GENERATED per variant, always out-of-tree. Overlays are
# additive and produce the SAME filenames as the base generation, so a variant's
# decoder cannot be expressed as a file list -- only as a regeneration. The
# committed decode/*.vhd stay the base generation forever (pr-quick.yml enforces
# it); nothing here writes into the working tree.
CPU_DECODE_GEN_NAMES := decode_pkg.vhd decode.vhd decode_body.vhd \
                        decode_table_simple.vhd decode_table_direct.vhd \
                        decode_table_rom.vhd
CPU_DECODE_GENERATED := $(addprefix $(DECODE_GEN_DIR)/decode/,$(CPU_DECODE_GEN_NAMES))
CPU_ROM_WIDTH ?= 72

# CPU_ROM_WIDTH is NOT part of DECODE_GEN_DIR's key (only CPU_VARIANT is), so
# two consumers of the SAME variant with different CPU_ROM_WIDTH would
# otherwise silently share whichever one built first -- the identical
# staleness class the per-variant directory exists to prevent, just one
# level down. CPU_DECODE_ROM_WIDTH_STAMP is a marker for "this directory's
# six files were built for THIS width"; it is a member of the grouped
# target below, so a width mismatch (stamp for the requested width missing)
# forces the whole group to regenerate -- atomically, like everything else
# in the group -- rather than only rebuilding the stamp itself.
CPU_DECODE_ROM_WIDTH_STAMP := $(DECODE_GEN_DIR)/decode/.rom_width_$(CPU_ROM_WIDTH)

# Spec inputs cpugen actually reads: the always-loaded base spec/*.toml, plus
# -- only when this variant has an overlay -- that overlay's own
# spec/<overlay>/*.toml subtree. A variant with no overlay (e.g. j2) must NOT
# depend on spec/sh4/*.toml: touching the sh4 spec would otherwise force a
# pointless j2 regeneration. We also depend on the cpugen Go sources
# themselves (cmd/cpugen + internal/), since a generator bug fix changes the
# output just as much as a spec edit does, and both are equally capable of
# leaving a stale decoder in place undetected.
CPU_DECODE_GEN_BASE_SPEC    := $(wildcard $(CPU_INC_DIR)decode/gen-go/spec/*.toml)
CPU_DECODE_GEN_OVERLAY_SPEC := $(if $(CPU_OVERLAY),$(wildcard $(CPU_INC_DIR)decode/gen-go/spec/$(CPU_OVERLAY)/*.toml))
CPU_DECODE_GEN_SRC          := $(shell find $(CPU_INC_DIR)decode/gen-go/cmd/cpugen \
                                 $(CPU_INC_DIR)decode/gen-go/internal -name '*.go')

# Grouped target (GNU Make 4.3+ "&:"): one recipe invocation produces all six
# files atomically. Without this, classic "targets: prereqs" syntax treats
# each of the six names as an independent rule sharing the recipe text, so
# `make -jN` can (and does) launch N concurrent, redundant `cpugen` runs all
# writing the same six files in the same directory -- wasteful, and a race
# that can leave DECODE_GEN_DIR partially populated. `go`'s own `-C`-based
# in-tree module cache builds are not safe to run N-way concurrently either.
$(CPU_DECODE_GENERATED) $(CPU_DECODE_ROM_WIDTH_STAMP) &: $(CPU_INC_DIR)variants.toml $(CPU_DECODE_GEN_BASE_SPEC) \
                            $(CPU_DECODE_GEN_OVERLAY_SPEC) $(CPU_DECODE_GEN_SRC)
	@command -v go >/dev/null 2>&1 || { \
	  echo "ERROR: go is required to generate the $(CPU_VARIANT) decoder." >&2; exit 1; }
	@mkdir -p $(DECODE_GEN_DIR)/decode
	go -C $(CPU_INC_DIR)decode/gen-go run ./cmd/cpugen -w $(CPU_ROM_WIDTH) \
	  $(if $(CPU_OVERLAY),-overlay spec/$(CPU_OVERLAY)) -illegal full \
	  -o $(abspath $(DECODE_GEN_DIR)/decode)
	@rm -f $(DECODE_GEN_DIR)/decode/.rom_width_*
	@touch $(CPU_DECODE_ROM_WIDTH_STAMP)

include $(CPU_INC_DIR)build_core.mk
