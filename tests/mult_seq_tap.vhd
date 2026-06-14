-- Busy-aware TAP testbench for the J1 sequential multiplier, mult(seq).
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
-- It uses a direct entity instantiation of work.mult(seq), so the sequential
-- architecture is bound unambiguously regardless of analysis order (no
-- reliance on which architecture happens to be the "default" for 'mult').

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

  process
  begin

    test_plan(7, "Mult seq (busy-aware)");

    -- Bypass a lot of logic, same as mult_tap.
    mac_i.s       <= '0';
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
    test_mult(mac_o.mach, mac_o.macl, x"ffffffff", x"ffff5556", "test DMULS.L");

    -------------------------------------------------------------- DMULU.L
    mac_i.command <= DMULUL;
    mac_i.wr_m1   <= '1';
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "DMULU.L");
    test_mult(mac_o.mach, mac_o.macl, x"00005554", x"ffff5556", "test DMULU.L");

    -------------------------------------------------------------- MUL.L
    mac_i.command <= MULL;
    mac_i.wr_m1   <= '1';
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "MUL.L");
    test_equal(mac_o.macl, x"ffff5556", "test MUL.L");

    -------------------------------------------------------------- MULS.W
    mac_i.command <= MULSW;
    mac_i.wr_m1   <= '1';
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "MULS.W");
    test_equal(mac_o.macl, x"ffff5556", "test MULS.W");

    -------------------------------------------------------------- MULU.W
    mac_i.command <= MULUW;
    mac_i.wr_m1   <= '1';
    mac_i.in1     <= x"00000002";
    mac_i.in2     <= x"ffffaaaa";
    wait until rising_edge(clk);
    mac_i.command <= NOP;
    mac_i.wr_m1   <= '0';
    run_to_completion(clk, mac_o.busy, "MULU.W");
    test_equal(mac_o.macl, x"00015554", "test MULU.W");

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
    test_equal(mac_o.macl, x"0001555a", "test MAC.W");

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
    test_mult(mac_o.mach, mac_o.macl, x"40005553", x"0001555B", "test MAC.L");

    test_finished("done");

    wait for 40 ns;
    ENDSIM := true;
    wait;
  end process;

end tb;
