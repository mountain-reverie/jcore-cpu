library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cpu2j0_pack.all;
  use work.data_bus_pack.all;
  use work.cache_pack.all;

entity dcache_color_tb is
end entity dcache_color_tb;

architecture tb of dcache_color_tb is

  signal clk, rst     : std_logic     := '0';
  signal done         : boolean       := false;
  signal ctrl         : cache_ctrl_t  := (en => '1', inv => '0');
  signal cpu_o        : cpu_data_o_t  := NULL_DATA_O;
  signal cpu_i        : cpu_data_i_t;
  signal a_mmu        : mmu_cache_i_t := MMU_CACHE_I_RESET;
  signal mem_o        : cpu_data_o_t;
  signal mem_i        : cpu_data_i_t;
  signal mem_lock     : std_logic;
  signal mem_ddrburst : std_logic;
  signal mem_ack_r    : std_logic;

  constant memw : integer := 16384;        -- 64 KB

  subtype word_t is std_logic_vector(31 downto 0);

  type mem_t is array (0 to memw - 1) of word_t;

  shared variable ddr_mem : mem_t := (others => (others => '0'));

  function widx (
    a : std_logic_vector
  ) return integer is

    variable v : std_logic_vector(a'length - 1 downto 0) := a;

  begin return to_integer(unsigned(v(15 downto 2))); end function widx;
  signal mem_o_d5 : cpu_data_o_t := NULL_DATA_O;
  signal ddr_rdy  : std_logic    := '0';

begin

  clk <= not clk after 4 ns when not done else
         '0';
  rst <= '1', '0' after 15 ns;

  dut : component dcache_cacheable_mux
    port map (
      clk125       => clk,
      clk200       => clk,
      rst          => rst,
      ctrl         => ctrl,
      cpu_o        => cpu_o,
      a_mmu        => a_mmu,
      lock         => '0',
      cpu_i        => cpu_i,
      mem_o        => mem_o,
      mem_lock     => mem_lock,
      mem_ddrburst => mem_ddrburst,
      mem_i        => mem_i,
      mem_ack_r    => mem_ack_r
    );

  -- behavioral 1-wait memory (same shape as dcache_check_tb)
  mem_o_d5 <= mem_o after 5 ns;

  process (mem_o, mem_o_d5) is
  begin

    if (mem_o_d5.en = '1' and mem_o.en = '1' and mem_o_d5.a = mem_o.a) then
      ddr_rdy <= '1';
    else
      ddr_rdy <= '0';
    end if;

  end process;

  mem_i.ack <= ddr_rdy; mem_ack_r <= ddr_rdy;

  process (mem_o, ddr_rdy) is
  begin

    if (ddr_rdy = '1') then
      mem_i.d <= ddr_mem(widx(mem_o.a));
    else
      mem_i.d <= (others => '0');
    end if;

  end process;

  process (clk) is
  begin

    if rising_edge(clk) then
      if (mem_o.en = '1' and mem_o.wr = '1') then

        for i in 0 to 3 loop

          if (mem_o.we(i) = '1') then
            ddr_mem(widx(mem_o.a))(8 * i + 7 downto 8 * i) := mem_o.d(8 * i + 7 downto 8 * i);
          end if;

        end loop;

      end if;
    end if;

  end process;

  stim : process is

    constant pat : word_t := x"C010C010";
    -- PA_BUF page = 0x10000 (PA[12]=0). pa_tag = PA[27:13] = 0x10000 >> 13 = 8.
    constant pa_tag : std_logic_vector(14 downto 0) := std_logic_vector(to_unsigned(8, 15));

    procedure tick is begin wait until rising_edge(clk); end procedure tick;

    procedure do_acc (
      a  : word_t;
      wr : std_logic;
      d  : word_t;
      at : std_logic
    ) is
    begin

      a_mmu <= (pa_tag => PA_TAG, at => at, c => '1');
      cpu_o <= (en=> '1', a=> a, rd=> not wr, wr=> wr, we=> (others => wr), d=> d);

      loop

        tick; exit when cpu_i.ack = '1';

      end loop;

      cpu_o <= NULL_DATA_O;
      a_mmu <= MMU_CACHE_I_RESET;
      tick;

    end procedure do_acc;
    variable got : word_t;

  begin

    wait until rst = '0';

    for i in 0 to 4 loop

      tick;

    end loop;

    -- color-correct WRITE: VA index bit12 = 0 (set 0), dirty, write-back -> mem
    -- at PA 0x10000 NOT updated.
    do_acc(x"00010000", '1', PAT, '1');
    -- mis-colored READ: VA index bit12 = 1 (set 1), same pa_tag -> miss -> fills
    -- from a different physical line -> stale (zero), NOT the pattern.
    a_mmu <= (pa_tag => pa_tag, at => '1', c => '1');
    cpu_o <= (en=> '1', a=> x"00011000", rd=> '1', wr=> '0', we=> "0000", d=> (others => '0'));

    loop

      tick; exit when cpu_i.ack = '1';

    end loop;

    got   := cpu_i.d; cpu_o <= NULL_DATA_O;
    a_mmu <= MMU_CACHE_I_RESET;
    tick;
    assert got /= pat
      report "COLORING FAIL: mis-colored read returned fresh pattern (synonym handled)"
      severity failure;
    report "coloring staleness observed: got=" & integer'image(to_integer(unsigned(got)))
      severity note;
    -- uncached bypass: a P2 write must reach memory directly (no caching).
    cpu_o <= (en=> '1', a=> x"A0000040", rd=> '0', wr=> '1', we=> "1111", d=> x"DEADBEEF");

    loop

      tick; exit when cpu_i.ack = '1';

    end loop;

    cpu_o <= NULL_DATA_O;
    tick;
    assert ddr_mem(widx(x"A0000040")) = x"DEADBEEF"
      report "BYPASS FAIL: uncached write did not reach memory"
      severity failure;
    -- C-bit override: a TRANSLATED (at='1') write to a cacheable region (P0) but
    -- with PTE C='0' must bypass straight to memory, NOT be cached/held dirty.
    a_mmu <= (pa_tag => std_logic_vector(to_unsigned(9, 15)), at => '1', c => '0');
    cpu_o <= (en=> '1', a=> x"00012000", rd=> '0', wr=> '1', we=> "1111", d=> x"FEEDFACE");

    loop

      tick; exit when cpu_i.ack = '1';

    end loop;

    cpu_o <= NULL_DATA_O;
    a_mmu <= MMU_CACHE_I_RESET;
    tick;
    assert ddr_mem(widx(x"00012000")) = x"FEEDFACE"
      report "C-BIT FAIL: translated C=0 write was cached, did not reach memory"
      severity failure;
    report "dcache_color_tb: all tests passed"
      severity note;
    done  <= true;
    wait;

  end process;

end architecture tb;
