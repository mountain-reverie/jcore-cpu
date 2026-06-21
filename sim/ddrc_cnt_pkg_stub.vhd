-- Minimal stub for ddrc_cnt_pack, providing only the types needed by cache_pkg.
library ieee;
use ieee.std_logic_1164.all;

package ddrc_cnt_pack is
  type ddr_status_o_t is record
    status0 : std_logic_vector(7 downto 0);
    dummy1  : std_logic;
  end record;
  constant NULL_DDR_STATUS : ddr_status_o_t := ( (others => '0'), '0' );
end package;
