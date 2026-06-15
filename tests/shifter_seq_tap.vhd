-- Busy-aware TAP for the J1 sequential shifter, shifter(seq).
-- shifter(comb) (the proven barrel) is the ORACLE: both are driven by the
-- same stimulus, and seq's busy-gated result must match comb's combinational
-- result for every vector. Mirrors tests/mult_seq_tap.vhd.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;
use work.test_pkg.all;

entity shifter_seq_tap is
end shifter_seq_tap;

architecture tb of shifter_seq_tap is
  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal start : std_logic := '0';
  signal sel   : std_logic := '0';
  signal t_in  : std_logic := '0';
  signal a     : std_logic_vector(31 downto 0) := (others => '0');
  signal b     : std_logic_vector(5 downto 0)  := (others => '0');
  signal op    : shiftfunc_t := logic;
  signal y_seq, y_cmb : std_logic_vector(31 downto 0);
  signal t_seq, t_cmb, busy : std_logic;
  shared variable ENDSIM : boolean := false;

  function enc(n : integer) return std_logic_vector is
    variable s : std_logic_vector(31 downto 0);
  begin
    s := std_logic_vector(to_signed(n, 32));
    return s(31) & s(4 downto 0);
  end function;

  -- Issue one shift on seq, wait for it to finish, and check seq==comb.
  procedure do_shift(signal clk_s : in std_logic; signal busy_s : in std_logic;
                     signal start_s, sel_s : out std_logic;
                     signal ys, yc : in std_logic_vector(31 downto 0);
                     signal ts, tc : in std_logic;
                     desc : string) is
    variable cyc : integer := 0;
  begin
    start_s <= '1'; sel_s <= '1';
    wait until rising_edge(clk_s);
    while busy_s = '1' loop
      wait until rising_edge(clk_s);
      cyc := cyc + 1;
    end loop;
    test_equal(ys, yc, desc & " : y == comb");
    test_ok(ts = tc, desc & " : t_out == comb");
    start_s <= '0'; sel_s <= '0';
    wait until rising_edge(clk_s);
  end procedure;
begin
  clk_gen : process begin
    if not ENDSIM then clk <= '0'; wait for 5 ns; clk <= '1'; wait for 5 ns;
    else wait; end if;
  end process;

  u_seq : entity work.shifter(seq) port map (
    clk => clk, rst => rst, start => start, sel => sel,
    a => a, b => b, t_in => t_in, op => op,
    y => y_seq, t_out => t_seq, busy => busy);
  u_cmb : entity work.shifter(comb) port map (
    clk => clk, rst => rst, start => '0', sel => '0',
    a => a, b => b, t_in => t_in, op => op,
    y => y_cmb, t_out => t_cmb, busy => open);

  process
    type vec_t is record op : shiftfunc_t; a : std_logic_vector(31 downto 0); n : integer; end record;
    type vecs_t is array (natural range <>) of vec_t;
    constant V : vecs_t := (
      (arith,  x"00000001",  4), (arith,  x"7fffffff",  1),
      (arith,  x"80000000", -1), (arith,  x"80000000", -31),
      (logic,  x"80000000", -1), (logic,  x"80000000", -31),
      (logic,  x"00000001", 31), (logic,  x"12345678",  8),
      (logic,  x"12345678", -8), (logic,  x"00ff00ff", 16),
      (logic,  x"ffff0000", -16),(arith,  x"deadbeef", -8),
      (rotate, x"f0000000",  1), (rotate, x"f0000000", -1),
      (rotc,   x"0f000000",  1), (rotc,   x"0f000000", -1),
      (logic,  x"abcdef01",  2), (logic,  x"abcdef01", -2),
      (arith,  x"00000000",  0), (logic,  x"a5a5a5a5",  0),
      -- gap coverage (review): right-by-32 (count=32, mag5=0/dir=right via
      -- enc(-32)), count=2 boundary for arith both directions, and a
      -- multi-step rotate (exercises the rotate RUN path, not just the 1-bit op).
      (logic,  x"80000000", -32), (arith,  x"ffffffff", -32),
      (arith,  x"deadbeef", -30), (arith,  x"00000001",  2),
      (rotate, x"deadbeef",  4) );
  begin
    test_plan(2 * V'length, "shifter seq vs comb (busy-aware)");
    wait for 12 ns; rst <= '0'; wait until rising_edge(clk);
    for i in V'range loop
      a <= V(i).a; b <= enc(V(i).n); op <= V(i).op;
      if V(i).op = rotc then t_in <= '1'; else t_in <= '0'; end if;
      wait until rising_edge(clk);
      do_shift(clk, busy, start, sel, y_seq, y_cmb, t_seq, t_cmb,
               "vec " & integer'image(i));
    end loop;
    test_finished("done");
    wait for 40 ns; ENDSIM := true; wait;
  end process;
end tb;
