library ieee;
  use ieee.std_logic_1164.all;
  use work.cpu2j0_pack.all;
  use work.data_bus_pack.all;
  use work.cache_pack.all;

-- Routes CPU data accesses by SH cacheability: cacheable -> write-back D-cache,
-- uncached (MMIO/control) -> direct bypass to the memory bus. The cacheable
-- decision is combinational on the (stable-for-the-whole-access) CPU address.
-- Snoop-preserving variant: the cache snoop port is exposed so multiple caches
-- can be cross-wired for coherency.

entity dcache_snoop_cacheable_mux is
  port (
    clk125 : in    std_logic;
    clk200 : in    std_logic;
    rst    : in    std_logic;
    ctrl   : in    cache_ctrl_t;
    -- CPU side
    cpu_o : in    cpu_data_o_t;  -- from cpu.db_o
    a_mmu : in    mmu_cache_i_t; -- from cpu.mmu_o (d_pa_tag/d_at)
    lock  : in    std_logic;     -- from cpu.db_lock
    cpu_i : out   cpu_data_i_t;  -- to cpu.db_i
    -- snoop port
    snpc_o : out   dcache_snoop_io_t;
    snpc_i : in    dcache_snoop_io_t;
    -- memory side
    mem_o        : out   cpu_data_o_t; -- to bus fabric master
    mem_lock     : out   std_logic;
    mem_ddrburst : out   std_logic;
    mem_i        : in    cpu_data_i_t; -- from bus fabric
    mem_ack_r    : in    std_logic
  );
end entity dcache_snoop_cacheable_mux;

architecture arch of dcache_snoop_cacheable_mux is

  signal cacheable : boolean;
  -- cache (dcache_adapter) CPU-side and memory-side nets
  signal c_cpu_o    : cpu_data_o_t; -- to adapter ibus_o
  signal c_cpu_i    : cpu_data_i_t; -- from adapter ibus_i
  signal c_mem_o    : cpu_data_o_t; -- adapter dbus_o
  signal c_mem_lock : std_logic;
  signal c_mem_ddrb : std_logic;

begin

  cacheable <= is_cacheable_mmu(cpu_o.a, a_mmu.at, a_mmu.c);

  -- CPU-side fan to the cache: only present the access when cacheable, else hold
  -- the cache idle (en=0).
  c_cpu_o <= cpu_o when cacheable else
             NULL_DATA_O;

  u_dcache : entity work.dcache_adapter
    port map (
      clk125        => clk125,
      clk200        => clk200,
      rst           => rst,
      ctrl          => ctrl,
      ibus_o        => c_cpu_o,
      a_mmu         => a_mmu,
      lock          => lock,
      ibus_i        => c_cpu_i,
      snpc_o        => snpc_o,
      snpc_i        => snpc_i,
      dbus_o        => c_mem_o,
      dbus_lock     => c_mem_lock,
      dbus_ddrburst => c_mem_ddrb,
      dbus_i        => mem_i,
      dbus_ack_r    => mem_ack_r
    );

  -- Memory-side mux: cache fill/writeback when the current access is cacheable,
  -- else the CPU access passes straight through.
  mem_o        <= c_mem_o when cacheable else
                  cpu_o;
  mem_lock     <= c_mem_lock when cacheable else
                  lock;
  mem_ddrburst <= c_mem_ddrb when cacheable else
                  '0';

  -- CPU response mux.
  cpu_i <= c_cpu_i when cacheable else
           mem_i;

end architecture arch;
