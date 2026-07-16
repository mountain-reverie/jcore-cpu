-- Unit test for the behavioral SB_MAC16 (core/sb_mac16_sim.vhd): proves the
-- model registers the unsigned 16x16 product with one clock of latency, and
-- that the BOT/TOP post-multiply adder stage produces correct results.
-- dut  : product-bypass mode (TOPOUTPUT_SELECT/BOTOUTPUT_SELECT = "11")
-- dut2 : adder mode (OUTPUT_SELECT = "00", adder engaged, iH feeds adder)

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.test_pkg.all;

entity sb_mac16_tap is
end entity sb_mac16_tap;

architecture tb of sb_mac16_tap is

  signal clk  : std_logic                     := '0';
  signal a, b : std_logic_vector(15 downto 0) := (others => '0');
  signal o    : std_logic_vector(31 downto 0);

  -- dut2 signals (adder mode)
  signal a2       : std_logic_vector(15 downto 0) := (others => '0');
  signal b2       : std_logic_vector(15 downto 0) := (others => '0');
  signal c2       : std_logic_vector(15 downto 0) := (others => '0');
  signal d2       : std_logic_vector(15 downto 0) := (others => '0');
  signal o2       : std_logic_vector(31 downto 0);
  signal accumco2 : std_logic;

  shared variable endsim : boolean := false;

  component sb_mac16 is
    generic (
      neg_trigger              : std_logic := '0';
      c_reg                    : std_logic := '0';
      a_reg                    : std_logic := '0';
      b_reg                    : std_logic := '0';
      d_reg                    : std_logic := '0';
      top_8x8_mult_reg         : std_logic := '0';
      bot_8x8_mult_reg         : std_logic := '0';
      pipeline_16x16_mult_reg1 : std_logic := '0';
      pipeline_16x16_mult_reg2 : std_logic := '0';
      topoutput_select         : std_logic_vector(1 downto 0) := "00";
      topaddsub_lowerinput     : std_logic_vector(1 downto 0) := "00";
      topaddsub_upperinput     : std_logic := '0';
      topaddsub_carryselect    : std_logic_vector(1 downto 0) := "00";
      botoutput_select         : std_logic_vector(1 downto 0) := "00";
      botaddsub_lowerinput     : std_logic_vector(1 downto 0) := "00";
      botaddsub_upperinput     : std_logic := '0';
      botaddsub_carryselect    : std_logic_vector(1 downto 0) := "00";
      mode_8x8                 : std_logic := '0';
      a_signed                 : std_logic := '0';
      b_signed                 : std_logic := '0'
    );
    port (
      clk        : in    std_logic;
      ce         : in    std_logic;
      a          : in    std_logic_vector(15 downto 0);
      b          : in    std_logic_vector(15 downto 0);
      c          : in    std_logic_vector(15 downto 0);
      d          : in    std_logic_vector(15 downto 0);
      ahold      : in    std_logic;
      bhold      : in    std_logic;
      chold      : in    std_logic;
      dhold      : in    std_logic;
      irsttop    : in    std_logic;
      irstbot    : in    std_logic;
      orsttop    : in    std_logic;
      orstbot    : in    std_logic;
      oloadtop   : in    std_logic;
      oloadbot   : in    std_logic;
      addsubtop  : in    std_logic;
      addsubbot  : in    std_logic;
      oholdtop   : in    std_logic;
      oholdbot   : in    std_logic;
      ci         : in    std_logic;
      accumci    : in    std_logic;
      signextin  : in    std_logic;
      o          : out   std_logic_vector(31 downto 0);
      co         : out   std_logic;
      accumco    : out   std_logic;
      signextout : out   std_logic
    );
  end component sb_mac16;

begin

  clkgen : process is
  begin

    while not endsim loop

      clk                <= '0';
      wait for 5 ns; clk <= '1';
      wait for 5 ns;

    end loop;

    wait;

  end process;

  -- Product-bypass instance (existing tests)
  dut : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      topoutput_select         => "11", botoutput_select => "11"
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => a,
      b          => b,
      c          => (others => '0'),
      d          => (others => '0'),
      ahold      => '0',
      bhold      => '0',
      chold      => '0',
      dhold      => '0',
      irsttop    => '0',
      irstbot    => '0',
      orsttop    => '0',
      orstbot    => '0',
      oloadtop   => '0',
      oloadbot   => '0',
      addsubtop  => '0',
      addsubbot  => '0',
      oholdtop   => '0',
      oholdbot   => '0',
      ci         => '0',
      accumci    => '0',
      signextin  => '0',
      o          => o,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- Adder-mode instance: iH feeds BOT+TOP adder, C/D are addends
  -- BOTADDSUB_LOWERINPUT="10" → iH[15:0]; BOTADDSUB_UPPERINPUT='1' → D
  -- BOTADDSUB_CARRYSELECT="00" → LCI=0; BOTOUTPUT_SELECT="00" → adder result
  -- TOPADDSUB_LOWERINPUT="10" → iH[31:16]; TOPADDSUB_UPPERINPUT='1' → C
  -- TOPADDSUB_CARRYSELECT="10" → HCI=LCO; TOPOUTPUT_SELECT="00" → adder result
  dut2 : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      botaddsub_lowerinput     => "10",
      botaddsub_upperinput     => '1',
      botaddsub_carryselect    => "00",
      botoutput_select         => "00",
      topaddsub_lowerinput     => "10",
      topaddsub_upperinput     => '1',
      topaddsub_carryselect    => "10",
      topoutput_select         => "00"
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => a2,
      b          => b2,
      c          => c2,
      d          => d2,
      ahold      => '0',
      bhold      => '0',
      chold      => '0',
      dhold      => '0',
      irsttop    => '0',
      irstbot    => '0',
      orsttop    => '0',
      orstbot    => '0',
      oloadtop   => '0',
      oloadbot   => '0',
      addsubtop  => '0',
      addsubbot  => '0',
      oholdtop   => '0',
      oholdbot   => '0',
      ci         => '0',
      accumci    => '0',
      signextin  => '0',
      o          => o2,
      co         => open,
      accumco    => accumco2,
      signextout => open
    );

  stim : process is

    procedure check (
      av,
      bv : integer
    ) is

      variable exp : std_logic_vector(31 downto 0);

    begin

      a <= std_logic_vector(to_unsigned(av, 16));
      b <= std_logic_vector(to_unsigned(bv, 16));
      wait until rising_edge(clk); -- inputs presented
      wait until rising_edge(clk); -- registered product available
      -- Compute via unsigned 16x16->32 to avoid native-integer overflow
      -- (e.g. 65535*65535 exceeds integer'high).
      exp := std_logic_vector(to_unsigned(av, 16) * to_unsigned(bv, 16));
      test_ok(o = exp, "SB_MAC16 " & integer'image(av) & "*" & integer'image(bv));

    end procedure check;

    -- Check adder mode: O = (A*B) + (C concatenated with D) as 32-bit add.
    -- Hand-computed expected values (see comments below each call).

    procedure check_adder (
      av,
      bv,
      cv,
      dv          : integer;
      exp_o       : std_logic_vector(31 downto 0);
      exp_accumco : std_logic;
      tag         : string
    ) is
    begin

      a2 <= std_logic_vector(to_unsigned(av, 16));
      b2 <= std_logic_vector(to_unsigned(bv, 16));
      c2 <= std_logic_vector(to_unsigned(cv, 16));
      d2 <= std_logic_vector(to_unsigned(dv, 16));
      wait until rising_edge(clk); -- inputs presented, prod will update
      wait until rising_edge(clk); -- prod now = A*B; O is combinational
      test_ok(o2 = exp_o and accumco2 = exp_accumco,
              "SB_MAC16 adder " & tag);

    end procedure check_adder;

  begin

    test_plan(7, "SB_MAC16 behavioral model");

    -- Existing product-bypass cases (dut, BOTOUTPUT_SELECT/TOPOUTPUT_SELECT="11")
    check(0, 0);
    check(3, 7);
    check(65535, 65535);   -- 0xFFFF * 0xFFFF = 0xFFFE0001
    check(1234, 4321);

    -- Adder-mode cases (dut2, OUTPUT_SELECT="00" → combinational adder result)
    --
    -- bot_add_d: A=16, B=16 → prod=0x00000100; D=5, C=0; LCI=0
    --   BOTres = 0x0100 + 0x0005 + 0 = 0x0105, LCO=0
    --   TOPres = 0x0000 + 0x0000 + LCO(0) = 0x0000
    --   O = 0x00000105, ACCUMCO=0
    check_adder(16, 16, 0, 5, x"00000105", '0', "bot_add_d");

    -- full32_add: A=256, B=256 → prod=0x00010000; C=1, D=0; LCI=0
    --   BOTres = 0x0000 + 0x0000 + 0 = 0x0000, LCO=0
    --   TOPres = 0x0001 + 0x0001 + LCO(0) = 0x0002
    --   O = 0x00020000, ACCUMCO=0
    check_adder(256, 256, 1, 0, x"00020000", '0', "full32_add");

    -- full32_carry: A=255, B=257 → prod=0x0000FFFF; C=0, D=1; LCI=0
    --   BOTres = 0xFFFF + 0x0001 + 0 = 0x10000 → BOTres=0x0000, LCO=1
    --   TOPres = 0x0000 + 0x0000 + LCO(1) = 0x0001
    --   O = 0x00010000, ACCUMCO=0
    check_adder(255, 257, 0, 1, x"00010000", '0', "full32_carry");

    test_finished("done");
    endsim := true;
    wait;

  end process;

end architecture tb;
