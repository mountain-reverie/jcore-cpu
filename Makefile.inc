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

CPU_INC_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
CPU_VARIANT ?= j2
TARGET_KIND ?= fpga
DECODE_GEN_DIR ?= $(CPU_INC_DIR)gen

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

include $(CPU_INC_DIR)build_core.mk
