-- Synth-local copy of cpu_decode_direct_sh2a (defined in core/cpu_config.vhd,
-- which is NOT in the synth FILES list to keep the byte-identical committed
-- configs untouched). Mirrors the base cpu_decode_direct config in
-- decode/decode_table_direct_config.vhd but adds SH2A_ARCH => true, which binds
-- decode_core(arch) with its SH-2A control hardware (ext_word register,
-- movml/movmu FSM) ENABLED. Without this, the J2A synth would compile the
-- SH-2A decode tables but leave decode_core's SH-2A logic gated off.
configuration cpu_decode_direct_sh2a of decode is
  for arch
    for core : decode_core
      use entity work.decode_core(arch)
generic map (
  decode_type => DIRECT,
  reset_vector => DEC_CORE_RESET,
  sh2a_arch => true
);
    end for;
    for table : decode_table
      use entity work.decode_table(direct_logic);
    end for;
  end for;
end configuration;

-- J2A synth: J2 baseline core + the SH-2A overlay decoder tables (generated
-- transiently into decode/ by `make -C decode generate-j2a`) with decode_core's
-- SH-2A logic ENABLED via the synth-local cpu_decode_direct_sh2a config above,
-- and SH2A_ARCH=>true on the cpu/datapath side. Identical to cpu_synth_direct
-- (synth/cpu_synth_config.vhd) except for the SH-2A decode binding. The
-- SH2A_ARCH cpu generic (datapath side) is injected by the wrapper below / by
-- the timing+cache harness configs.
configuration cpu_synth_j2a of cpu is
  for stru
    for u_mult : mult use entity work.mult(stru); end for;
    -- The SH-2A divider (u_div) lives in the g_div : if SH2A_ARCH generate; bind
    -- its component to the entity so synth_ecp5 elaborates it into LUTs rather
    -- than leaving a black-box `divider` cell that nextpnr rejects.
    for g_div
      for u_div : divider use entity work.divider(rtl); end for;
    end for;
    for u_decode : decode use configuration work.cpu_decode_direct_sh2a; end for;
    for u_datapath : datapath use entity work.datapath(stru);
      for stru
        for u_regfile : register_file use entity work.register_file(two_bank); end for;
        for u_shifter : shifter use entity work.shifter(comb); end for;
      end for;
    end for;
  end for;
end configuration;

-- Thin pass-through top for the bare-cpu asic/ecp5 AREA backends: the yosys-ghdl
-- plugin has no -g flag, so SH2A_ARCH=>true is set via a configuration generic
-- map, which needs a component-instantiation context. cpu_j2a_top provides it;
-- cpu_synth_j2a_sh2a binds u_cpu to cpu_synth_j2a generic map(SH2A_ARCH=>true).
-- Exactly mirrors cpu_j4_priv_top / cpu_synth_j4_priv in cpu_synth_j4_config.vhd.

library ieee;
  use ieee.std_logic_1164.all;
  use work.cpu2j0_pack.all;

entity cpu_j2a_top is
  port (
    clk     : in    std_logic;
    rst     : in    std_logic;
    db_o    : out   cpu_data_o_t;
    db_lock : out   std_logic;
    db_i    : in    cpu_data_i_t;
    inst_o  : out   cpu_instruction_o_t;
    inst_i  : in    cpu_instruction_i_t;
    debug_o : out   cpu_debug_o_t;
    debug_i : in    cpu_debug_i_t;
    event_o : out   cpu_event_o_t;
    event_i : in    cpu_event_i_t;
    cop_o   : out   cop_o_t;
    cop_i   : in    cop_i_t;
    priv_o  : out   cpu_priv_o_t
  );
end entity cpu_j2a_top;

architecture stru of cpu_j2a_top is

  component cpu is
    generic (
      copro_decode : boolean := true;
      priv_arch    : boolean := false;
      mmu_arch     : boolean := false;
      sh2a_arch    : boolean := false
    );
    port (
      clk     : in    std_logic;
      rst     : in    std_logic;
      db_o    : out   cpu_data_o_t;
      db_lock : out   std_logic;
      db_i    : in    cpu_data_i_t;
      inst_o  : out   cpu_instruction_o_t;
      inst_i  : in    cpu_instruction_i_t;
      debug_o : out   cpu_debug_o_t;
      debug_i : in    cpu_debug_i_t;
      event_o : out   cpu_event_o_t;
      event_i : in    cpu_event_i_t;
      cop_o   : out   cop_o_t;
      cop_i   : in    cop_i_t;
      priv_o  : out   cpu_priv_o_t
    );
  end component cpu;

begin

  u_cpu : component cpu
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
      priv_o  => priv_o
    );

end architecture stru;

configuration cpu_synth_j2a_sh2a of cpu_j2a_top is
  for stru
    for u_cpu : cpu
      use configuration work.cpu_synth_j2a
generic map (
  sh2a_arch => true
);
    end for;
  end for;
end configuration cpu_synth_j2a_sh2a;
