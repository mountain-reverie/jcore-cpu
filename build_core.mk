# DECODE_DIR selects the decoder source directory: the default `decode` is the
# J2/J4 baseline; a J1 sim/synth build sets DECODE_DIR=decode/j1 to consume the
# subset decoder. decode_core.vhd is shared (not regenerated per variant) and
# always comes from decode/.
DECODE_DIR ?= decode

$(VHDLS) += cpu2j0_pkg.vhd
$(VHDLS) += core/components_pkg.vhd
$(VHDLS) += core/cpu.vhd
$(VHDLS) += core/mult_pkg.vhd
$(VHDLS) += core/mult.vhd
$(VHDLS) += core/mult_seq.vhd
$(VHDLS) += core/datapath_pkg.vhd
$(VHDLS) += core/shifter.vhd
$(VHDLS) += core/shifter_seq.vhd
$(VHDLS) += core/datapath.vhd
$(VHDLS) += core/register_file.vhd

$(VHDLS) += $(DECODE_DIR)/decode_pkg.vhd
$(VHDLS) += $(DECODE_DIR)/decode.vhd
$(VHDLS) += $(DECODE_DIR)/decode_body.vhd
$(VHDLS) += decode/decode_table.vhd
$(VHDLS) += decode/decode_core.vhd
