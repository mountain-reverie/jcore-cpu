-- Correctness gate for core/dsp_arith.vhd: proves the SB_MAC16-based
-- dsp_arith entity produces IDENTICAL results to components_pkg.arith_unit
-- (the reference J2/J4/sim ALU function) for every vector tested, bit for
-- bit across all 33 result bits.  This is a measurement/correctness
-- prototype: vectors are NOT weakened or dropped to force a pass.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.cpu2j0_components_pack.all;
use work.test_pkg.all;

entity dsp_arith_tap is
end dsp_arith_tap;

architecture tb of dsp_arith_tap is
  signal clk    : std_logic := '0';
  signal a, b   : std_logic_vector(31 downto 0) := (others => '0');
  signal is_sub : std_logic := '0';
  signal ci     : std_logic := '0';
  signal result : std_logic_vector(32 downto 0);

  shared variable ENDSIM : boolean := false;

  component dsp_arith is
    port (
      clk    : in  std_logic;
      a      : in  std_logic_vector(31 downto 0);
      b      : in  std_logic_vector(31 downto 0);
      is_sub : in  std_logic;
      ci     : in  std_logic;
      result : out std_logic_vector(32 downto 0));
  end component;

begin

  clkgen : process begin
    while not ENDSIM loop
      clk <= '0'; wait for 5 ns; clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  dut : dsp_arith
    port map (clk => clk, a => a, b => b, is_sub => is_sub, ci => ci, result => result);

  stim : process
    variable func : arith_func_t;
    variable exp  : std_logic_vector(32 downto 0);
    variable n_tests : integer := 0;

    function to_bit_sl(x : boolean) return std_logic is
    begin
      if x then return '1'; else return '0'; end if;
    end function;

    procedure check(av, bv : std_logic_vector(31 downto 0);
                     f : arith_func_t; civ : std_logic; tag : string) is
    begin
      a <= av; b <= bv; is_sub <= to_bit_sl(f = SUB); ci <= civ;
      wait for 1 ns;
      exp := arith_unit(av, bv, f, civ);
      n_tests := n_tests + 1;
      test_ok(result = exp, "dsp_arith " & tag);
      if result /= exp then
        test_comment_fail(result, exp);
      end if;
    end procedure;

    -- Randomized/swept coverage on top of the directed corner cases below.
    variable seed1 : integer := 42;
    variable seed2 : integer := 4321;
    variable rnd   : real;
    variable rav, rbv : std_logic_vector(31 downto 0);
    variable rci  : std_logic;
    variable rfunc : arith_func_t;
  begin
    test_plan(24 + 4*64, "dsp_arith vs arith_unit");

    test_comment("directed corners, ADD");
    check(x"00000000", x"00000000", ADD, '0', "0+0");
    check(x"00000000", x"00000000", ADD, '1', "0+0+1");
    check(x"ffffffff", x"00000001", ADD, '0', "0xffffffff+1");
    check(x"ffffffff", x"ffffffff", ADD, '0', "0xffffffff+0xffffffff");
    check(x"ffffffff", x"ffffffff", ADD, '1', "0xffffffff+0xffffffff+1");
    check(x"7fffffff", x"00000001", ADD, '0', "0x7fffffff+1");
    check(x"80000000", x"80000000", ADD, '0', "0x80000000+0x80000000");
    check(x"80000000", x"ffffffff", ADD, '1', "0x80000000+0xffffffff+1");

    test_comment("directed corners, SUB");
    check(x"00000000", x"00000000", SUB, '0', "0-0");
    check(x"00000000", x"00000000", SUB, '1', "0-0-1");
    check(x"00000000", x"00000001", SUB, '0', "0-1 (borrow)");
    check(x"80000000", x"00000001", SUB, '0', "0x80000000-1");
    check(x"7fffffff", x"80000000", SUB, '0', "0x7fffffff-0x80000000");
    check(x"7fffffff", x"7fffffff", SUB, '0', "0x7fffffff-0x7fffffff");
    check(x"7fffffff", x"7fffffff", SUB, '1', "0x7fffffff-0x7fffffff-1");
    check(x"ffffffff", x"ffffffff", SUB, '0', "0xffffffff-0xffffffff");
    check(x"ffffffff", x"ffffffff", SUB, '1', "0xffffffff-0xffffffff-1");
    check(x"00000001", x"00000000", SUB, '1', "1-0-1 (exact zero carry boundary)");

    test_comment("carry/borrow boundary sweep across the 16-bit DSP split");
    check(x"0000ffff", x"00000001", ADD, '0', "low-half carry into high half (ADD)");
    check(x"00010000", x"00000001", SUB, '0', "borrow across 16-bit boundary (SUB)");
    check(x"0000ffff", x"00000001", SUB, '0', "0x0000ffff-1 (no borrow across boundary)");
    check(x"00010000", x"00000000", SUB, '1', "borrow across boundary via ci");
    check(x"ffff0000", x"00010000", ADD, '0', "high-half only carry");
    check(x"7fff8000", x"00008000", ADD, '0', "mid-word carry chain");

    -- Randomized sweep: 64 iterations over ADD and SUB, ci=0/1 each --
    -- 4*64 = 256 additional vectors.
    test_comment("randomized sweep");
    for i in 0 to 63 loop
      -- Build each 32-bit vector from two 16-bit random halves to stay
      -- within 32-bit signed integer range (avoids overflow in to_unsigned).
      uniform(seed1, seed2, rnd);
      rav(31 downto 16) := std_logic_vector(to_unsigned(integer(rnd * 65535.0), 16));
      uniform(seed1, seed2, rnd);
      rav(15 downto 0)  := std_logic_vector(to_unsigned(integer(rnd * 65535.0), 16));
      uniform(seed1, seed2, rnd);
      rbv(31 downto 16) := std_logic_vector(to_unsigned(integer(rnd * 65535.0), 16));
      uniform(seed1, seed2, rnd);
      rbv(15 downto 0)  := std_logic_vector(to_unsigned(integer(rnd * 65535.0), 16));
      check(rav, rbv, ADD, '0', "rand ADD ci=0 #" & integer'image(i));
      check(rav, rbv, ADD, '1', "rand ADD ci=1 #" & integer'image(i));
      check(rav, rbv, SUB, '0', "rand SUB ci=0 #" & integer'image(i));
      check(rav, rbv, SUB, '1', "rand SUB ci=1 #" & integer'image(i));
    end loop;

    test_finished("done");
    ENDSIM := true;
    wait;
  end process;
end tb;
