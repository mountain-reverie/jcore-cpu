library work;

library ieee;
  use ieee.std_logic_1164.all;
  use std.textio.all;
  use ieee.std_logic_textio.all;
  use work.bridge_pkg.all;
  use work.cpu2j0_pack.all;
  use work.monitor_pkg.all;
  use work.data_bus_pkg.all;
  use work.cache_pack.all;

#include "cpu_signals.h"

entity cpu_dualcore_tb is
end entity cpu_dualcore_tb;

architecture behaviour of cpu_dualcore_tb is

  -- local instruction-bridge array types (mirror cpu_cache_tb); kept idle here,
  -- since instruction fetch is merged onto the DEV_SRAM data master. The signal
  -- names are still referenced by cpu_signals.h, so they must exist.

  type instrd_bus_i_t is array(instr_bus_device_t'left to instr_bus_device_t'right) of cpu_data_i_t;

  type instrd_bus_o_t is array(instr_bus_device_t'left to instr_bus_device_t'right) of cpu_data_o_t;

  constant cpuid_addr : std_logic_vector(31 downto 0) := x"ABCD0600";

  signal clk : std_logic := '1';
  signal rst : std_logic := '1';
  -- vsg_off constant_013
  -- CLK_PERIOD is a C-preprocessor macro (sim/cpu_signals.h) substituted by
  -- gcc -E before ghdl analysis, NOT a reference to the clk_period constant;
  -- vsg's constant_013 must not lowercase it (would break macro substitution).
  constant clk_period : time := CLK_PERIOD ns;
  -- vsg_on constant_013

  -- per-cpu raw buses
  signal cpu0_db_o,    cpu1_db_o    : cpu_data_o_t;
  signal cpu0_db_i,    cpu1_db_i    : cpu_data_i_t;
  signal cpu0_db_lock, cpu1_db_lock : std_logic;
  signal cpu0_inst_o,  cpu1_inst_o  : cpu_instruction_o_t;
  signal cpu0_inst_i,  cpu1_inst_i  : cpu_instruction_i_t;
  signal cpu0_mmu,     cpu1_mmu     : cpu_mmu_o_t;
  signal cpu0_a_mmu,   cpu1_a_mmu   : mmu_cache_i_t;

  -- cpuid-intercepted cpu->cache data buses
  signal c0_db_o,      c1_db_o : cpu_data_o_t;
  signal c0_db_i,      c1_db_i : cpu_data_i_t;

  -- cache mem-side (plain cpu_data buses) for the 4 masters
  signal d0_o : cpu_data_o_t;
  signal d1_o : cpu_data_o_t;
  signal i0_o : cpu_data_o_t;
  signal i1_o : cpu_data_o_t;
  signal d0_i : cpu_data_i_t;
  signal d1_i : cpu_data_i_t;
  signal i0_i : cpu_data_i_t;
  signal i1_i : cpu_data_i_t;

  -- cascade intermediates + final memory master
  signal ab_o  : cpu_data_o_t;
  signal cd_o  : cpu_data_o_t;
  signal mem_o : cpu_data_o_t;   -- ab=merge(d0,i0), cd=merge(d1,i1)
  signal ab_i  : cpu_data_i_t;
  signal cd_i  : cpu_data_i_t;
  signal mem_i : cpu_data_i_t;

  -- snoop cross-wire
  signal snp0,         snp1 : dcache_snoop_io_t;

  -- misc cpu interface tie-offs (mirror cpu_cache_tb defaults)
  signal debug_i     : cpu_debug_i_t                := (
                                                        en => '0',
                                                        cmd => BREAK,
                                                        ir => (others => '0'),
                                                        d => (others => '0'),
                                                        d_en => '0'
                                                       );
  signal debug_i_cmd : std_logic_vector(1 downto 0) := "00";
  signal debug_o     : cpu_debug_o_t;
  signal debug1_o    : cpu_debug_o_t;

  signal event_req_i  : std_logic_vector(2 downto 0)  := (others => '1');
  signal event_ack_o  : std_logic;
  signal event_info_i : std_logic_vector(11 downto 0) := (others => '0');

  signal event_i                : cpu_event_i_t;
  signal event0_o,     event1_o : cpu_event_o_t;
  signal copro_i                : cop_i_t;
  signal copro0_o,     copro1_o : cop_o_t;

  constant cctrl : work.data_bus_pack.cache_ctrl_t := (en => '1', inv => '0');

  -- the single memory bus presented to the C bridge
  signal data_master_o : cpu_data_o_t;
  signal data_master_i : cpu_data_i_t := ((others => 'Z'), '0');
  signal data_slaves_i : data_bus_i_t;
  signal data_slaves_o : data_bus_o_t;
  signal data_select   : data_bus_device_t;

  signal pio_data_o : cpu_data_o_t := NULL_DATA_O;
  signal pio_data_i : cpu_data_i_t := (ack => '0', d => (others => '0'));

  -- idle instruction bridge signals (names required by cpu_signals.h)
  signal instrd_slaves_i : instrd_bus_i_t;
  signal instrd_slaves_o : instrd_bus_o_t;

  signal dummy : bit;

begin

  rst <= '1', '0' after 10 ns;
  clk <= '0' after clk_period / 2 when clk = '1' else
         '1' after clk_period / 2;

  -- Idle the (unused) instruction bridge: instruction fetch is merged onto the
  -- DEV_SRAM data master, so these ports never assert. Keep en low so the C
  -- model never services them.
  instrd_slaves_o(DEV_SRAM) <= NULL_DATA_O;
  instrd_slaves_o(DEV_DDR)  <= NULL_DATA_O;

  -- FIXME: Old CPU interface wrapper (shared by both cores)
  event_i.en  <= '0' when event_req_i = "111" else
                 '1';
  event_i.cmd <= INTERRUPT when event_req_i = "000" else
                 INTERRUPT when event_req_i = "001" else
                 ERROR when event_req_i = "010" else
                 ERROR when event_req_i = "011" else
                 BREAK when event_req_i = "100" else
                 RESET_CPU;
  event_i.msk <= '0' when event_req_i = "000" else
                 '1';
  event_i.lvl <= event_info_i(11 downto 8);
  event_i.vec <= event_info_i( 7 downto 0);
  event_ack_o <= event0_o.ack;

  with debug_i_cmd select debug_i.cmd <=
    BREAK when "00",
    STEP when "01",
    INSERT when "10",
    CONTINUE when others;

  ----- CPU0 -----
  cpu0 : configuration work.cpu_sim
    port map (
      clk     => clk,
      rst     => rst,
      db_o    => cpu0_db_o,
      db_lock => cpu0_db_lock,
      db_i    => cpu0_db_i,
      inst_o  => cpu0_inst_o,
      inst_i  => cpu0_inst_i,
      debug_o => debug_o,
      debug_i => debug_i,
      event_i => event_i,
      event_o => event0_o,
      cop_o   => copro0_o,
      cop_i   => copro_i,
      mmu_o   => cpu0_mmu
    );

  ----- CPU1 -----
  cpu1 : configuration work.cpu_sim
    port map (
      clk     => clk,
      rst     => rst,
      db_o    => cpu1_db_o,
      db_lock => cpu1_db_lock,
      db_i    => cpu1_db_i,
      inst_o  => cpu1_inst_o,
      inst_i  => cpu1_inst_i,
      debug_o => debug1_o,
      debug_i => debug_i,
      event_i => event_i,
      event_o => event1_o,
      cop_o   => copro1_o,
      cop_i   => copro_i,
      mmu_o   => cpu1_mmu
    );

  -- cpuid intercept: reads of CPUID_ADDR return the core id, bypassing the cache.
  -- id=0 for cpu0, id=1 for cpu1. Combinational immediate ack.
  -- CPU0
  process (cpu0_db_o, c0_db_i) is
  begin

    if (cpu0_db_o.en = '1' and cpu0_db_o.rd = '1' and cpu0_db_o.a = cpuid_addr) then
      c0_db_o   <= NULL_DATA_O;                 -- hide from cache
      cpu0_db_i <= (d => x"00000000", ack => '1');
    else
      c0_db_o   <= cpu0_db_o;
      cpu0_db_i <= c0_db_i;
    end if;

  end process;

  -- CPU1
  process (cpu1_db_o, c1_db_i) is
  begin

    if (cpu1_db_o.en = '1' and cpu1_db_o.rd = '1' and cpu1_db_o.a = cpuid_addr) then
      c1_db_o   <= NULL_DATA_O;
      cpu1_db_i <= (d => x"00000001", ack => '1');
    else
      c1_db_o   <= cpu1_db_o;
      cpu1_db_i <= c1_db_i;
    end if;

  end process;

  -- per-cpu d-side MMU cacheability inputs (mirror cpu_cache_tb.vhd:232)
  cpu0_a_mmu <= (pa_tag => cpu0_mmu.d_pa_tag, at => cpu0_mmu.d_at, c => cpu0_mmu.d_c);
  cpu1_a_mmu <= (pa_tag => cpu1_mmu.d_pa_tag, at => cpu1_mmu.d_at, c => cpu1_mmu.d_c);

  -- D-caches (snoop cross-wired) + I-caches per cpu. The snoop-preserving
  -- cacheable mux routes uncached (MMIO) accesses straight to the bus with the
  -- full 32-bit address, fixing the LED/MMIO path, while keeping snoop coherency.
  u_dc0 : entity work.dcache_snoop_cacheable_mux
    port map (
      clk125       => clk,
      clk200       => clk,
      rst          => rst,
      ctrl         => cctrl,
      cpu_o        => c0_db_o,
      a_mmu        => cpu0_a_mmu,
      lock         => cpu0_db_lock,
      cpu_i        => c0_db_i,
      snpc_o       => snp0,
      snpc_i       => snp1,
      mem_o        => d0_o,
      mem_lock     => open,
      mem_ddrburst => open,
      mem_i        => d0_i,
      mem_ack_r    => d0_i.ack
    );

  u_dc1 : entity work.dcache_snoop_cacheable_mux
    port map (
      clk125       => clk,
      clk200       => clk,
      rst          => rst,
      ctrl         => cctrl,
      cpu_o        => c1_db_o,
      a_mmu        => cpu1_a_mmu,
      lock         => cpu1_db_lock,
      cpu_i        => c1_db_i,
      snpc_o       => snp1,
      snpc_i       => snp0,
      mem_o        => d1_o,
      mem_lock     => open,
      mem_ddrburst => open,
      mem_i        => d1_i,
      mem_ack_r    => d1_i.ack
    );

  u_ic0 : entity work.icache_adapter
    port map (
      clk125        => clk,
      clk200        => clk,
      rst           => rst,
      ctrl          => cctrl,
      ibus_o        => cpu0_inst_o,
      ibus_i        => cpu0_inst_i,
      dbus_o        => i0_o,
      dbus_ddrburst => open,
      dbus_i        => i0_i,
      dbus_ack_r    => i0_i.ack
    );

  u_ic1 : entity work.icache_adapter
    port map (
      clk125        => clk,
      clk200        => clk,
      rst           => rst,
      ctrl          => cctrl,
      ibus_o        => cpu1_inst_o,
      ibus_i        => cpu1_inst_i,
      dbus_o        => i1_o,
      dbus_ddrburst => open,
      dbus_i        => i1_i,
      dbus_ack_r    => i1_i.ack
    );

  -- 4:1 merge via cascaded 2-master muxes:
  --   ab=merge(d0,i0), cd=merge(d1,i1), mem=merge(ab,cd)
  m_ab : entity work.multi_master_bus_mux
    port map (
      rst     => rst,
      clk     => clk,
      m1_i    => d0_i,
      m1_o    => d0_o,
      m2_i    => i0_i,
      m2_o    => i0_o,
      slave_i => ab_i,
      slave_o => ab_o
    );

  m_cd : entity work.multi_master_bus_mux
    port map (
      rst     => rst,
      clk     => clk,
      m1_i    => d1_i,
      m1_o    => d1_o,
      m2_i    => i1_i,
      m2_o    => i1_o,
      slave_i => cd_i,
      slave_o => cd_o
    );

  m_top : entity work.multi_master_bus_mux
    port map (
      rst     => rst,
      clk     => clk,
      m1_i    => ab_i,
      m1_o    => ab_o,
      m2_i    => cd_i,
      m2_o    => cd_o,
      slave_i => mem_i,
      slave_o => mem_o
    );

  data_master_o <= mem_o;
  mem_i         <= data_master_i;

  -- memory bridge: identical to cpu_cache_tb device decode + data_buses + C signals
  process (data_master_o) is

    variable dev : data_bus_device_t;

  begin

    if (data_master_o.en = '0') then
      dev := DEV_NONE;
    else
      dev := decode_data_address(data_master_o.a);
      if (dev = DEV_NONE) then
        dev := DEV_SRAM;
      end if;
    end if;

    data_select <= dev;

  end process;

  data_buses(master_i => data_master_i, master_o => data_master_o,
             selected => data_select,
             slaves_i => data_slaves_i, slaves_o => data_slaves_o);

  data_slaves_i(DEV_NONE) <= loopback_bus(data_slaves_o(DEV_NONE));
  data_slaves_i(DEV_SPI)  <= loopback_bus(data_slaves_o(DEV_SPI));

  pio_data_o             <= data_slaves_o(DEV_PIO);
  data_slaves_i(DEV_PIO) <= pio_data_i;

#include "sim_macros.h"

end architecture behaviour;
