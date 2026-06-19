-- J4 synth placeholder == J2.
-- Identical to cpu_synth_direct (synth/cpu_synth_config.vhd) with u_mult
-- bound to mult(stru) (the 31x16 array multiplier).  SH-4 privilege/TLB/L2
-- units will hook in here once the J4 overlay is non-empty.
configuration cpu_synth_j4 of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(stru);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_direct;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru);
      for stru
        for u_regfile : register_file
          use entity work.register_file(two_bank);
        end for;
        for u_shifter : shifter
          use entity work.shifter(comb);
        end for;
      end for;
    end for;
  end for;
end configuration;

-- M0: thin pass-through top for the J4 asic/ecp5 area backends with
-- PRIV_ARCH=true.  The yosys ghdl plugin does not support the ghdl -g generic
-- override flag, so PRIV_ARCH cannot be set at elaboration time via the shell.
-- The only mechanism that works through the plugin is a VHDL configuration
-- binding with generic map, which requires a component instantiation context.
-- This entity provides that context; cpu_synth_j4_priv binds u_cpu to
-- cpu_synth_j4 with generic map(PRIV_ARCH => true), giving a synthesisable
-- top where cpu elaborates with the full SH-4 privileged datapath active.
-- cpu_synth.sh uses this as TOP + CPUTOP=cpu_j4_priv_top for j4/j4c asic/ecp5.
library ieee;
use ieee.std_logic_1164.all;
use work.cpu2j0_pack.all;

entity cpu_j4_priv_top is
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    db_o    : out cpu_data_o_t;
    db_lock : out std_logic;
    db_i    : in  cpu_data_i_t;
    inst_o  : out cpu_instruction_o_t;
    inst_i  : in  cpu_instruction_i_t;
    debug_o : out cpu_debug_o_t;
    debug_i : in  cpu_debug_i_t;
    event_o : out cpu_event_o_t;
    event_i : in  cpu_event_i_t;
    cop_o   : out cop_o_t;
    cop_i   : in  cop_i_t;
    priv_o  : out cpu_priv_o_t);
end entity cpu_j4_priv_top;

architecture stru of cpu_j4_priv_top is
  component cpu is
    generic (
      COPRO_DECODE : boolean := true;
      PRIV_ARCH    : boolean := false);
    port (
      clk     : in  std_logic;
      rst     : in  std_logic;
      db_o    : out cpu_data_o_t;
      db_lock : out std_logic;
      db_i    : in  cpu_data_i_t;
      inst_o  : out cpu_instruction_o_t;
      inst_i  : in  cpu_instruction_i_t;
      debug_o : out cpu_debug_o_t;
      debug_i : in  cpu_debug_i_t;
      event_o : out cpu_event_o_t;
      event_i : in  cpu_event_i_t;
      cop_o   : out cop_o_t;
      cop_i   : in  cop_i_t;
      priv_o  : out cpu_priv_o_t);
  end component cpu;
begin
  u_cpu : cpu
    port map (
      clk     => clk,
      rst     => rst,
      db_o    => db_o,
      db_lock => db_lock,
      db_i    => db_i,
      inst_o  => inst_o,
      inst_i  => inst_i,
      debug_o => debug_o,
      debug_i => debug_i,
      event_o => event_o,
      event_i => event_i,
      cop_o   => cop_o,
      cop_i   => cop_i,
      priv_o  => priv_o);
end architecture stru;

configuration cpu_synth_j4_priv of cpu_j4_priv_top is
  for stru
    for u_cpu : cpu
      use configuration work.cpu_synth_j4
        generic map (PRIV_ARCH => true);
    end for;
  end for;
end configuration cpu_synth_j4_priv;
