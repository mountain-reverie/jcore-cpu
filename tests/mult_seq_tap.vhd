-- Busy-aware TAP testbench for the J1 sequential multiplier, mult(seq),
-- the J2 array multiplier mult(stru), and the iCE40 DSP multiplier mult(ice40dsp).
--
-- The original tests/mult_tap.vhd samples MACH/MACL at a FIXED short delay
-- and never waits on busy.  That is fine for the single-cycle pipelined J2
-- 'stru' architecture, but it CANNOT verify a genuinely sequential engine
-- that takes ~32 cycles and asserts busy throughout -- the sample would land
-- in the middle of the computation.
--
-- This testbench instead drives the same operands and commands that
-- mult_tap uses, then for each operation:
--   1. issues the command,
--   2. waits for mac_o.busy to go HIGH (computation started),
--   3. waits while mac_o.busy = '1' (counting cycles, to prove it is slow),
--   4. once busy falls, samples MACH/MACL and checks against the expected
--      product (the same expected constants mult_tap uses).
--
-- All three architectures are instantiated (direct entity binding, so each is
-- bound unambiguously regardless of analysis order) and driven by the SAME
-- stimulus.  Every functional vector is checked against the golden constants on
-- seq, stru, AND ice40dsp; the saturating MAC.W cases cross-check all three
-- against the stru oracle.  So this one busy-aware harness validates all three
-- mult units from a single stimulus.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;
use work.test_pkg.all;
use work.mult_pkg.all;

entity mult_seq_tap is
end mult_seq_tap;

architecture tb of mult_seq_tap is

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal slot : std_logic;

  shared variable ENDSIM : boolean := false;

  signal mac_i : mult_i_t;
  signal mac_o : mult_o_t;

  -- Second multiplier instance: the J2 'stru' architecture, used as the ORACLE
  -- for the saturating (S-bit) MAC.W cross-check below.  It is driven by the
  -- SAME stimulus bus (mac_i) so its MACH/MACL must match the sequential one.
  signal mac_o_ref : mult_o_t;

  -- Third multiplier instance: iCE40 DSP architecture (SB_MAC16 partial products).
  signal mac_o_dsp : mult_o_t;

  procedure test_mult(actualh    : std_logic_vector(31 downto 0);
                      actuall    : std_logic_vector(31 downto 0);
                      expectedh  : std_logic_vector(31 downto 0);
                      expectedl  : std_logic_vector(31 downto 0);
                      description : string := "";
                      directive   : string := "") is
    variable okh : boolean := actualh = expectedh;
    variable okl : boolean := actuall = expectedl;
    variable ok  : boolean := okh and okl;
  begin
    test_ok(ok, description, directive);
    if not okh then
      test_comment("MACH fail");
    end if;
    if not okl then
      test_comment("MACL fail");
    end if;
  end procedure;

  -- Wait for a multiply to finish: first wait until busy rises (the FSM has
  -- accepted the command), then count clock edges while busy stays high.
  -- Returns the number of clocks busy was asserted via the shared report.
  procedure run_to_completion(signal clk_s   : in  std_logic;
                              signal busy_s   : in  std_logic;
                              description : string) is
    variable cycles : integer := 0;
  begin
    -- Wait for busy to assert (skip if it never goes high -- shouldn't happen).
    if busy_s = '0' then
      wait until busy_s = '1' for 100 ns;
    end if;
    -- Count rising clock edges while busy is high.
    while busy_s = '1' loop
      wait until rising_edge(clk_s);
      cycles := cycles + 1;
    end loop;
    test_comment(description & " busy cycles = " & integer'image(cycles));
    assert cycles > 8
      report description & ": expected a sequential (slow) multiply (>8 busy cycles), got "
             & integer'image(cycles)
      severity warning;
  end procedure;

begin

  clk_gen : process
  begin
    if ENDSIM = false then
      clk <= '0';
      wait for 5 ns;
      clk <= '1';
      wait for 5 ns;
    else
      wait;
    end if;
  end process;

  -- Direct entity instantiation: unambiguously the sequential architecture.
  mult_i : entity work.mult(seq)
    port map (clk => clk, rst => rst, slot => slot, a => mac_i, y => mac_o);

  -- The J2 array multiplier (stru) bound explicitly as the saturating oracle.
  mult_ref : entity work.mult(stru)
    port map (clk => clk, rst => rst, slot => slot, a => mac_i, y => mac_o_ref);

  -- The iCE40 DSP multiplier (ice40dsp) bound explicitly.
  dsp_dut : entity work.mult(ice40dsp)
    port map (clk => clk, rst => rst, slot => slot, a => mac_i, y => mac_o_dsp);

  process
  begin

    -- 7 functional vectors checked on ALL THREE architectures (seq + stru + ice40dsp)
    -- against the golden constants (21), plus 5 saturating cross-checks on all three
    -- against the stru oracle (15 but only the 5 seq+stru pairs were original; adding
    -- 5 dsp cross-checks) = 31 total.
    test_plan(31, "Mult seq+stru+ice40dsp (busy-aware)");

    -- Bypass a lot of logic, same as mult_tap.
    mac_i.s       <= '0';
    mac_i.acc_squash <= '0';  -- precise-exception MAC squash (MMU_ARCH); '0' = normal accumulate
    mac_i.wr_mach <= '0';
    mac_i.wr_macl <= '0';

    mac_i.command <= NOP;
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"fffffffe";
    mac_i.in2     <= x"00005555";
    slot          <= '0';

    wait for 10 ns;
    rst  <= '0';
    slot <= '1';
    wait until rising_edge(clk);

    -------------------------------------------------------------- DMULS.L
    mac_i.command <= DMULSL;
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "DMULS.L");
    test_mult(mac_o.mach, mac_o.macl, x"ffffffff", x"ffff5556", "test DMULS.L (seq)");
    test_mult(mac_o_ref.mach, mac_o_ref.macl, x"ffffffff", x"ffff5556", "test DMULS.L (stru)");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, x"ffffffff", x"ffff5556", "test DMULS.L (ice40dsp)");

    -------------------------------------------------------------- DMULU.L
    mac_i.command <= DMULUL;
    mac_i.wr_m1   <= '1';
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "DMULU.L");
    test_mult(mac_o.mach, mac_o.macl, x"00005554", x"ffff5556", "test DMULU.L (seq)");
    test_mult(mac_o_ref.mach, mac_o_ref.macl, x"00005554", x"ffff5556", "test DMULU.L (stru)");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, x"00005554", x"ffff5556", "test DMULU.L (ice40dsp)");

    -------------------------------------------------------------- MUL.L
    mac_i.command <= MULL;
    mac_i.wr_m1   <= '1';
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "MUL.L");
    test_equal(mac_o.macl, x"ffff5556", "test MUL.L (seq)");
    test_equal(mac_o_ref.macl, x"ffff5556", "test MUL.L (stru)");
    test_equal(mac_o_dsp.macl, x"ffff5556", "test MUL.L (ice40dsp)");

    -------------------------------------------------------------- MULS.W
    mac_i.command <= MULSW;
    mac_i.wr_m1   <= '1';
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "MULS.W");
    test_equal(mac_o.macl, x"ffff5556", "test MULS.W (seq)");
    test_equal(mac_o_ref.macl, x"ffff5556", "test MULS.W (stru)");
    test_equal(mac_o_dsp.macl, x"ffff5556", "test MULS.W (ice40dsp)");

    -------------------------------------------------------------- MULU.W
    mac_i.command <= MULUW;
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00000002";
    mac_i.in2     <= x"ffffaaaa";
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "MULU.W");
    test_equal(mac_o.macl, x"00015554", "test MULU.W (seq)");
    test_equal(mac_o_ref.macl, x"00015554", "test MULU.W (stru)");
    test_equal(mac_o_dsp.macl, x"00015554", "test MULU.W (ice40dsp)");

    -------------------------------------------------------------- MAC.W
    -- Load m1 first (one slot), then issue MAC.W with the second operand.
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00000003";
    wait until rising_edge(clk);
    mac_i.command <= MACW;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"00000002";
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.W");
    test_equal(mac_o.macl, x"0001555a", "test MAC.W (seq)");
    test_equal(mac_o_ref.macl, x"0001555a", "test MAC.W (stru)");
    test_equal(mac_o_dsp.macl, x"0001555a", "test MAC.W (ice40dsp)");

    -------------------------------------------------------------- MAC.L
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"7fffffff";
    wait until rising_edge(clk);
    mac_i.command <= MACL;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"7fffffff";
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.L");
    test_mult(mac_o.mach, mac_o.macl, x"40005553", x"0001555B", "test MAC.L (seq)");
    test_mult(mac_o_ref.mach, mac_o_ref.macl, x"40005553", x"0001555B", "test MAC.L (stru)");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, x"40005553", x"0001555B", "test MAC.L (ice40dsp)");

    --------------------------------------------------------------------
    -- SATURATE32 cross-check: drive identical saturating MAC.W (s='1')
    -- sequences into BOTH mult(seq) and mult(stru) and require the
    -- sequential engine to reproduce the J2 array multiplier's MACH/MACL.
    -- The J2 'stru' is the oracle, so no hand-computed constants are needed.
    --
    -- Each case:
    --   1. seed MACH:MACL on both engines via wr_mach/wr_macl,
    --   2. load m1 (multiplicand),
    --   3. issue MAC.W with s='1' (multiplier in in2),
    --   4. wait for the slow seq engine to finish (stru is long done),
    --   5. compare seq MACH/MACL == stru MACH/MACL.
    --------------------------------------------------------------------

    -- Case A: NEGATIVE prior MACL, small positive product -> NO overflow.
    --   prior MACL = 0x80000001, MAC.W of 1 x 1.  The old (buggy) seq path
    --   zero-extended the negative MACL and wrongly saturated to 0x7fffffff
    --   with a MACH-bit-0 carry; stru keeps it sign-correct.
    mac_i.s       <= '1';
    mac_i.wr_mach <= '1';
    mac_i.wr_macl <= '1';
    mac_i.in1     <= x"00000000";   -- MACH seed
    mac_i.in2     <= x"80000001";   -- MACL seed (negative)
    wait until rising_edge(clk);
    mac_i.wr_mach <= '0';
    mac_i.wr_macl <= '0';
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00000001";   -- multiplicand
    wait until rising_edge(clk);
    mac_i.command <= MACW;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"00000001";   -- multiplier
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.W S neg-no-ovf");
    test_mult(mac_o.mach, mac_o.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS negative MACL, no overflow");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS negative MACL, no overflow (ice40dsp)");

    -- Case B: POSITIVE overflow clamp.
    --   prior MACL = 0x7fffffff (max positive), add a positive product
    --   (0x4000 x 0x4000 = 0x10000000) -> must clamp to P32MAX and set the
    --   MACH bit-0 carry.
    mac_i.wr_mach <= '1';
    mac_i.wr_macl <= '1';
    mac_i.in1     <= x"00000000";
    mac_i.in2     <= x"7fffffff";
    wait until rising_edge(clk);
    mac_i.wr_mach <= '0';
    mac_i.wr_macl <= '0';
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00004000";
    wait until rising_edge(clk);
    mac_i.command <= MACW;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"00004000";
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.W S pos-ovf");
    test_mult(mac_o.mach, mac_o.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS positive overflow clamp + MACH carry");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS positive overflow clamp + MACH carry (ice40dsp)");

    -- Case C: NEGATIVE overflow clamp.
    --   prior MACL = 0x80000000 (max negative), add a negative product
    --   (0x4000 x -0x4000 = -0x10000000) -> must clamp to N32MAX.
    mac_i.wr_mach <= '1';
    mac_i.wr_macl <= '1';
    mac_i.in1     <= x"00000000";
    mac_i.in2     <= x"80000000";
    wait until rising_edge(clk);
    mac_i.wr_mach <= '0';
    mac_i.wr_macl <= '0';
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00004000";   -- +0x4000
    wait until rising_edge(clk);
    mac_i.command <= MACW;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"ffffc000";   -- -0x4000
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.W S neg-ovf");
    test_mult(mac_o.mach, mac_o.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS negative overflow clamp");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS negative overflow clamp (ice40dsp)");

    -- Case D: NEGATIVE accumulator, negative product, NO overflow.
    --   prior MACL = 0xffff0000, add (-0x4000) x (0x2) = -0x8000 ->
    --   0xfffe8000, stays negative, no saturation.  Reproduces the
    --   reviewer's 0xbfff8000-style negative-accumulate case.
    mac_i.wr_mach <= '1';
    mac_i.wr_macl <= '1';
    mac_i.in1     <= x"00000000";
    mac_i.in2     <= x"ffff0000";
    wait until rising_edge(clk);
    mac_i.wr_mach <= '0';
    mac_i.wr_macl <= '0';
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"ffffc000";   -- -0x4000
    wait until rising_edge(clk);
    mac_i.command <= MACW;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"00000002";   -- +2
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.W S neg-acc");
    test_mult(mac_o.mach, mac_o.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS negative accumulator, no overflow");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS negative accumulator, no overflow (ice40dsp)");

    -- Case E: MACH carry-out preservation.
    --   prior MACH = 0xa5a5a5a4 (bit 0 clear), prior MACL = 0x7fffffff,
    --   positive overflow.  On saturation stru ORs MACH bit 0; the upper
    --   MACH bits must be preserved -> expect 0xa5a5a5a5.
    mac_i.wr_mach <= '1';
    mac_i.wr_macl <= '1';
    mac_i.in1     <= x"a5a5a5a4";
    mac_i.in2     <= x"7fffffff";
    wait until rising_edge(clk);
    mac_i.wr_mach <= '0';
    mac_i.wr_macl <= '0';
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00004000";
    wait until rising_edge(clk);
    mac_i.command <= MACW;
    mac_i.wr_m1   <= '0';
    mac_i.in2     <= x"00004000";
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    run_to_completion(clk, mac_o.busy, "MAC.W S mach-carry");
    test_mult(mac_o.mach, mac_o.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS MACH bit-0 carry preserves high bits");
    test_mult(mac_o_dsp.mach, mac_o_dsp.macl, mac_o_ref.mach, mac_o_ref.macl,
              "xchk MACWS MACH bit-0 carry preserves high bits (ice40dsp)");

    test_finished("done");

    wait for 40 ns;
    ENDSIM := true;
    wait;
  end process;

end tb;
