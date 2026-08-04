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

$(VHDLS) += $(CPU_DECODE_GENERATED)
$(VHDLS) += decode/decode_table.vhd
$(VHDLS) += decode/decode_core.vhd

$(VHDLS) += $(CPU_EXTRA_FILES)
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
