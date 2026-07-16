library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cache_pack.all;
  use work.memory_pack.all;

entity icache_ram is
  port (
    clk125 : in    std_logic;
    clk200 : in    std_logic;
    rst    : in    std_logic;
    ra     : in    icache_ram_i_t;
    ry     : out   icache_ram_o_t
  );
end entity icache_ram;

architecture beh of icache_ram is

  signal tag_we  : std_logic_vector( 1 downto 0);
  signal tag_dr  : std_logic_vector(15 downto 0);
  signal tag_dw  : std_logic_vector(15 downto 0);
  signal ram_we1 : std_logic_vector( 1 downto 0);

begin

  tag : component ram_1rw
    generic map (
      subword_width => 8,
      subword_num   => 2,
      addr_width    => 8
    )
    port map (
      rst    => rst,
      clk    => clk125,
      en     => ra.ten,
      wr     => ra.twr,
      we     => tag_we,
      a      => ra.ta,
      dw     => tag_dw,
      dr     => tag_dr,
      margin => "00"
    );

  tag_we <= ra.twr & ra.twr;
  tag_dw <= "0" & ra.tag;
  ry.tag <= tag_dr(14 downto 0); -- 15 b (PA[27:13], 28-bit region)

  ram : for i in 0 to 1 generate

    ram_s : component ram_2rw
      generic map (
        subword_width => 8,
        subword_num   => 2,
        addr_width    => 11
      )
      port map (
        rst0    => rst,
        clk0    => clk125,
        en0     => ra.en0,
        wr0     => '0',
        we0     => b"00",
        a0      => ra.a0,
        dw0     => x"0000",
        dr0     => ry.d0 (16 * i + 15 downto 16 * i),
        rst1    => rst,
        clk1    => clk200,
        en1     => ra.en1,
        wr1     => ra.wr1,
        we1     => ram_we1,
        a1      => ra.a1,
        dw1     => ra.d1 (16 * i + 15 downto 16 * i),
        dr1     => open,
        margin0 => '0',
        margin1 => '0'
      );

  end generate ram;

  ram_we1 <= ra.wr1 & ra.wr1;

end architecture beh;
