library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_pack.all;
use work.data_bus_pack.all;
use work.cache_pack.all;

entity dcache_check_tb is end entity;

architecture tb of dcache_check_tb is
  signal clk125, clk200, rst : std_logic := '0';
  signal done : boolean := false;

  signal ctrl   : cache_ctrl_t := (en => '1', inv => '0');
  signal ibus_o : cpu_data_o_t := NULL_DATA_O;
  signal ibus_i : cpu_data_i_t;
  signal snpc_i : dcache_snoop_io_t := NULL_SNOOP_IO;
  signal snpc_o : dcache_snoop_io_t;
  signal dbus_o : cpu_data_o_t;
  signal dbus_i : cpu_data_i_t := (d => (others => '0'), ack => '0');
  signal dbus_lock, dbus_ddrburst, dbus_ack_r : std_logic := '0';
begin
  clk125 <= not clk125 after 4 ns when not done else '0';
  clk200 <= clk125;
  rst    <= '1', '0' after 15 ns;

  dut : entity work.dcache_adapter
    port map (clk125 => clk125, clk200 => clk200, rst => rst,
              ctrl => ctrl, ibus_o => ibus_o, lock => '0', ibus_i => ibus_i,
              snpc_o => snpc_o, snpc_i => snpc_i,
              dbus_o => dbus_o, dbus_lock => dbus_lock,
              dbus_ddrburst => dbus_ddrburst,
              dbus_i => dbus_i, dbus_ack_r => dbus_ack_r);

  stim : process
  begin
    wait until rst = '0';
    for i in 0 to 9 loop wait until rising_edge(clk125); end loop;
    report "dcache_check_tb: skeleton OK (no scenarios yet)" severity note;
    done <= true;
    wait;
  end process;
end architecture;
