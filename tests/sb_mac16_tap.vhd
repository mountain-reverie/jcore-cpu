-- Unit test for the behavioral SB_MAC16 (core/sb_mac16_sim.vhd): proves the
-- model registers the unsigned 16x16 product with one clock of latency. This
-- is the sim stand-in that mult(ice40dsp) binds; the real DSP is supplied by
-- yosys synth_ice40 at synthesis.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.test_pkg.all;

entity sb_mac16_tap is
end sb_mac16_tap;

architecture tb of sb_mac16_tap is
  signal clk : std_logic := '0';
  signal a, b : std_logic_vector(15 downto 0) := (others => '0');
  signal o : std_logic_vector(31 downto 0);
  shared variable ENDSIM : boolean := false;

  component SB_MAC16 is
    generic (
      NEG_TRIGGER : std_logic := '0';
      C_REG : std_logic := '0'; A_REG : std_logic := '0';
      B_REG : std_logic := '0'; D_REG : std_logic := '0';
      TOP_8x8_MULT_REG : std_logic := '0'; BOT_8x8_MULT_REG : std_logic := '0';
      PIPELINE_16x16_MULT_REG1 : std_logic := '0';
      PIPELINE_16x16_MULT_REG2 : std_logic := '0';
      TOPOUTPUT_SELECT : std_logic_vector(1 downto 0) := "00";
      TOPADDSUB_LOWERINPUT : std_logic_vector(1 downto 0) := "00";
      TOPADDSUB_UPPERINPUT : std_logic := '0';
      TOPADDSUB_CARRYSELECT : std_logic_vector(1 downto 0) := "00";
      BOTOUTPUT_SELECT : std_logic_vector(1 downto 0) := "00";
      BOTADDSUB_LOWERINPUT : std_logic_vector(1 downto 0) := "00";
      BOTADDSUB_UPPERINPUT : std_logic := '0';
      BOTADDSUB_CARRYSELECT : std_logic_vector(1 downto 0) := "00";
      MODE_8x8 : std_logic := '0';
      A_SIGNED : std_logic := '0'; B_SIGNED : std_logic := '0');
    port (
      CLK : in std_logic; CE : in std_logic;
      A : in std_logic_vector(15 downto 0); B : in std_logic_vector(15 downto 0);
      C : in std_logic_vector(15 downto 0); D : in std_logic_vector(15 downto 0);
      AHOLD : in std_logic; BHOLD : in std_logic;
      CHOLD : in std_logic; DHOLD : in std_logic;
      IRSTTOP : in std_logic; IRSTBOT : in std_logic;
      ORSTTOP : in std_logic; ORSTBOT : in std_logic;
      OLOADTOP : in std_logic; OLOADBOT : in std_logic;
      ADDSUBTOP : in std_logic; ADDSUBBOT : in std_logic;
      OHOLDTOP : in std_logic; OHOLDBOT : in std_logic;
      CI : in std_logic; ACCUMCI : in std_logic; SIGNEXTIN : in std_logic;
      O : out std_logic_vector(31 downto 0);
      CO : out std_logic; ACCUMCO : out std_logic; SIGNEXTOUT : out std_logic);
  end component;
begin
  clkgen : process begin
    while not ENDSIM loop
      clk <= '0'; wait for 5 ns; clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  dut : SB_MAC16
    generic map (PIPELINE_16x16_MULT_REG1 => '1',
                 TOPOUTPUT_SELECT => "11", BOTOUTPUT_SELECT => "11")
    port map (
      CLK => clk, CE => '1', A => a, B => b,
      C => (others => '0'), D => (others => '0'),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => '0',
      SIGNEXTIN => '0', O => o, CO => open, ACCUMCO => open, SIGNEXTOUT => open);

  stim : process
    procedure check(av, bv : integer) is
      variable exp : std_logic_vector(31 downto 0);
    begin
      a <= std_logic_vector(to_unsigned(av, 16));
      b <= std_logic_vector(to_unsigned(bv, 16));
      wait until rising_edge(clk);   -- inputs presented
      wait until rising_edge(clk);   -- registered product available
      -- Compute via unsigned 16x16->32 to avoid native-integer overflow
      -- (e.g. 65535*65535 exceeds integer'high).
      exp := std_logic_vector(to_unsigned(av, 16) * to_unsigned(bv, 16));
      test_ok(o = exp, "SB_MAC16 " & integer'image(av) & "*" & integer'image(bv));
    end procedure;
  begin
    test_plan(4, "SB_MAC16 behavioral model");
    check(0, 0);
    check(3, 7);
    check(65535, 65535);   -- 0xFFFF * 0xFFFF = 0xFFFE0001
    check(1234, 4321);
    test_finished("done");
    ENDSIM := true;
    wait;
  end process;
end tb;
