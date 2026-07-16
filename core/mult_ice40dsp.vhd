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
  constant calc_cycles : integer := 3;

  type dsp_state_t is (s_idle, s_calc, s_done);

  type dsp_reg_t is record
    sstate : dsp_state_t;
    dec    : mult_decode_t;
    m1     : std_logic_vector(31 downto 0);
    m2     : std_logic_vector(31 downto 0);
    mb     : std_logic_vector(31 downto 0);
    mach   : std_logic_vector(31 downto 0);
    macl   : std_logic_vector(31 downto 0);
    count  : integer range 0 to calc_cycles;
  end record dsp_reg_t;

  constant dsp_reset : dsp_reg_t :=
  (
    sstate => s_idle,
    dec    => MULT_DECODE_NOP,
    m1     => (others => '0'),
    m2     => (others => '0'),
    mb     => (others => '0'),
    mach   => (others => '0'),
    macl   => (others => '0'),
    count  => 0
  );

  signal r, rin : dsp_reg_t;

  -- Operand halves: Al=mag_a[15:0], Ah=mag_a[31:16], Bl=mag_b[15:0], Bh=mag_b[31:16].
  -- Partial products: G=Al*Bl, K=Ah*Bl, J=Al*Bh, F=Ah*Bh.
  -- Product = G + (K+J)<<16 + F<<32.  M=K+J is a 33-bit value.
  --
  -- IMPORTANT (iCE40 UP5K, verified in icebox chipdb-5k.txt): the 8 SB_MAC16
  -- sites sit at X in {0,25}, Y-base in {5,10,15,23}, each spanning 4 tiles with
  -- GAPS between blocks -- they are NEVER vertically adjacent. The ACCUMCI/ACCUMCO
  -- carry wires are tile-local to a single SB_MAC16 (its own accumulator loop),
  -- so an inter-DSP ACCUMCO->ACCUMCI cascade is physically unroutable here
  -- (nextpnr aborts: "dsp:accumco used as source and sink in different nets").
  -- Likewise ACCUMCO/CO cannot drive fabric. So EVERY inter-DSP carry is captured
  -- in a routable O[16] bit (a DSP whose top adder computes 0+0+LCO puts the
  -- bottom-adder carry in O[16]) and re-injected into the next DSP via routable
  -- C/D/CI inputs. No ACCUMCO/ACCUMCI/CO dedicated DSP-cascade wire is used
  -- anywhere (CI is a routable general fabric input, not the cascade carry).
  --
  -- Column carry-propagate (16-bit columns c0..c3), all inside DSP adders:
  --   result[15:0]  = G[15:0]                              (o_g[15:0])
  --   result[31:16] = G[31:16] + M[15:0]        -> cB      (DSP_C1  bottom)
  --   result[47:32] = F[15:0]  + M[31:16] + cB  -> cC      (DSP_C23 bottom)
  --   result[63:48] = F[31:16] + M[32]    + cC             (DSP_C23 top)
  -- M=K+J is formed by DSP_KJLO (K's product + J[15:0], with K[31:16]+Slo[16] in
  -- its top half) and DSP_MHI (that + J[31:16], carry-captured -> M[32]=o_mhi[16]).
  signal al     : std_logic_vector(15 downto 0);
  signal ah     : std_logic_vector(15 downto 0);
  signal bl     : std_logic_vector(15 downto 0);
  signal bh     : std_logic_vector(15 downto 0);
  signal o_g    : std_logic_vector(31 downto 0);
  signal o_f    : std_logic_vector(31 downto 0);
  signal o_j    : std_logic_vector(31 downto 0); -- raw products G,F,J
  signal o_kjlo : std_logic_vector(31 downto 0); -- [15:0]=M[15:0]; [31:16]=K[31:16]+Slo[16]
  signal o_mhi  : std_logic_vector(31 downto 0); -- [15:0]=M[31:16]; [16]=M[32]
  signal o_c1   : std_logic_vector(31 downto 0); -- [15:0]=result[31:16]; [16]=cB
  signal o_c23  : std_logic_vector(31 downto 0); -- [15:0]=result[47:32]; [31:16]=result[63:48]
  signal m32_d  : std_logic_vector(15 downto 0); -- {0..0, M[32]} for DSP_C23 top C

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

  y.busy       <= '1' when r.sstate /= s_idle else
                  '0';
  y.slot_stall <= '1' when r.sstate /= s_idle else
                  '0';
  y.mach       <= r.mach;
  y.macl       <= r.macl;

  -- Operand-half fan-out from the held magnitudes.
  al    <= r.dec.mag_a(15 downto 0);   ah <= r.dec.mag_a(31 downto 16);
  bl    <= r.dec.mag_b(15 downto 0);   bh <= r.dec.mag_b(31 downto 16);
  m32_d <= "000000000000000" & o_mhi(16); -- M[32] as a 16-bit input for DSP_C23 top C

  -- DSP_G: G = Al*Bl, raw product on O (routable).
  dsp_g : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      topoutput_select         => "11", botoutput_select => "11",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => al,
      b          => bl,
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
      o          => o_g,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- DSP_F: F = Ah*Bh, raw product on O (routable).
  dsp_f : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      topoutput_select         => "11", botoutput_select => "11",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => ah,
      b          => bh,
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
      o          => o_f,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- DSP_J: J = Al*Bh, raw product on O (routable).
  dsp_j : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      topoutput_select         => "11", botoutput_select => "11",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => al,
      b          => bh,
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
      o          => o_j,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- DSP_KJLO: prod=K=Ah*Bl.  bottom = K[15:0] + J[15:0] -> o_kjlo[15:0]=M[15:0],
  -- carry Slo[16] into the top.  top = K[31:16] + 0 + Slo[16] -> o_kjlo[31:16]
  -- (= K[31:16]+Slo[16], never overflows so its ACCUMCO is 0 and left open).
  dsp_kjlo : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      botoutput_select         => "00",    topoutput_select => "00",
      botaddsub_lowerinput     => "10", botaddsub_upperinput => '1',
      botaddsub_carryselect    => "00",
      topaddsub_lowerinput     => "10", topaddsub_upperinput => '0',
      topaddsub_carryselect    => "10",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => ah,
      b          => bl,
      c          => (others => '0'),
      d          => o_j(15 downto 0),
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
      o          => o_kjlo,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- DSP_MHI: pure adder (no product used).  bottom = o_kjlo[31:16] + J[31:16]
  -- = Shi -> o_mhi[15:0]=M[31:16], carry Shi[16]=M[32] captured in o_mhi[16]
  -- (top = 0 + 0 + LCO).  iZ=B via LOWERINPUT="00".
  dsp_mhi : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      botoutput_select         => "00",    topoutput_select => "00",
      botaddsub_lowerinput     => "00", botaddsub_upperinput => '1',
      botaddsub_carryselect    => "00",
      topaddsub_lowerinput     => "00", topaddsub_upperinput => '0',
      topaddsub_carryselect    => "10",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => (others => '0'),
      b          => o_kjlo(31 downto 16),
      c          => (others => '0'),
      d          => o_j(31 downto 16),
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
      o          => o_mhi,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- DSP_C1: pure adder.  bottom = G[31:16] + M[15:0] -> o_c1[15:0]=result[31:16],
  -- carry cB captured in o_c1[16] (top = 0 + 0 + LCO).
  dsp_c1 : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      botoutput_select         => "00",    topoutput_select => "00",
      botaddsub_lowerinput     => "00", botaddsub_upperinput => '1',
      botaddsub_carryselect    => "00",
      topaddsub_lowerinput     => "00", topaddsub_upperinput => '0',
      topaddsub_carryselect    => "10",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => (others => '0'),
      b          => o_g(31 downto 16),
      c          => (others => '0'),
      d          => o_kjlo(15 downto 0),
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
      o          => o_c1,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- DSP_C23: pure adder, both columns.  bottom = F[15:0] + M[31:16] + cB(via CI)
  -- -> o_c23[15:0]=result[47:32], carry cC=LCO into top.  top = F[31:16] + M[32]
  -- + cC -> o_c23[31:16]=result[63:48] (never overflows; ACCUMCO=0, open).
  dsp_c23 : component sb_mac16
    generic map (
      pipeline_16x16_mult_reg1 => '1',
      botoutput_select         => "00",    topoutput_select => "00",
      botaddsub_lowerinput     => "00", botaddsub_upperinput => '1',
      botaddsub_carryselect    => "11",
      topaddsub_lowerinput     => "00", topaddsub_upperinput => '1',
      topaddsub_carryselect    => "10",
      a_signed                 => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => o_f(31 downto 16),
      b          => o_f(15 downto 0),
      c          => m32_d,
      d          => o_mhi(15 downto 0),
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
      ci         => o_c1(16),
      accumci    => '0',
      signextin  => '0',
      o          => o_c23,
      co         => open,
      accumco    => open,
      signextout => open
    );

  comb : process (r, slot, a, o_g, o_c1, o_c23) is

    variable v      : dsp_reg_t;
    variable accept : boolean;
    variable dec    : mult_decode_t;
    variable acc    : unsigned(63 downto 0);
    variable o      : mult_macout_t;

  begin

    v := r;

    -- Operand / accumulator load (identical to mult(seq)).
    accept := (r.sstate = s_idle) and (slot = '1') and (a.command /= NOP);

    if (slot = '1') then
      if (a.command /= NOP) then
        v.m2 := a.in2;
        if (a.command = MACL or a.command = MACW) then
          v.mb := r.m1;
        end if;
      end if;
      if (a.wr_m1 = '1') then
        v.m1 := a.in1;
      end if;
    end if;

    if (slot = '1' and a.wr_mach = '1') then
      v.mach := a.in1;
    end if;

    if (slot = '1' and a.wr_macl = '1') then
      v.macl := a.in2;
    end if;

    -- Command acceptance: shared decode; hold magnitudes for the DSP.
    if (accept) then
      dec      := mult_decode(a.command, a.s, v.m1, v.mb, v.m2);
      v.dec    := dec;
      v.sstate := s_calc;
      v.count  := calc_cycles;
      if (dec.clr_mach = '1') then
        v.mach := (others => '0');
      end if;
      if (dec.clr_macl = '1') then
        v.macl := (others => '0');
      end if;
    end if;

    -- CALC: hold the magnitudes on the DSP inputs while the SB_MAC16 pipeline
    -- fills. Steps every clock (slot is frozen by slot_stall, as in seq's RUN).
    if (r.sstate = s_calc) then
      if (r.count = 0) then
        v.sstate := s_done;
      else
        v.count := r.count - 1;
      end if;
    end if;

    -- DONE: assemble the 64-bit magnitude product from the DSP-adder cascade
    -- outputs, then shared finalize (sign + MAC seed + saturate + write).
    if (r.sstate = s_done) then
      acc(15 downto 0)  := unsigned(o_g(15 downto 0));                     -- result[15:0]
      acc(31 downto 16) := unsigned(o_c1(15 downto 0));                    -- result[31:16]
      acc(47 downto 32) := unsigned(o_c23(15 downto 0));                   -- result[47:32]
      acc(63 downto 48) := unsigned(o_c23(31 downto 16));                  -- result[63:48]
      o                 := mult_finalize(r.dec, acc, r.mach, r.macl);
      v.mach            := o.mach;
      v.macl            := o.macl;
      v.sstate          := s_idle;
      v.dec.cmd         := NOP;
    end if;

    rin <= v;

  end process comb;

  reg : process (clk, rst) is
  begin

    if (rst = '1') then
      r <= dsp_reset;
    elsif rising_edge(clk) then
      r <= rin;
    end if;

  end process reg;

end architecture ice40dsp;
