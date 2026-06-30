-- J1 iCE40 DSP multiplier: architecture 'ice40dsp' of entity 'mult'.
--
-- Same port interface and observable MACH/MACL as mult(stru)/mult(seq), but the
-- product MAGNITUDE is computed by four iCE40 SB_MAC16 DSP blocks (unsigned
-- 16x16 partial products) instead of LUT logic, reclaiming the ~1200 LUT4 that
-- mult(seq) costs so the J1 SoC fits the UP5K.
--
-- It shares mult_pkg.mult_decode / mult_pkg.mult_finalize with mult(seq): the
-- ONLY difference between the two architectures is how the 64-bit magnitude
-- product is formed. mult_decode yields the sign-corrected magnitudes mag_a/
-- mag_b (positive); here  A*B = ll + ((lh+hl)<<16) + (hh<<32)  with ll/lh/hl/hh
-- the four unsigned 16x16 products of the operand halves. For 16-bit ops the
-- high halves are zero, so only ll contributes. mult_finalize then applies the
-- product sign, MAC seed and saturation, exactly as for mult(seq).
--
-- Latency is handshake-gated (busy/slot_stall held while the FSM waits
-- CALC_CYCLES >= the SB_MAC16 pipeline depth), so correctness does NOT depend
-- on the exact DSP latency. SB_MAC16 is an unbound component at synthesis
-- (yosys supplies the real cell); sim binds core/sb_mac16_sim.vhd. Mirrors
-- clkgen(ecp5)/EHXPLLL + ehxpll_sim.vhd.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mult_pkg.all;

architecture ice40dsp of mult is

  -- Hold operands this many cycles before sampling the DSP products. >= any
  -- SB_MAC16 pipeline depth (<=2). Extra cycles are harmless (operands held).
  constant CALC_CYCLES : integer := 3;

  type dsp_state_t is (S_IDLE, S_CALC, S_DONE);

  type dsp_reg_t is record
    sstate : dsp_state_t;
    dec    : mult_decode_t;
    m1     : std_logic_vector(31 downto 0);
    m2     : std_logic_vector(31 downto 0);
    mb     : std_logic_vector(31 downto 0);
    mach   : std_logic_vector(31 downto 0);
    macl   : std_logic_vector(31 downto 0);
    count  : integer range 0 to CALC_CYCLES;
  end record;

  constant DSP_RESET : dsp_reg_t := (
    sstate => S_IDLE, dec => MULT_DECODE_NOP,
    m1 => (others => '0'), m2 => (others => '0'), mb => (others => '0'),
    mach => (others => '0'), macl => (others => '0'), count => 0);

  signal r, rin : dsp_reg_t;

  type half_arr is array(0 to 3) of std_logic_vector(15 downto 0);
  type prod_arr is array(0 to 3) of std_logic_vector(31 downto 0);
  signal mac_a, mac_b : half_arr;
  signal pp           : prod_arr;

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

  y.busy       <= '1' when r.sstate /= S_IDLE else '0';
  y.slot_stall <= '1' when r.sstate /= S_IDLE else '0';
  y.mach       <= r.mach;
  y.macl       <= r.macl;

  -- Operand-half fan-out from the held magnitudes: ll, lh, hl, hh.
  mac_a(0) <= r.dec.mag_a(15 downto 0);   mac_b(0) <= r.dec.mag_b(15 downto 0);
  mac_a(1) <= r.dec.mag_a(15 downto 0);   mac_b(1) <= r.dec.mag_b(31 downto 16);
  mac_a(2) <= r.dec.mag_a(31 downto 16);  mac_b(2) <= r.dec.mag_b(15 downto 0);
  mac_a(3) <= r.dec.mag_a(31 downto 16);  mac_b(3) <= r.dec.mag_b(31 downto 16);

  gen_mac : for i in 0 to 3 generate
    u_mac : SB_MAC16
      generic map (
        PIPELINE_16x16_MULT_REG1 => '1',
        TOPOUTPUT_SELECT => "11", BOTOUTPUT_SELECT => "11",
        A_SIGNED => '0', B_SIGNED => '0')
      port map (
        CLK => clk, CE => '1', A => mac_a(i), B => mac_b(i),
        C => (others => '0'), D => (others => '0'),
        AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
        IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
        OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
        OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => '0',
        SIGNEXTIN => '0', O => pp(i), CO => open, ACCUMCO => open,
        SIGNEXTOUT => open);
  end generate;

  comb : process(r, slot, a, pp)
    variable v      : dsp_reg_t;
    variable accept : boolean;
    variable dec    : mult_decode_t;
    variable acc    : unsigned(63 downto 0);
    variable o      : mult_macout_t;
  begin
    v := r;

    -- Operand / accumulator load (identical to mult(seq)).
    accept := (r.sstate = S_IDLE) and (slot = '1') and (a.command /= NOP);
    if slot = '1' then
      if a.command /= NOP then
        v.m2 := a.in2;
        if a.command = MACL or a.command = MACW then
          v.mb := r.m1;
        end if;
      end if;
      if a.wr_m1 = '1' then
        v.m1 := a.in1;
      end if;
    end if;
    if slot = '1' and a.wr_mach = '1' then
      v.mach := a.in1;
    end if;
    if slot = '1' and a.wr_macl = '1' then
      v.macl := a.in2;
    end if;

    -- Command acceptance: shared decode; hold magnitudes for the DSP.
    if accept then
      dec := mult_decode(a.command, a.s, v.m1, v.mb, v.m2);
      v.dec    := dec;
      v.sstate := S_CALC;
      v.count  := CALC_CYCLES;
      if dec.clr_mach = '1' then v.mach := (others => '0'); end if;
      if dec.clr_macl = '1' then v.macl := (others => '0'); end if;
    end if;

    -- CALC: hold the magnitudes on the DSP inputs while the SB_MAC16 pipeline
    -- fills. Steps every clock (slot is frozen by slot_stall, as in seq's RUN).
    if r.sstate = S_CALC then
      if r.count = 0 then
        v.sstate := S_DONE;
      else
        v.count := r.count - 1;
      end if;
    end if;

    -- DONE: assemble the 64-bit magnitude product from the four DSP partial
    -- products, then shared finalize (sign + MAC seed + saturate + write).
    if r.sstate = S_DONE then
      acc := resize(unsigned(pp(0)), 64)
           + shift_left(resize(unsigned(pp(1)), 64), 16)
           + shift_left(resize(unsigned(pp(2)), 64), 16)
           + shift_left(resize(unsigned(pp(3)), 64), 32);
      o := mult_finalize(r.dec, acc, r.mach, r.macl);
      v.mach    := o.mach;
      v.macl    := o.macl;
      v.sstate  := S_IDLE;
      v.dec.cmd := NOP;
    end if;

    rin <= v;
  end process;

  reg : process(clk, rst)
  begin
    if rst = '1' then
      r <= DSP_RESET;
    elsif rising_edge(clk) then
      r <= rin;
    end if;
  end process;

end ice40dsp;
