-- Sim-only behavioural model of the iCE40 SB_MAC16 DSP block.
--
-- mult(ice40dsp) (core/mult_ice40dsp.vhd) instantiates SB_MAC16 as a COMPONENT
-- and feeds it UNSIGNED 16x16 magnitude operands. At synthesis the component is
-- left unbound (--syn-binding) so yosys synth_ice40 maps it to the real DSP;
-- ghdl cannot elaborate that primitive, so simulation analyzes this stand-in
-- instead. Deliberately EXCLUDED from every synth filelist, exactly like
-- targets/boards/ulx3s/tb/ehxpll_sim.vhd vs clkgen(ecp5)/EHXPLLL.
--
-- Models only what mult(ice40dsp) uses: O = unsigned(A)*unsigned(B), registered
-- once (PIPELINE_16x16_MULT_REG1), gated by CE. The accumulate/add/sign control
-- ports and the A_SIGNED/B_SIGNED generics are accepted and ignored.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SB_MAC16 is
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
end entity;

architecture behave of SB_MAC16 is
  signal prod : std_logic_vector(31 downto 0) := (others => '0');
begin
  process(CLK) begin
    if rising_edge(CLK) then
      if CE = '1' then
        prod <= std_logic_vector(unsigned(A) * unsigned(B));
      end if;
    end if;
  end process;
  O          <= prod;
  CO         <= '0';
  ACCUMCO    <= '0';
  SIGNEXTOUT <= '0';
end architecture;
