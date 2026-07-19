library ieee;
use ieee.std_logic_1164.all;

-- Self-contained sequential 32/32 divider unit (J2A divs/divu support).
-- This package only defines the port records; the unit has no dependency
-- on the shared datapath/SR types so it can be developed and tested in
-- isolation from the CPU.

package divider_pkg is

  type divider_i_t is record
    start     : std_logic;                     -- 1-cycle pulse to begin
    dividend  : std_logic_vector(31 downto 0);  -- Rn
    divisor   : std_logic_vector(31 downto 0);  -- R0
    is_signed : std_logic;                      -- 1 = divs, 0 = divu
  end record divider_i_t;

  type divider_o_t is record
    busy     : std_logic;                       -- high from start until done
    quotient : std_logic_vector(31 downto 0);    -- valid when busy falls
  end record divider_o_t;

end package divider_pkg;
