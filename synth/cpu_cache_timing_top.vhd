-- Synthesis-only timing harness for the cpu + L1 I/D caches.
--
-- Like cpu_timing_top, but it instantiates the cpu AND the icache/dcache
-- adapters (which contain the caches + inferred RAMs), so the reported area/Fmax
-- cover the full cpu+cache. The boundary is collapsed to a few real IO via a
-- registered scramble word: every harness-driven input comes from `acc` and
-- every output is folded back into `acc`, so nothing is constant-folded and the
-- whole cpu+cache is preserved. It is NOT a functional model.
--
-- Clocking: the cpu and the cache cpu-side run on clk125; the cache mem-side
-- runs on clk200. SAME_CLOCK (true on FPGA, false on ASIC) selects the cache's
-- single-clock vs dual-clock CDC form; for SAME_CLOCK=true the caller ties
-- clk125 = clk200. The core + adapter instances are bound by an EXTERNAL
-- per-variant configuration (synth/cpu_cache_timing_config.vhd:
-- cpu_cache_timing_j2/j4); cpu_synth.sh elaborates that, never this entity.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_pack.all;
use work.data_bus_pack.all;
use work.cache_pack.all;

entity cpu_cache_timing_top is
  -- No generic: the cache CDC form comes from the cache_clkmode package the
  -- build analyzes (sc/dc), so ghdl bakes the constant and yosys sees no params.
  port ( clk125 : in  std_logic;   -- cpu + cache cpu-side clock
         clk200 : in  std_logic;   -- cache mem-side clock (= clk125 if single-clock)
         rst    : in  std_logic;
         ti     : in  std_logic;    -- serial entropy in (keeps inputs non-constant)
         sout   : out std_logic );  -- serial reduction out (keeps outputs observed)
end entity;

architecture timing of cpu_cache_timing_top is
  function pad32(v : std_logic_vector) return std_logic_vector is
    variable vv : std_logic_vector(v'length-1 downto 0) := v;
    variable r  : std_logic_vector(31 downto 0) := (others => '0');
  begin
    r(vv'high downto 0) := vv;
    return r;
  end function;

  signal acc : std_logic_vector(31 downto 0);

  -- cpu <-> cache buses
  signal db_o    : cpu_data_o_t;          -- cpu data out -> dcache
  signal db_lock : std_logic;
  signal db_i    : cpu_data_i_t;          -- dcache -> cpu data in
  signal inst_o  : cpu_instruction_o_t;   -- cpu instr out -> icache
  signal inst_i  : cpu_instruction_i_t;   -- icache -> cpu instr in

  -- other cpu IO (harness-driven, like cpu_timing_top)
  signal debug_o : cpu_debug_o_t;
  signal event_o : cpu_event_o_t;
  signal cop_o   : cop_o_t;
  signal debug_i : cpu_debug_i_t;
  signal event_i : cpu_event_i_t;
  signal cop_i   : cop_i_t;

  -- cache DDR-side (folded into acc / driven from acc)
  signal ic_ddr_o, dc_ddr_o : cpu_data_o_t;
  signal ic_ddr_i, dc_ddr_i : cpu_data_i_t;
  signal ic_burst, dc_burst, dc_dbus_lock : std_logic;
  signal ic_ctrl, dc_ctrl : cache_ctrl_t;
  signal dc_snpc_o : dcache_snoop_io_t;
begin
  -- harness-driven cpu inputs (debug/event/cop) -- same scheme as cpu_timing_top
  debug_i.en   <= acc(2);
  debug_i.cmd  <= cpu_debug_cmd_t'val(to_integer(unsigned(acc(4 downto 3))));
  debug_i.ir   <= acc(15 downto 0);
  debug_i.d    <= acc;
  debug_i.d_en <= acc(5);
  event_i.en   <= acc(6);
  event_i.cmd  <= cpu_event_cmd_t'val(to_integer(unsigned(acc(8 downto 7))));
  event_i.vec  <= acc(7 downto 0);
  event_i.msk  <= acc(9);
  event_i.lvl  <= acc(13 downto 10);
  cop_i.d   <= acc;
  cop_i.ack <= acc(14);
  cop_i.t   <= acc(15);
  cop_i.exc <= acc(16);

  -- cache control + DDR-side inputs from acc (kept non-constant)
  ic_ctrl.en <= acc(17); ic_ctrl.inv <= acc(18);
  dc_ctrl.en <= acc(19); dc_ctrl.inv <= acc(20);
  ic_ddr_i.d <= acc; ic_ddr_i.ack <= acc(21);
  dc_ddr_i.d <= acc; dc_ddr_i.ack <= acc(22);

  u_cpu : cpu
    port map ( clk => clk125, rst => rst,
               db_o => db_o, db_lock => db_lock, db_i => db_i,
               inst_o => inst_o, inst_i => inst_i,
               debug_o => debug_o, debug_i => debug_i,
               event_o => event_o, event_i => event_i,
               cop_o => cop_o, cop_i => cop_i );

  u_icache : icache_adapter
   
    port map ( clk125 => clk125, clk200 => clk200, rst => rst,
               ctrl => ic_ctrl,
               ibus_o => inst_o, ibus_i => inst_i,
               dbus_o => ic_ddr_o, dbus_ddrburst => ic_burst,
               dbus_i => ic_ddr_i, dbus_ack_r => acc(23) );

  u_dcache : dcache_adapter
   
    port map ( clk125 => clk125, clk200 => clk200, rst => rst,
               ctrl => dc_ctrl,
               ibus_o => db_o, lock => db_lock, ibus_i => db_i,
               snpc_o => dc_snpc_o, snpc_i => NULL_SNOOP_IO,
               dbus_o => dc_ddr_o, dbus_lock => dc_dbus_lock,
               dbus_ddrburst => dc_burst,
               dbus_i => dc_ddr_i, dbus_ack_r => acc(24) );

  -- Fold cpu non-cache outputs + the cache DDR-side outputs into acc each clk125
  -- cycle (every bit influences acc, so cpu + both caches are preserved).
  process(clk125) begin
    if rising_edge(clk125) then
      if rst = '1' then
        acc <= (others => '0');
      else
        acc <= (acc(30 downto 0) & ti)
             xor debug_o.d xor cop_o.d
             xor ic_ddr_o.a xor ic_ddr_o.d xor dc_ddr_o.a xor dc_ddr_o.d
             xor pad32(event_o.lvl)
             xor pad32(cop_o.rna) xor pad32(cop_o.rnb) xor pad32(cop_o.op)
             xor pad32(ic_ddr_o.we) xor pad32(dc_ddr_o.we)
             xor pad32(dc_snpc_o.al)
             xor pad32(ic_ddr_o.en & ic_ddr_o.rd & ic_ddr_o.wr & ic_burst
                       & dc_ddr_o.en & dc_ddr_o.rd & dc_ddr_o.wr & dc_burst
                       & dc_dbus_lock & dc_snpc_o.en
                       & debug_o.ack & debug_o.rdy
                       & event_o.ack & event_o.slp & event_o.dbg
                       & cop_o.en & cop_o.stallcp);
      end if;
    end if;
  end process;

  sout <= acc(31);
end architecture;
