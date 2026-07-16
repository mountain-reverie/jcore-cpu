library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cpu2j0_pack.all;
  use work.data_bus_pack.all;
  use work.cache_pack.all;

entity icache_cacheable_mux_tb is
end entity icache_cacheable_mux_tb;

architecture tb of icache_cacheable_mux_tb is

  signal   clk,          rst       : std_logic                     := '0';
  signal   done                    : boolean                       := false;
  signal   ctrl                    : cache_ctrl_t                  := (en => '1', inv => '0');
  signal   ibus_o                  : cpu_instruction_o_t           := NULL_INST_O;
  signal   ibus_i                  : cpu_instruction_i_t;
  signal   a_mmu                   : mmu_cache_i_t                 := MMU_CACHE_I_RESET;
  signal   mem_o                   : cpu_data_o_t;
  signal   mem_ddrburst, mem_ack_r : std_logic;
  signal   mem_i                   : cpu_data_i_t;
  constant memword                 : std_logic_vector(31 downto 0) := x"AAAABBBB"; -- [31:16]=AAAA [15:0]=BBBB

begin

  clk <= not clk after 4 ns when not done else
         '0';
  rst <= '1', '0' after 15 ns;

  dut : entity work.icache_cacheable_mux
    port map (
      clk125       => clk,
      clk200       => clk,
      rst          => rst,
      ctrl         => ctrl,
      ibus_o       => ibus_o,
      a_mmu        => a_mmu,
      ibus_i       => ibus_i,
      mem_o        => mem_o,
      mem_ddrburst => mem_ddrburst,
      mem_i        => mem_i,
      mem_ack_r    => mem_ack_r
    );

  -- behavioral 1-cycle memory: ack any read, always return MEMWORD.
  process (clk) is
  begin

    if rising_edge(clk) then
      if (mem_o.en = '1' and mem_o.rd = '1') then
        mem_i.ack <= '1';
        mem_i.d   <= memword;
      else
        mem_i.ack <= '0';
        mem_i.d   <= (others => '0');
      end if;
    end if;

  end process;

  mem_ack_r <= mem_i.ack;

  stim : process is

    procedure fetch (
      a      : std_logic_vector(31 downto 1);
      at,
      c      : std_logic;
      expect : std_logic_vector(15 downto 0);
      nm     : string
    ) is

      variable cyc : integer := 0;

    begin

      a_mmu  <= (pa_tag => (others => '0'), at => at, c => c);
      ibus_o <= (en => '1', a => a, jp => '0');

      loop

        wait until rising_edge(clk); cyc := cyc + 1;
        exit when ibus_i.ack = '1'; assert cyc < 50
          report nm & ": no ack"
          severity failure;

      end loop;

      assert ibus_i.d = expect
        report nm & ": got " & integer'image(to_integer(unsigned(ibus_i.d)))
        severity failure;
      ibus_o <= NULL_INST_O;
      a_mmu  <= MMU_CACHE_I_RESET;
      wait until rising_edge(clk);

    end procedure fetch;

  begin

    wait until rst = '0';

    for i in 0 to 3 loop

      wait until rising_edge(clk);

    end loop;

    -- Bypass via region: P2 (uncached), even-halfword -> upper half AAAA.
    -- a[31:1] = 0xA0000000>>1 = 31 bits: 101 followed by 28 zeros, a(1)=0
    fetch("101" & (27 downto 0 => '0'), '0', '1', x"AAAA", "P2 even bypass");
    -- Bypass via region: P2 odd-halfword (a(1)=1) -> lower half BBBB.
    -- same P2 prefix, last bit = 1 (a(1)=1)
    fetch("101" & (27 downto 1 => '0') & "1", '0', '0', x"BBBB", "P2 odd bypass");
    -- Bypass via C-bit override: translated (at=1) cacheable region but C=0.
    -- a=0x00000000, 31 bits all zero, a(1)=0
    fetch("0000000000000000000000000000000", '1', '0', x"AAAA", "AT1 C0 bypass");
    report "icache_cacheable_mux_tb: all bypass tests passed"
      severity note;
    done <= true;
    wait;

  end process;

end architecture tb;
