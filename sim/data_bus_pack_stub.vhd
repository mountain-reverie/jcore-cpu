-- Minimal stub for data_bus_pack, providing only the types needed by cache_pkg.
library ieee;
use ieee.std_logic_1164.all;

package data_bus_pack is
  type cache_ctrl_t is record
    en  : std_logic;
    inv : std_logic;
  end record;
  constant NULL_CACHE_CTRL : cache_ctrl_t := (en => '0', inv => '0');
end package;
