# Shim: mk_utils.mk includes exactly one build file per directory by name, so
# this filename must survive. All content lives in Makefile.inc.
TARGET_KIND := fpga
include $(dir $(lastword $(MAKEFILE_LIST)))Makefile.inc

# Files not yet variant-partitioned (register file / decode-table architectures
# are selected by VHDL configuration, so all must be analyzed).
$(VHDLS) += core/register_file_flops.vhd
$(VHDLS) += core/register_file_two_bank.vhd
$(VHDLS) += core/register_file_ebr.vhd
$(VHDLS) += decode/decode_table_simple.vhd
$(VHDLS) += decode/decode_table_simple_config.vhd
$(VHDLS) += decode/decode_table_direct.vhd
$(VHDLS) += decode/decode_table_direct_config.vhd
$(VHDLS) += decode/decode_table_rom.vhd
$(VHDLS) += decode/decode_table_rom_config.vhd
