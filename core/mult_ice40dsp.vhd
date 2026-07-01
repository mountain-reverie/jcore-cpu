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

  -- Operand halves: Al=mag_a[15:0], Ah=mag_a[31:16], Bl=mag_b[15:0], Bh=mag_b[31:16].
  -- Partial products: G=Al*Bl, K=Ah*Bl, J=Al*Bh, F=Ah*Bh.
  -- Product = G + (K+J)<<16 + F<<32. The middle term M=K+J is a 33-bit value.
  --
  -- Routable cascade (NO ACCUMCO/CO drives general fabric):
  --   DSP_K   : raw product K (routable O).
  --   DSP_J   : O_J = (J+K)[31:0] = M[31:0]; ACCUMCO_J = M[32].
  --   DSP_X   : prod=0, ACCUMCI=ACCUMCO_J (dedicated) -> O_X[0] = M[32] (routable).
  --   DSP_LOW : prod=G, C=M[15:0]; O_low = result[31:0]; ACCUMCO_low = carry@bit32.
  --   DSP_HIGH: prod=F, D=M[31:16], C=M[32], ACCUMCI=ACCUMCO_low (dedicated);
  --             O_high = result[63:32].
  -- Two dedicated ACCUMCO->ACCUMCI cascade pairs, both 32-bit-aligned (DSP_J->DSP_X
  -- and DSP_LOW->DSP_HIGH): the only legal use of the carry ports on iCE40.
  signal al, ah, bl, bh             : std_logic_vector(15 downto 0);
  signal o_g, o_k, o_j, o_x, o_high : std_logic_vector(31 downto 0);
  signal m32_c                      : std_logic_vector(15 downto 0);
  -- Cascade carries. To keep nextpnr happy the four cascaded DSPs form ONE
  -- contiguous ACCUMCO->ACCUMCI chain (J -> X -> LOW -> HIGH) so no intermediate
  -- ACCUMCO is left dangling next to another chain (which aliases the shared
  -- dsp:accumco wire). accj and acclow carry real bits; accx is a harmless 0
  -- (DSP_X's top adder never overflows) that DSP_LOW ignores functionally.
  signal accj, accx, acclow         : std_logic;

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

  -- Operand-half fan-out from the held magnitudes.
  al <= r.dec.mag_a(15 downto 0);   ah <= r.dec.mag_a(31 downto 16);
  bl <= r.dec.mag_b(15 downto 0);   bh <= r.dec.mag_b(31 downto 16);
  m32_c <= "000000000000000" & o_x(0);   -- M[32] placed at C top-input bit 0

  -- DSP_K: K = Ah*Bl, raw product on O (routable).
  DSP_K : SB_MAC16
    generic map (
      PIPELINE_16x16_MULT_REG1 => '1',
      TOPOUTPUT_SELECT => "11", BOTOUTPUT_SELECT => "11",
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1', A => ah, B => bl,
      C => (others => '0'), D => (others => '0'),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => '0',
      SIGNEXTIN => '0', O => o_k, CO => open, ACCUMCO => open,
      SIGNEXTOUT => open);

  -- DSP_J: prod=J=Al*Bh, add K (via C/D) -> O_J = M[31:0]; ACCUMCO_J = M[32].
  DSP_J : SB_MAC16
    generic map (
      PIPELINE_16x16_MULT_REG1 => '1',
      BOTOUTPUT_SELECT => "00",    TOPOUTPUT_SELECT => "00",
      BOTADDSUB_LOWERINPUT => "10", BOTADDSUB_UPPERINPUT => '1',
      BOTADDSUB_CARRYSELECT => "00",
      TOPADDSUB_LOWERINPUT => "10", TOPADDSUB_UPPERINPUT => '1',
      TOPADDSUB_CARRYSELECT => "10",
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1', A => al, B => bh,
      C => o_k(31 downto 16), D => o_k(15 downto 0),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => '0',
      SIGNEXTIN => '0', O => o_j, CO => open, ACCUMCO => accj,
      SIGNEXTOUT => open);

  -- DSP_X: prod=0, ACCUMCI=ACCUMCO_J via dedicated cascade -> O_X[0] = M[32].
  DSP_X : SB_MAC16
    generic map (
      PIPELINE_16x16_MULT_REG1 => '1',
      BOTOUTPUT_SELECT => "00",    TOPOUTPUT_SELECT => "00",
      BOTADDSUB_LOWERINPUT => "10", BOTADDSUB_UPPERINPUT => '0',
      BOTADDSUB_CARRYSELECT => "10",
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1', A => (others => '0'), B => (others => '0'),
      C => (others => '0'), D => (others => '0'),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => accj,
      -- ACCUMCO wired on to DSP_LOW.ACCUMCI so the J->X->LOW->HIGH cascade is
      -- ONE contiguous column chain: no intermediate ACCUMCO dangles to alias
      -- the shared dsp:accumco tile wire. DSP_LOW ignores this input
      -- functionally (its BOTADDSUB_CARRYSELECT="00", not "10").
      SIGNEXTIN => '0', O => o_x, CO => open, ACCUMCO => accx,
      SIGNEXTOUT => open);

  -- DSP_LOW: prod=G=Al*Bl, add M[15:0] (=o_j[15:0]) at the top half via C.
  -- O_low = result[31:0]; ACCUMCO_low = carry into bit 32.
  DSP_LOW : SB_MAC16
    generic map (
      PIPELINE_16x16_MULT_REG1 => '1',
      BOTOUTPUT_SELECT => "00",    TOPOUTPUT_SELECT => "00",
      BOTADDSUB_LOWERINPUT => "10", BOTADDSUB_UPPERINPUT => '0',
      BOTADDSUB_CARRYSELECT => "00",
      TOPADDSUB_LOWERINPUT => "10", TOPADDSUB_UPPERINPUT => '1',
      TOPADDSUB_CARRYSELECT => "10",
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1', A => al, B => bl,
      C => o_j(15 downto 0), D => (others => '0'),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => accx,
      SIGNEXTIN => '0', O => o_g, CO => open, ACCUMCO => acclow,
      SIGNEXTOUT => open);

  -- DSP_HIGH: prod=F=Ah*Bh, add M[31:16] (=o_j[31:16]) via D at bottom and
  -- M[32] (=o_x[0]) via C at top; carry-in from DSP_LOW via dedicated ACCUMCI.
  -- O_high = result[63:32].
  DSP_HIGH : SB_MAC16
    generic map (
      PIPELINE_16x16_MULT_REG1 => '1',
      BOTOUTPUT_SELECT => "00",    TOPOUTPUT_SELECT => "00",
      BOTADDSUB_LOWERINPUT => "10", BOTADDSUB_UPPERINPUT => '1',
      BOTADDSUB_CARRYSELECT => "10",
      TOPADDSUB_LOWERINPUT => "10", TOPADDSUB_UPPERINPUT => '1',
      TOPADDSUB_CARRYSELECT => "10",
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1', A => ah, B => bh,
      C => m32_c, D => o_j(31 downto 16),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => '0', ACCUMCI => acclow,
      SIGNEXTIN => '0', O => o_high, CO => open, ACCUMCO => open,
      SIGNEXTOUT => open);

  comb : process(r, slot, a, o_g, o_high)
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

    -- DONE: assemble the 64-bit magnitude product from the DSP-adder cascade
    -- outputs, then shared finalize (sign + MAC seed + saturate + write).
    if r.sstate = S_DONE then
      acc(31 downto 0)  := unsigned(o_g);     -- result[31:0]  (DSP_LOW)
      acc(63 downto 32) := unsigned(o_high);  -- result[63:32] (DSP_HIGH)
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
