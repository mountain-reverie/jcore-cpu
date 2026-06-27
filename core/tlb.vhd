library ieee;
use ieee.std_logic_1164.all;
use work.cpu2j0_components_pack.all;

entity tlb is
  port (
    clk      : in  std_logic;
    i_va     : in  std_logic_vector(31 downto 0);
    i_pa_tag : out std_logic_vector(14 downto 0);
    i_pa12   : out std_logic;
    i_c      : out std_logic;
    i_hit    : out std_logic;
    i_prot   : out std_logic;
    d_va     : in  std_logic_vector(31 downto 0);
    d_we     : in  std_logic;
    d_pa_tag : out std_logic_vector(14 downto 0);
    d_pa12   : out std_logic;
    d_c      : out std_logic;
    d_hit    : out std_logic;
    d_prot   : out std_logic;
    asid     : in  std_logic_vector(15 downto 0);
    md       : in  std_logic;
    at       : in  std_logic;
    tlb_wr   : in  std_logic;
    pteh_vpn : in  std_logic_vector(31 downto 12);
    ptel     : in  std_logic_vector(31 downto 0);
    asidr    : in  std_logic_vector(15 downto 0);
    ti       : in  std_logic
  );
end entity;

architecture rtl of tlb is
  signal ram : tlb_array_t := (others => TLB_ENTRY_RESET);
begin

  -- Combinational I-lookup
  process(ram, i_va, asid, md)
    variable entry     : tlb_entry_t;
    variable hit_found : std_logic;
    variable hit_pa    : std_logic_vector(14 downto 0);
    variable hit_pa12  : std_logic;
    variable hit_c     : std_logic;
    variable prot      : std_logic;
  begin
    hit_found := '0'; hit_pa := (others => '0'); hit_pa12 := '0'; hit_c := '0'; prot := '0';
    for k in 0 to 31 loop
      entry := ram(k);
      if entry.valid = '1'
         and entry.vpn = i_va(31 downto 12)
         and (entry.global = '1' or entry.asid_tag = asid) then
        hit_found := '1';
        hit_pa    := entry.ppn(27 downto 13);  -- PA[27:13] = 15 bits
        hit_pa12  := entry.ppn(12);            -- PA[12] (PIPT relocation)
        hit_c     := entry.c;
        if entry.x = '0' or (entry.u = '0' and md = '0') then
          prot := '1';
        end if;
      end if;
    end loop;
    i_hit    <= hit_found;
    i_pa_tag <= hit_pa;
    i_pa12   <= hit_pa12;
    i_c      <= hit_c;
    i_prot   <= prot and hit_found;
  end process;

  -- Combinational D-lookup
  process(ram, d_va, d_we, asid, md)
    variable entry     : tlb_entry_t;
    variable hit_found : std_logic;
    variable hit_pa    : std_logic_vector(14 downto 0);
    variable hit_pa12  : std_logic;
    variable hit_c     : std_logic;
    variable prot      : std_logic;
  begin
    hit_found := '0'; hit_pa := (others => '0'); hit_pa12 := '0'; hit_c := '0'; prot := '0';
    for k in 0 to 31 loop
      entry := ram(k);
      if entry.valid = '1'
         and entry.vpn = d_va(31 downto 12)
         and (entry.global = '1' or entry.asid_tag = asid) then
        hit_found := '1';
        hit_pa    := entry.ppn(27 downto 13);
        hit_pa12  := entry.ppn(12);
        hit_c     := entry.c;
        if (entry.u = '0' and md = '0') or (d_we = '1' and entry.w = '0') then
          prot := '1';
        end if;
      end if;
    end loop;
    d_hit    <= hit_found;
    d_pa_tag <= hit_pa;
    d_pa12   <= hit_pa12;
    d_c      <= hit_c;
    d_prot   <= prot and hit_found;
  end process;

  -- Clocked write + TI flush (NRU replacement computed inline)
  process(clk)
    variable idx      : integer range 0 to 31;
    variable found    : boolean;
    variable all_used : boolean;
  begin
    if rising_edge(clk) then
      if ti = '1' then
        for k in 0 to 31 loop
          ram(k).valid <= '0';
          ram(k).used  <= '0';
        end loop;
      elsif tlb_wr = '1' then
        -- NRU: find first invalid slot; if none, first unused; if all used clear all
        idx := 0; found := false; all_used := true;
        for k in 0 to 31 loop
          if not found then
            if ram(k).valid = '0' then
              idx := k; found := true;
            elsif ram(k).used = '0' then
              if all_used then idx := k; end if;
              all_used := false;
            end if;
          end if;
        end loop;
        if not found and all_used then
          -- all entries valid+used: clear used bits, write to slot 0
          for k in 0 to 31 loop
            ram(k).used <= '0';
          end loop;
          idx := 0;
        end if;
        ram(idx).valid     <= '1';
        ram(idx).used      <= '1';
        ram(idx).vpn       <= pteh_vpn;
        ram(idx).asid_tag  <= asidr;
        ram(idx).page_mask <= (others => '0');
        ram(idx).ppn       <= ptel(31 downto 10);
        ram(idx).w         <= ptel(7);
        ram(idx).x         <= ptel(6);
        ram(idx).u         <= ptel(5);
        ram(idx).d         <= ptel(4);
        ram(idx).c         <= ptel(3);
        ram(idx).global    <= ptel(2);
        ram(idx).stale     <= ptel(1);
      end if;
    end if;
  end process;

end architecture;
