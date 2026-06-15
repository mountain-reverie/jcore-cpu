library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;
use work.test_pkg.all;

entity shifter_tap is
end shifter_tap;

architecture tb of shifter_tap is
  signal clk, rst, start, t_in, t_out, busy : std_logic := '0';
  signal a, y : std_logic_vector(31 downto 0) := (others => '0');
  signal b    : std_logic_vector(5 downto 0)  := (others => '0');
  signal op   : shiftfunc_t := logic;

  -- Encode a signed shift amount the way the datapath does: bit5 = direction
  -- (1 = right), bits4:0 = magnitude. Mirrors bshift_tap's slv(n) convention
  -- where a right shift by N is a left-rotate by (32-N) = (-N) mod 32.
  function enc(n : integer) return std_logic_vector is
    variable s : std_logic_vector(31 downto 0);
  begin
    s := std_logic_vector(to_signed(n, 32));
    return s(31) & s(4 downto 0);
  end function;
begin
  u : entity work.shifter(comb)
    port map (clk => clk, rst => rst, start => start,
              a => a, b => b, t_in => t_in, op => op,
              y => y, t_out => t_out, busy => busy);

  process
  begin
    test_plan(16, "shifter entity");
    test_comment("shifter(comb) entity: result");
    a <= x"12345678"; b <= enc(0);   t_in <= '0'; op <= arith;  wait for 1 ns;
    test_equal(y, x"12345678", "shift by 0 is identity");
    a <= x"00000001"; b <= enc(4);   t_in <= '0'; op <= arith;  wait for 1 ns;
    test_equal(y, x"00000010", "arith 1 left by 4");
    a <= x"7fffffff"; b <= enc(1);   op <= arith;               wait for 1 ns;
    test_equal(y, x"fffffffe", "arith 7fffffff left by 1");
    a <= x"80000000"; b <= enc(-1);  op <= arith;               wait for 1 ns;
    test_equal(y, x"c0000000", "arith 80000000 right by 1");
    a <= x"80000000"; b <= enc(-31); op <= arith;               wait for 1 ns;
    test_equal(y, x"ffffffff", "arith 80000000 right by 31");
    a <= x"80000000"; b <= enc(-1);  op <= logic;               wait for 1 ns;
    test_equal(y, x"40000000", "logic 80000000 right by 1");
    a <= x"80000000"; b <= enc(-31); op <= logic;               wait for 1 ns;
    test_equal(y, x"00000001", "logic 80000000 right by 31");
    a <= x"00000001"; b <= enc(31);  op <= logic;               wait for 1 ns;
    test_equal(y, x"80000000", "logic 1 left by 31");
    a <= x"f0000000"; b <= enc(1);   op <= rotate;              wait for 1 ns;
    test_equal(y, x"e0000001", "rotate f0000000 left by 1");
    a <= x"f0000000"; b <= enc(-1);  op <= rotate;              wait for 1 ns;
    test_equal(y, x"78000000", "rotate f0000000 right by 1");
    a <= x"0f000000"; b <= enc(1);   t_in <= '1'; op <= rotc;   wait for 1 ns;
    test_equal(y, x"1e000001", "rotc 0f000000 left by 1, c=1");
    a <= x"0f000000"; b <= enc(-1);  t_in <= '1'; op <= rotc;   wait for 1 ns;
    test_equal(y, x"87800000", "rotc 0f000000 right by 1, c=1");

    test_comment("shifter(comb) entity: shifted-out bit (t_out)");
    a <= x"80000000"; b <= enc(1);   t_in <= '0'; op <= logic;  wait for 1 ns;
    test_equal(t_out, '1', "t_out = MSB on left shift");
    a <= x"00000001"; b <= enc(-1);  op <= logic;               wait for 1 ns;
    test_equal(t_out, '1', "t_out = LSB on right shift");
    a <= x"00000000"; b <= enc(1);   op <= logic;               wait for 1 ns;
    test_equal(t_out, '0', "t_out = 0 when MSB clear on left shift");

    test_comment("shifter(comb) entity: never busy");
    test_equal(busy, '0', "comb shifter asserts busy = 0");

    test_finished("done");
    wait;
  end process;
end tb;
