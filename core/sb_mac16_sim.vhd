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

entity sb_mac16 is
  generic (
    neg_trigger              : std_logic                    := '0';
    c_reg                    : std_logic                    := '0';
    a_reg                    : std_logic                    := '0';
    b_reg                    : std_logic                    := '0';
    d_reg                    : std_logic                    := '0';
    top_8x8_mult_reg         : std_logic                    := '0';
    bot_8x8_mult_reg         : std_logic                    := '0';
    pipeline_16x16_mult_reg1 : std_logic                    := '0';
    pipeline_16x16_mult_reg2 : std_logic                    := '0';
    topoutput_select         : std_logic_vector(1 downto 0) := "00";
    topaddsub_lowerinput     : std_logic_vector(1 downto 0) := "00";
    topaddsub_upperinput     : std_logic                    := '0';
    topaddsub_carryselect    : std_logic_vector(1 downto 0) := "00";
    botoutput_select         : std_logic_vector(1 downto 0) := "00";
    botaddsub_lowerinput     : std_logic_vector(1 downto 0) := "00";
    botaddsub_upperinput     : std_logic                    := '0';
    botaddsub_carryselect    : std_logic_vector(1 downto 0) := "00";
    mode_8x8                 : std_logic                    := '0';
    a_signed                 : std_logic                    := '0';
    b_signed                 : std_logic                    := '0'
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
end entity sb_mac16;

architecture behave of sb_mac16 is

  -- iH: registered 16x16 product (PIPELINE_16x16_MULT_REG1 path)
  signal prod : std_logic_vector(31 downto 0) := (others => '0');

begin

  process (clk) is
  begin

    if rising_edge(clk) then
      if (ce = '1') then
        prod <= std_logic_vector(unsigned(a) * unsigned(b));
      end if;
    end if;

  end process;

  -- Combinational BOT/TOP adder stage, transcribed from yosys cells_sim.v.
  -- Variable names iZ/iY/LCI/LCO/YZ/iR/iX/iW/HCI/XW/iP match cells_sim.v.
  -- The xor-with-replicated-ADDSUB form matches cells_sim.v even when ADDSUB='0'.
  -- Accumulator registers (iS/iQ in cells_sim.v) are zeroed — not modelled.
  process (prod, a, b, c, d, ci, accumci, signextin, addsubbot, addsubtop) is

    variable iz_v          : unsigned(15 downto 0);
    variable iy_v          : unsigned(15 downto 0);
    variable addsubbot_rep : unsigned(15 downto 0);
    variable addsubtop_rep : unsigned(15 downto 0);
    variable lci_v         : std_logic;
    variable sum17_bot     : unsigned(16 downto 0);
    variable lco_v         : std_logic;
    variable yz_v          : unsigned(15 downto 0);
    variable ir_v          : unsigned(15 downto 0);
    variable ix_v          : unsigned(15 downto 0);
    variable iw_v          : unsigned(15 downto 0);
    variable hci_v         : std_logic;
    variable sum17_top     : unsigned(16 downto 0);
    variable accumco_v     : std_logic;
    variable xw_v          : unsigned(15 downto 0);
    variable ip_v          : unsigned(15 downto 0);
    variable oh_v          : std_logic_vector(15 downto 0);
    variable ol_v          : std_logic_vector(15 downto 0);

  begin

    addsubbot_rep := (others => addsubbot);
    addsubtop_rep := (others => addsubtop);

    -- BOT lower input mux (iZ in cells_sim.v)
    -- "00"→B, "01"→iG 8x8 partial (stub 0), "10"→iH[15:0], "11"→sign-ext SIGNEXTIN
    case botaddsub_lowerinput is

      when "10" =>

        iz_v := unsigned(prod(15 downto 0));

      when "11" =>

        iz_v := (others => signextin);

      when "01" =>

        iz_v := (others => '0');                                  -- iG partial not modelled

      when others =>

        iz_v := unsigned(b);                                      -- "00"

    end case;

    -- BOT upper input mux (iY in cells_sim.v)
    -- '1'→D (iD), '0'→accumulator register (not modelled, zeroed)
    if (botaddsub_upperinput = '1') then
      iy_v := unsigned(d);
    else
      iy_v := (others => '0');
    end if;

    -- BOT carry-in (LCI in cells_sim.v)
    case botaddsub_carryselect is

      when "00" =>

        lci_v := '0';

      when "01" =>

        lci_v := '1';

      when "10" =>

        lci_v := accumci;

      when others =>

        lci_v := ci;

    end case;

    -- BOT adder: {LCO, YZ} = iZ + (iY ^ {16{ADDSUBBOT}}) + LCI  (cells_sim.v)
    sum17_bot := ('0' & iz_v) + ('0' & (iy_v xor addsubbot_rep));

    if (lci_v = '1') then
      sum17_bot := sum17_bot + 1;
    end if;

    lco_v := sum17_bot(16);
    yz_v  := sum17_bot(15 downto 0);
    -- iR = OLOADBOT ? iD : YZ ^ {16{ADDSUBBOT}}  (OLOADBOT not modelled → always YZ path)
    ir_v := yz_v xor addsubbot_rep;

    -- BOT output select (Ol in cells_sim.v)
    -- "00"→iR (combinational adder), "11"→iH[15:0] (raw product bypass)
    case botoutput_select is

      when "00" =>

        ol_v := std_logic_vector(ir_v);

      when "11" =>

        ol_v := prod(15 downto 0);

      when others =>

        ol_v := (others => '0');                                  -- iS or iG not modelled

    end case;

    -- TOP lower input mux (iX in cells_sim.v)
    -- "00"→A, "01"→iF 8x8 partial (stub 0), "10"→iH[31:16], "11"→{16{iZ[15]}}
    case topaddsub_lowerinput is

      when "10" =>

        ix_v := unsigned(prod(31 downto 16));

      when "11" =>

        ix_v := (others => iZ_v(15));

      when "01" =>

        ix_v := (others => '0');                                  -- iF partial not modelled

      when others =>

        ix_v := unsigned(a);                                      -- "00"

    end case;

    -- TOP upper input mux (iW in cells_sim.v)
    -- '1'→C (iC), '0'→accumulator register (not modelled, zeroed)
    if (topaddsub_upperinput = '1') then
      iw_v := unsigned(c);
    else
      iw_v := (others => '0');
    end if;

    -- TOP carry-in (HCI in cells_sim.v)
    case topaddsub_carryselect is

      when "00" =>

        hci_v := '0';

      when "01" =>

        hci_v := '1';

      when "10" =>

        hci_v := lco_v;

      when others =>

        hci_v := lco_v xor addsubbot;

    end case;

    -- TOP adder: {ACCUMCO, XW} = iX + (iW ^ {16{ADDSUBTOP}}) + HCI  (cells_sim.v)
    sum17_top := ('0' & ix_v) + ('0' & (iw_v xor addsubtop_rep));

    if (hci_v = '1') then
      sum17_top := sum17_top + 1;
    end if;

    accumco_v := sum17_top(16);
    xw_v      := sum17_top(15 downto 0);
    -- iP = OLOADTOP ? iC : XW ^ {16{ADDSUBTOP}}  (OLOADTOP not modelled → always XW path)
    ip_v := xw_v xor addsubtop_rep;

    -- TOP output select (Oh in cells_sim.v)
    -- "00"→iP (combinational adder), "11"→iH[31:16] (raw product bypass)
    case topoutput_select is

      when "00" =>

        oh_v := std_logic_vector(ip_v);

      when "11" =>

        oh_v := prod(31 downto 16);

      when others =>

        oh_v := (others => '0');                                  -- iQ or iF not modelled

    end case;

    o       <= oh_v & ol_v;
    accumco <= accumco_v;
    -- CO = ACCUMCO ^ ADDSUBTOP  (cells_sim.v)
    co <= accumco_v xor addsubtop;
    -- SIGNEXTOUT = iX[15]  (cells_sim.v)
    signextout <= iX_v(15);

  end process;

end architecture behave;
