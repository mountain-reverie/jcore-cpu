$(VHDLS) += cpu2j0_pkg.vhd
$(VHDLS) += core/components_pkg.vhd
$(VHDLS) += core/cpu.vhd
$(VHDLS) += core/mult_pkg.vhd
$(VHDLS) += core/mult.vhd
$(VHDLS) += core/divider_pkg.vhd
$(VHDLS) += core/divider.vhd
$(VHDLS) += core/datapath_pkg.vhd
$(VHDLS) += core/shifter.vhd
$(VHDLS) += core/shifter_seq.vhd
$(VHDLS) += core/datapath.vhd
$(VHDLS) += core/register_file.vhd
# core/tlb.vhd itself is variant-gated (added via variants.toml extra_files,
# only for CPU_VARIANT=j4; see sim/gen/*/variants.mk), but tlb_walk depends
# only on datapath_pack/cpu2j0_pack and is not yet instantiated anywhere, so
# it is analyzed unconditionally here alongside the other base core files.
$(VHDLS) += core/tlb_walk.vhd

# Relative to $(CPU_INC_DIR) when CPU_DECODE_GENERATED actually lives under it
# (the default, $(CPU_INC_DIR)gen/$(CPU_VARIANT)/decode/...), so that mk_utils.mk
# consumers (jcore-soc's Makefile, via include_vhdl_var's `$(addprefix $(1)/,...)`
# where $(1)=components/cpu) get a SINGLY-prefixed path instead of
# components/cpu/components/cpu/gen/... To find that bug: jcore-soc's Makefile
# scans this directory by `include components/cpu/build.mk` and re-prefixes
# every entry with "components/cpu/" itself -- entries already rooted at
# $(CPU_INC_DIR) (== "components/cpu/" in that context) would otherwise be
# prefixed twice. $(patsubst) is a no-op (leaves the path untouched) whenever
# CPU_DECODE_GENERATED does NOT start with $(CPU_INC_DIR) -- which is exactly
# what happens for the OTHER consumer, sim/Makefile, which overrides
# DECODE_GEN_DIR to an absolute path ($(CURDIR)/gen) before including this
# file; CPU_INC_DIR there is "../", which is not a prefix of an absolute path,
# so this patsubst leaves those entries alone and sim/Makefile's own
# DECODE_GEN_DIR-based filter (see sim/Makefile's own comment above CPU_VHDS)
# keeps working unmodified.
$(VHDLS) += $(patsubst $(CPU_INC_DIR)%,%,$(CPU_DECODE_GENERATED))
$(VHDLS) += decode/decode_table.vhd
$(VHDLS) += decode/decode_core.vhd

$(VHDLS) += $(CPU_EXTRA_FILES)
# core/cpu_config_common.vhd holds the decode-binding configurations shared by
# every variant (cpu_decode_direct_fpga/_rom_fpga, cpu_decode_direct_mmu,
# _sh2a, _mmu_sh2a) plus the `use work.decode_pack.all;` clause that precedes
# cpu_decode_direct_mmu. It must be analyzed BEFORE $(CPU_CONFIG_FILE) because
# the per-variant files (cpu_config_j2a.vhd's cpu_j2a, cpu_config_sim.vhd's
# cpu_sim/_sh2a/_dsp_alu) bind these configurations by name.
$(VHDLS) += core/cpu_config_common.vhd
$(VHDLS) += $(CPU_CONFIG_FILE)

# Register-file architectures and decode-table configs are selected by VHDL
# CONFIGURATION declarations in $(CPU_CONFIG_FILE) (e.g. cpu_config.vhd's
# `configuration cpu_sim` binds register_file(two_bank); other configs bind
# register_file(ebr)), so all of them must be analyzed for every variant
# (variants.toml: "every configuration except cpu_j1 binds
# register_file_two_bank"). They are therefore variant-independent -- part
# of the shared base list, not any variant's extra_files -- and must be
# analyzed AFTER $(CPU_CONFIG_FILE) (matches pre-refactor ghdl -i order).
$(VHDLS) += core/register_file_flops.vhd
$(VHDLS) += core/register_file_two_bank.vhd
$(VHDLS) += core/register_file_ebr.vhd
$(VHDLS) += decode/decode_table_simple_config.vhd
$(VHDLS) += decode/decode_table_direct_config.vhd
$(VHDLS) += decode/decode_table_rom_config.vhd
