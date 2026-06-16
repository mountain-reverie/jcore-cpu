default: all

####################################################################
# To add tests, modify the following section
####################################################################

# Add VHDL test benches entity names 

VHDL_TESTS := register_tap
VHDL_TESTS += register_ebr_tap
VHDL_TESTS += mult_tap
VHDL_TESTS += mult_seq_tap
VHDL_TESTS += divider_tap
VHDL_TESTS += bshift_tap
VHDL_TESTS += shifter_tap
VHDL_TESTS += shifter_seq_tap
VHDL_TESTS += arith_tap
VHDL_TESTS += logic_tap
VHDL_TESTS += manip_tap

# Add VHDL files used by the test benches

VHDS := register_tap.vhd
VHDS += register_ebr_tap.vhd
VHDS += mult_tap.vhd
VHDS += mult_seq_tap.vhd
VHDS += divider_tap.vhd
VHDS += bshift_tap.vhd
VHDS += shifter_tap.vhd
VHDS += shifter_seq_tap.vhd
VHDS += arith_tap.vhd
VHDS += logic_tap.vhd
VHDS += manip_tap.vhd


####################################################################
# Nothing below this line should need to change when you add tests
####################################################################

TOOLS_DIR := $(firstword $(wildcard ../../mcu_lib/tools) $(wildcard ../../../tools))
RUNTESTS := $(TOOLS_DIR)/tests/runtests

VHDLS := CPU_VHDS
include ../build.mk

VHDS += $(addprefix ../, $(CPU_VHDS))
# Analyse mult(seq) AFTER core mult(stru) so that 'stru' stays the default
# architecture of entity 'mult' for the component-instantiated mult_tap
# testbench.  mult_seq_tap uses a direct entity instantiation of mult(seq),
# so it is unaffected by default-binding order either way.
VHDS += ../core/mult_seq.vhd
# register_file(two_bank) -- the ebr cross-check oracle -- already arrives via
# build.mk (CPU_VHDS); ebr is added explicitly until Task 4 moves it there.
VHDS += ../core/register_file_ebr.vhd
VHDS += $(TOOLS_DIR)/tests/tap/test_pkg.vhd

VHDL_TOPS := $(VHDL_TESTS)

all: TESTS $(VHDL_TESTS)

$(RUNTESTS):
	make -C $(TOOLS_DIR)/tests

check: all $(RUNTESTS)
	$(RUNTESTS) TESTS 

tap: all $(RUNTESTS)
	$(RUNTESTS) -t TESTS

work-obj93.cf: $(VHDS)

include $(TOOLS_DIR)/ghdl.mk

clean:
	rm -f *.o *.d *.tap *.t *.cf
	rm -f $(VHDL_TOPS)

.PHONY: default clean all
