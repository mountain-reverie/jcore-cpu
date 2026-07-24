library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.divider_pkg.all;

-- Self-contained sequential 32/32 -> 32 divider (unsigned and signed),
-- for J2A DIVS/DIVU support. This is a plain restoring-division FSM
-- operating on operand magnitudes; it has no dependency on the shared
-- datapath/SR types and is testable in complete isolation from the CPU
-- (see tests/divider_unit_tap.vhd).
--
-- Latency: pulse 'start' for one cycle; 'busy' goes high on the next
-- cycle and stays high for 32 step cycles plus one finalize cycle, then
-- drops with 'quotient' valid on the cycle busy falls.

entity divider is
  port (
    clk : in    std_logic;
    rst : in    std_logic;
    a   : in    divider_i_t;
    y   : out   divider_o_t
  );
end entity divider;

architecture rtl of divider is

  function negate (
    v : std_logic_vector
  ) return std_logic_vector is
  begin

    return std_logic_vector(unsigned(not v) + 1);

  end function negate;

  signal busy_r       : std_logic                     := '0';
  signal sign_r       : std_logic                     := '0';
  signal divisor_r    : std_logic_vector(31 downto 0) := (others => '0');
  signal combined_r   : std_logic_vector(63 downto 0) := (others => '0');
  signal steps_left_r : natural range 0 to 32         := 0;
  signal quotient_r   : std_logic_vector(31 downto 0) := (others => '0');

begin

  y.busy     <= busy_r;
  y.quotient <= quotient_r;

  process (clk, rst) is

    variable dividend_abs : std_logic_vector(31 downto 0);
    variable divisor_abs  : std_logic_vector(31 downto 0);
    variable shifted      : std_logic_vector(63 downto 0);
    variable rem_cand     : std_logic_vector(31 downto 0);

  begin

    if (rst = '1') then
      busy_r       <= '0';
      sign_r       <= '0';
      divisor_r    <= (others => '0');
      combined_r   <= (others => '0');
      steps_left_r <= 0;
      quotient_r   <= (others => '0');
    elsif rising_edge(clk) then
      if (busy_r = '0') then
        if (a.start = '1') then
          if (a.is_signed = '1') then
            sign_r <= a.dividend(31) xor a.divisor(31);
            if (a.dividend(31) = '1') then
              dividend_abs := negate(a.dividend);
            else
              dividend_abs := a.dividend;
            end if;
            if (a.divisor(31) = '1') then
              divisor_abs := negate(a.divisor);
            else
              divisor_abs := a.divisor;
            end if;
          else
            sign_r       <= '0';
            dividend_abs := a.dividend;
            divisor_abs  := a.divisor;
          end if;

          combined_r   <= (63 downto 32 => '0') & dividend_abs;
          divisor_r    <= divisor_abs;
          steps_left_r <= 32;
          busy_r       <= '1';
        end if;
      else
        if (steps_left_r = 0) then
          if (sign_r = '1') then
            quotient_r <= negate(combined_r(31 downto 0));
          else
            quotient_r <= combined_r(31 downto 0);
          end if;
          busy_r <= '0';
        else
          shifted  := combined_r(62 downto 0) & '0';
          rem_cand := shifted(63 downto 32);
          if (unsigned(rem_cand) >= unsigned(divisor_r)) then
            rem_cand   := std_logic_vector(unsigned(rem_cand) - unsigned(divisor_r));
            shifted(0) := '1';
          else
            shifted(0) := '0';
          end if;
          shifted(63 downto 32) := rem_cand;
          combined_r            <= shifted;
          steps_left_r          <= steps_left_r - 1;
        end if;
      end if;
    end if;

  end process;

end architecture rtl;
