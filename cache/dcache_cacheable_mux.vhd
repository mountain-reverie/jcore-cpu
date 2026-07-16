library ieee;
  use ieee.std_logic_1164.all;
  use work.cpu2j0_pack.all;
  use work.data_bus_pack.all;
  use work.cache_pack.all;

-- Routes CPU data accesses by SH cacheability: cacheable -> write-back D-cache,
-- uncached (MMIO/control) -> direct bypass to the memory bus. The cacheable
-- decision is combinational on the (stable-for-the-whole-access) CPU address.

entity dcache_cacheable_mux is
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
    -- memory side
    mem_o        : out   cpu_data_o_t; -- to bus fabric master
    mem_lock     : out   std_logic;
    mem_ddrburst : out   std_logic;
    mem_i        : in    cpu_data_i_t; -- from bus fabric
    mem_ack_r    : in    std_logic
  );
end entity dcache_cacheable_mux;

architecture arch of dcache_cacheable_mux is

  signal cacheable : boolean;
  -- cache (dcache_adapter) CPU-side and memory-side nets
  signal c_cpu_o    : cpu_data_o_t; -- to adapter ibus_o
  signal c_cpu_i    : cpu_data_i_t; -- from adapter ibus_i
  signal c_mem_o    : cpu_data_o_t; -- adapter dbus_o
  signal c_mem_lock : std_logic;
  signal c_mem_ddrb : std_logic;
  -- The cache still owns the memory bus while it has an in-flight mem-side
  -- transaction (a background line fill or a dirty-line writeback): the dcache
  -- acks the CPU on the critical word and completes the burst in the background,
  -- so cpu_o may already have advanced to a following (uncacheable) access.
  signal cache_busy : std_logic;
  -- snoop tie-offs
  signal snp_o : dcache_snoop_io_t;

begin

  cacheable <= is_cacheable_mmu(cpu_o.a, a_mmu.at, a_mmu.c);
  cache_busy <= c_mem_o.en;

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
      snpc_o        => snp_o,
      snpc_i        => NULL_SNOOP_IO,
      dbus_o        => c_mem_o,
      dbus_lock     => c_mem_lock,
      dbus_ddrburst => c_mem_ddrb,
      dbus_i        => mem_i,
      dbus_ack_r    => mem_ack_r
    );

  -- Memory-side mux: the cache drives the bus whenever the current access is
  -- cacheable OR it still has a burst in flight. An uncacheable bypass access
  -- must NOT steal the bus mid-burst -- doing so drops a fill word and the CPU
  -- later reads stale/zero data on the resulting bogus cache hit.
  mem_o        <= c_mem_o    when (cacheable or cache_busy = '1') else cpu_o;
  mem_lock     <= c_mem_lock when (cacheable or cache_busy = '1') else lock;
  mem_ddrburst <= c_mem_ddrb when cacheable else '0';

  -- CPU response mux. For an uncacheable access, suppress ack while the cache
  -- still owns the bus: mem_i.ack in that window is acking the cache's fill
  -- word, not the CPU's held-off bypass access.
  cpu_i.d   <= c_cpu_i.d   when cacheable else mem_i.d;
  cpu_i.ack <= c_cpu_i.ack when cacheable else (mem_i.ack and not cache_busy);
end architecture;
