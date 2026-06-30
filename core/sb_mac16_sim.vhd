-- Sim-only behavioural model of the iCE40 SB_MAC16 DSP block.
--
-- mult(ice40dsp) (core/mult_ice40dsp.vhd) instantiates SB_MAC16 as a COMPONENT
-- and feeds it UNSIGNED 16x16 magnitude operands. At synthesis the component is
-- left unbound (--syn-binding) so yosys synth_ice40 maps it to the real DSP;
-- ghdl cannot elaborate that primitive, so simulation analyzes this stand-in
-- instead. Deliberately EXCLUDED from every synth filelist, exactly like
-- targets/boards/ulx3s/tb/ehxpll_sim.vhd vs clkgen(ecp5)/EHXPLLL.
--
-- Models the registered 16x16 unsigned product (iH) plus the 32-bit
-- BOT/TOP post-multiply adder stage, matching yosys cells_sim.v SB_MAC16 for
-- the parameter subset used by Task 10:
--   BOT: {LCO, BOTres} = iH[15:0] + D + LCI  (or B, SIGNEXTIN via mux)
--   TOP: {ACCUMCO, TOPres} = iH[31:16] + C + HCI  (HCI from LCO)
-- Generics not implemented (left as accepted/ignored): AHOLD/BHOLD/CHOLD/DHOLD,
-- IRST*/ORST*/OLOAD*/OHOLD*, A_REG/B_REG/C_REG/D_REG, 8x8 registers,
-- PIPELINE_16x16_MULT_REG2, MODE_8x8, A_SIGNED/B_SIGNED, OUTPUT_SELECT "01"/"10".
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
  -- iH: registered 16x16 product (PIPELINE_16x16_MULT_REG1 path)
  signal prod : std_logic_vector(31 downto 0) := (others => '0');
begin
  process(CLK) begin
    if rising_edge(CLK) then
      if CE = '1' then
        prod <= std_logic_vector(unsigned(A) * unsigned(B));
      end if;
    end if;
  end process;

  -- Combinational BOT/TOP adder stage, transcribed from yosys cells_sim.v.
  -- Variable names iZ/iY/LCI/LCO/YZ/iR/iX/iW/HCI/XW/iP match cells_sim.v.
  -- The xor-with-replicated-ADDSUB form matches cells_sim.v even when ADDSUB='0'.
  -- Accumulator registers (iS/iQ in cells_sim.v) are zeroed — not modelled.
  process(prod, A, B, C, D, CI, ACCUMCI, SIGNEXTIN, ADDSUBBOT, ADDSUBTOP)
    variable iZ_v        : unsigned(15 downto 0);
    variable iY_v        : unsigned(15 downto 0);
    variable addsubbot_rep : unsigned(15 downto 0);
    variable addsubtop_rep : unsigned(15 downto 0);
    variable LCI_v       : std_logic;
    variable sum17_bot   : unsigned(16 downto 0);
    variable LCO_v       : std_logic;
    variable YZ_v        : unsigned(15 downto 0);
    variable iR_v        : unsigned(15 downto 0);
    variable iX_v        : unsigned(15 downto 0);
    variable iW_v        : unsigned(15 downto 0);
    variable HCI_v       : std_logic;
    variable sum17_top   : unsigned(16 downto 0);
    variable ACCUMCO_v   : std_logic;
    variable XW_v        : unsigned(15 downto 0);
    variable iP_v        : unsigned(15 downto 0);
    variable Oh_v        : std_logic_vector(15 downto 0);
    variable Ol_v        : std_logic_vector(15 downto 0);
  begin
    addsubbot_rep := (others => ADDSUBBOT);
    addsubtop_rep := (others => ADDSUBTOP);

    -- BOT lower input mux (iZ in cells_sim.v)
    -- "00"→B, "01"→iG 8x8 partial (stub 0), "10"→iH[15:0], "11"→sign-ext SIGNEXTIN
    case BOTADDSUB_LOWERINPUT is
      when "10"   => iZ_v := unsigned(prod(15 downto 0));
      when "11"   => iZ_v := (others => SIGNEXTIN);
      when "01"   => iZ_v := (others => '0');  -- iG partial not modelled
      when others => iZ_v := unsigned(B);       -- "00"
    end case;

    -- BOT upper input mux (iY in cells_sim.v)
    -- '1'→D (iD), '0'→accumulator register (not modelled, zeroed)
    if BOTADDSUB_UPPERINPUT = '1' then
      iY_v := unsigned(D);
    else
      iY_v := (others => '0');
    end if;

    -- BOT carry-in (LCI in cells_sim.v)
    case BOTADDSUB_CARRYSELECT is
      when "00"   => LCI_v := '0';
      when "01"   => LCI_v := '1';
      when "10"   => LCI_v := ACCUMCI;
      when others => LCI_v := CI;
    end case;

    -- BOT adder: {LCO, YZ} = iZ + (iY ^ {16{ADDSUBBOT}}) + LCI  (cells_sim.v)
    sum17_bot := ('0' & iZ_v) + ('0' & (iY_v xor addsubbot_rep));
    if LCI_v = '1' then
      sum17_bot := sum17_bot + 1;
    end if;
    LCO_v := sum17_bot(16);
    YZ_v  := sum17_bot(15 downto 0);
    -- iR = OLOADBOT ? iD : YZ ^ {16{ADDSUBBOT}}  (OLOADBOT not modelled → always YZ path)
    iR_v  := YZ_v xor addsubbot_rep;

    -- BOT output select (Ol in cells_sim.v)
    -- "00"→iR (combinational adder), "11"→iH[15:0] (raw product bypass)
    case BOTOUTPUT_SELECT is
      when "00"   => Ol_v := std_logic_vector(iR_v);
      when "11"   => Ol_v := prod(15 downto 0);
      when others => Ol_v := (others => '0');  -- iS or iG not modelled
    end case;

    -- TOP lower input mux (iX in cells_sim.v)
    -- "00"→A, "01"→iF 8x8 partial (stub 0), "10"→iH[31:16], "11"→{16{iZ[15]}}
    case TOPADDSUB_LOWERINPUT is
      when "10"   => iX_v := unsigned(prod(31 downto 16));
      when "11"   => iX_v := (others => iZ_v(15));
      when "01"   => iX_v := (others => '0');  -- iF partial not modelled
      when others => iX_v := unsigned(A);       -- "00"
    end case;

    -- TOP upper input mux (iW in cells_sim.v)
    -- '1'→C (iC), '0'→accumulator register (not modelled, zeroed)
    if TOPADDSUB_UPPERINPUT = '1' then
      iW_v := unsigned(C);
    else
      iW_v := (others => '0');
    end if;

    -- TOP carry-in (HCI in cells_sim.v)
    case TOPADDSUB_CARRYSELECT is
      when "00"   => HCI_v := '0';
      when "01"   => HCI_v := '1';
      when "10"   => HCI_v := LCO_v;
      when others => HCI_v := LCO_v xor ADDSUBBOT;
    end case;

    -- TOP adder: {ACCUMCO, XW} = iX + (iW ^ {16{ADDSUBTOP}}) + HCI  (cells_sim.v)
    sum17_top := ('0' & iX_v) + ('0' & (iW_v xor addsubtop_rep));
    if HCI_v = '1' then
      sum17_top := sum17_top + 1;
    end if;
    ACCUMCO_v := sum17_top(16);
    XW_v      := sum17_top(15 downto 0);
    -- iP = OLOADTOP ? iC : XW ^ {16{ADDSUBTOP}}  (OLOADTOP not modelled → always XW path)
    iP_v      := XW_v xor addsubtop_rep;

    -- TOP output select (Oh in cells_sim.v)
    -- "00"→iP (combinational adder), "11"→iH[31:16] (raw product bypass)
    case TOPOUTPUT_SELECT is
      when "00"   => Oh_v := std_logic_vector(iP_v);
      when "11"   => Oh_v := prod(31 downto 16);
      when others => Oh_v := (others => '0');  -- iQ or iF not modelled
    end case;

    O          <= Oh_v & Ol_v;
    ACCUMCO    <= ACCUMCO_v;
    -- CO = ACCUMCO ^ ADDSUBTOP  (cells_sim.v)
    CO         <= ACCUMCO_v xor ADDSUBTOP;
    -- SIGNEXTOUT = iX[15]  (cells_sim.v)
    SIGNEXTOUT <= iX_v(15);
  end process;
end architecture;
