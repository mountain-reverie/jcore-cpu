# Shim: mk_utils.mk includes exactly one build file per directory by name, so
# this filename must survive. All content lives in Makefile.inc.
#
# The register-file / decode-table-config files that used to be hand-listed
# here (variant-independent, "not yet variant-partitioned") now live in
# build_core.mk itself, appended after $(CPU_CONFIG_FILE) -- so every
# includer of Makefile.inc (this file, sim/Makefile, etc.) gets them via the
# one shared list instead of each includer needing its own copy.
TARGET_KIND := fpga
include $(dir $(lastword $(MAKEFILE_LIST)))Makefile.inc
