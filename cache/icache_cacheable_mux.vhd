library ieee;
  use ieee.std_logic_1164.all;
  use work.cpu2j0_pack.all;
  use work.data_bus_pack.all;
  use work.cache_pack.all;

-- Routes CPU instruction fetches by MMU cacheability: cacheable -> icache,
-- uncached (P2/P4 region, or translated page with PTE C=0) -> direct bypass
-- read on the memory bus. Mirrors dcache_cacheable_mux; the bypass reuses the
-- canonical splice_instr_data_bus (correct 16-bit big-endian half selection).

entity icache_cacheable_mux is
  port (
    clk125 : in    std_logic;
    clk200 : in    std_logic;
    rst    : in    std_logic;
    ctrl   : in    cache_ctrl_t;
    -- CPU side
    ibus_o : in    cpu_instruction_o_t; -- from cpu.inst_o
    a_mmu  : in    mmu_cache_i_t;       -- from cpu.mmu_o (i_pa_tag/i_at/i_c)
    ibus_i : out   cpu_instruction_i_t; -- to cpu.inst_i
    -- memory side (data-typed)
    mem_o        : out   cpu_data_o_t;
    mem_ddrburst : out   std_logic;
    mem_i        : in    cpu_data_i_t;
    mem_ack_r    : in    std_logic
  );
end entity icache_cacheable_mux;

architecture arch of icache_cacheable_mux is

  signal cacheable : boolean;
  -- '1' iff this fetch's translation is known this cycle (MMU off, or MMU on
  -- and the ITLB lookup hit). See the comment on g_ibus_o below.
  signal translated : boolean;
  -- ibus_o, held idle while the translation is unknown.
  signal g_ibus_o : cpu_instruction_o_t;
  signal c_ibus_o : cpu_instruction_o_t; -- to icache_adapter (idle when uncacheable)
  signal c_ibus_i : cpu_instruction_i_t; -- from icache_adapter
  signal c_mem_o  : cpu_data_o_t;        -- icache_adapter dbus_o
  signal c_ddrb   : std_logic;
  signal b_ibus_i : cpu_instruction_i_t; -- bypass reply
  signal b_mem_o  : cpu_data_o_t;        -- bypass data request

begin

  cacheable <= is_cacheable_mmu(ibus_o.a & '0', a_mmu.at, a_mmu.c);

  -- A fetch that missed in the ITLB has NO translation yet: a_mmu.pa_tag and
  -- a_mmu.c are both undefined, and the core deliberately keeps inst_o.en
  -- asserted across the whole walk (core/cpu.vhd withholds dp_inst_i.ack, not
  -- the request) so the fetch replays against the installed entry afterwards.
  -- The half that actually matters is the BYPASS. `cacheable` above is
  -- is_cacheable_mmu(.., a_mmu.at, a_mmu.c); on an ITLB miss at='1' and c is
  -- undefined, and the untranslated fetch is routed uncacheable -- so it never
  -- reaches the icache in the first place, and no line fill and no tag commit
  -- is at stake. It reaches the BYPASS, which happily issues a bus read for the
  -- raw, UNTRANSLATED VA and acks the fetch with whatever came back. The core
  -- is mid-walk and expects no ack at all; it gets one, carrying data from an
  -- address that was never translated. Hold the fetch out of BOTH arms until
  -- its translation exists -- gating only the bypass would leave a
  -- cacheable-looking miss free to do the same thing the day the routing
  -- changes, and gating both is the same one signal.
  translated <= (a_mmu.at = '0') or (a_mmu.hit = '1');

  g_ibus_o <= ibus_o when translated else
              NULL_INST_O;

  -- present the fetch to the icache only when cacheable, else hold it idle.
  c_ibus_o <= g_ibus_o when cacheable else
              NULL_INST_O;

  u_icache : entity work.icache_adapter
    port map (
      clk125        => clk125,
      clk200        => clk200,
      rst           => rst,
      ctrl          => ctrl,
      ibus_o        => c_ibus_o,
      ibus_i        => c_ibus_i,
      a_mmu         => a_mmu,
      dbus_o        => c_mem_o,
      dbus_ddrburst => c_ddrb,
      dbus_i        => mem_i,
      dbus_ack_r    => mem_ack_r
    );

  -- bypass: instruction fetch as a direct 32-bit data read with correct
  -- 16-bit half selection. Process wrapper required (VHDL-93 disallows
  -- concurrent procedure calls in architecture bodies).
  process (g_ibus_o, mem_i) is
  begin

    splice_instr_data_bus(g_ibus_o, b_ibus_i, b_mem_o, mem_i);

  end process;

  -- memory-side + response muxes select on cacheability.
  mem_o        <= c_mem_o when cacheable else
                  b_mem_o;
  mem_ddrburst <= c_ddrb when cacheable else
                  '0';
  ibus_i       <= c_ibus_i when cacheable else
                  b_ibus_i;

end architecture arch;
