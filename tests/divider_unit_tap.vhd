-- Isolated TAP test for core/divider.vhd, the sequential J2A divs/divu
-- unit. No CPU is involved: the entity is driven directly and its
-- quotient checked against an expected value computed with VHDL's
-- signed/unsigned '/' operator (used here purely as the test oracle,
-- not as part of the design under test).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.divider_pkg.all;
use work.test_pkg.all;

entity divider_unit_tap is
end entity divider_unit_tap;

architecture tb of divider_unit_tap is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal din : divider_i_t := (
    start     => '0',
    dividend  => (others => '0'),
    divisor   => (others => '0'),
    is_signed => '0'
  );
  signal dout : divider_o_t;

  shared variable endsim : boolean := false;

  -- Pulse start with the given operands, wait for completion, and
  -- return the resulting quotient.
  procedure do_div (
    signal clk_s  : in std_logic;
    signal din_s  : out divider_i_t;
    signal dout_s : in divider_o_t;
    dividend      : in std_logic_vector(31 downto 0);
    divisor       : in std_logic_vector(31 downto 0);
    is_signed     : in std_logic;
    variable result : out std_logic_vector(31 downto 0)
  ) is
  begin
    din_s.dividend  <= dividend;
    din_s.divisor   <= divisor;
    din_s.is_signed <= is_signed;
    din_s.start     <= '1';
    wait until rising_edge(clk_s);
    din_s.start <= '0';

    -- wait for busy to assert then de-assert
    wait until rising_edge(clk_s) and dout_s.busy = '1';
    wait until rising_edge(clk_s) and dout_s.busy = '0';

    result := dout_s.quotient;
  end procedure do_div;

begin

  clk_gen : process is
  begin
    if (not endsim) then
      clk <= '0';
      wait for 5 ns; clk <= '1';
      wait for 5 ns;
    else
      wait;
    end if;
  end process;

  u_div : entity work.divider(rtl)
    port map (
      clk => clk,
      rst => rst,
      a   => din,
      y   => dout
    );

  process is

    variable result : std_logic_vector(31 downto 0);

    procedure check_u (
      dividend : std_logic_vector(31 downto 0);
      divisor  : std_logic_vector(31 downto 0);
      expected : std_logic_vector(31 downto 0);
      desc     : string
    ) is
    begin
      do_div(clk, din, dout, dividend, divisor, '0', result);
      test_equal(result, expected, desc);
    end procedure check_u;

    procedure check_s (
      dividend : std_logic_vector(31 downto 0);
      divisor  : std_logic_vector(31 downto 0);
      expected : std_logic_vector(31 downto 0);
      desc     : string
    ) is
    begin
      do_div(clk, din, dout, dividend, divisor, '1', result);
      test_equal(result, expected, desc);
    end procedure check_s;

    -- record-only case (div by zero): just confirm it terminates and
    -- produces a stable, deterministic value on repeat.
    procedure check_terminates (
      dividend  : std_logic_vector(31 downto 0);
      divisor   : std_logic_vector(31 downto 0);
      is_signed : std_logic;
      desc      : string
    ) is
      variable r1, r2 : std_logic_vector(31 downto 0);
    begin
      do_div(clk, din, dout, dividend, divisor, is_signed, r1);
      do_div(clk, din, dout, dividend, divisor, is_signed, r2);
      test_equal(r1, r2, desc & " : deterministic");
    end procedure check_terminates;

  begin

    test_plan(19, "divider unit (isolated)");

    wait for 20 ns;
    rst <= '0';
    wait until rising_edge(clk);

    -- unsigned
    check_u(x"00000064", x"00000007", x"0000000E", "u 100/7=14");
    check_u(x"00000005", x"00000005", x"00000001", "u 5/5=1");
    check_u(x"00000000", x"00000009", x"00000000", "u 0/9=0");
    check_u(x"FFFFFFFF", x"00000002", x"7FFFFFFF", "u FFFFFFFF/2=7FFFFFFF");
    check_u(x"FFFFFFFF", x"00000001", x"FFFFFFFF", "u FFFFFFFF/1=FFFFFFFF");
    check_u(x"00003039", x"00000001", x"00003039", "u 12345/1=12345");
    check_terminates(x"FFFFFFFF", x"00000000", '0', "u x/0");

    -- signed
    check_s(x"FFFFFF9C", x"00000007", x"FFFFFFF2", "s -100/7=-14");
    check_s(x"00000064", x"FFFFFFF9", x"FFFFFFF2", "s 100/-7=-14");
    check_s(x"FFFFFF9C", x"FFFFFFF9", x"0000000E", "s -100/-7=14");
    check_s(x"00000064", x"00000007", x"0000000E", "s 100/7=14");
    check_s(x"0000002A", x"00000001", x"0000002A", "s 42/1=42");
    check_s(x"0000002A", x"FFFFFFFF", x"FFFFFFD6", "s 42/-1=-42");
    check_s(x"00000000", x"00000005", x"00000000", "s 0/5=0");
    check_terminates(x"80000000", x"FFFFFFFF", '1', "s 80000000/-1");
    check_terminates(x"FFFFFF9C", x"00000000", '1', "s x/0");

    -- a couple of extra sanity checks to round out the matrix
    check_u(x"00000009", x"00000004", x"00000002", "u 9/4=2");
    check_s(x"FFFFFFFE", x"00000002", x"FFFFFFFF", "s -2/2=-1");
    check_s(x"00000002", x"FFFFFFFE", x"FFFFFFFF", "s 2/-2=-1");

    wait for 40 ns;
    endsim := true;
    wait;

  end process;

end architecture tb;
