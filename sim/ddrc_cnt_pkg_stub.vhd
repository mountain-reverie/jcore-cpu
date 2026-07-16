-- SIM-ONLY minimal shim of ddrc_cnt_pack.
-- Provides only ddr_status_o_t, used transitively by cache_pack (cache/cache_pkg.vhd).
-- The real package $(JCORE_SOC)/components/ddr2/ddrc_cnt_pkg.vhd drags in work.config,
-- which is not available in the cpu sim build, so this shim is justified.
-- ddr_status_o_t MUST stay in sync with the real definition at
-- $(JCORE_SOC)/components/ddr2/ddrc_cnt_pkg.vhd lines ~133-136.

library ieee;
  use ieee.std_logic_1164.all;

package ddrc_cnt_pack is

  type ddr_status_o_t is record
    status0 : std_logic_vector(7 downto 0);
    dummy1  : std_logic;
  end record ddr_status_o_t;

  constant null_ddr_status : ddr_status_o_t := ((others => '0'), '0');

end package ddrc_cnt_pack;
