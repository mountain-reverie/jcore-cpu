library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cache_pack.all;
use work.memory_pack.all;
use work.cache_clkmode.all;

entity dcache_ram is port (
   clk125 : in  std_logic;
   clk200 : in  std_logic;
   rst : in  std_logic;
   ra  : in  dcache_ram_i_t;
   ry  : out dcache_ram_o_t);
end dcache_ram;

architecture beh of dcache_ram is

signal tag_we0 : std_logic_vector( 2 downto 0);
signal tag_dr0 : std_logic_vector(23 downto 0);
signal tag_dw0 : std_logic_vector(23 downto 0);
signal tag_dr1 : std_logic_vector(23 downto 0);

begin

   tag0 : ram_1rw
    generic map (
     SUBWORD_WIDTH => 8,
     SUBWORD_NUM => 3,
     ADDR_WIDTH => 8)
    port map(
     rst => rst,
     clk => clk125,
     en  => ra.ten0,
     wr  => ra.twr0,
     we  => tag_we0,
     a   => ra.ta0,
     dw  => tag_dw0,                           -- 24 b => 5 b & 19 b
     dr  => tag_dr0,
     margin => "000" );

   tag1 : ram_1rw
    generic map (
     SUBWORD_WIDTH => 8,
     SUBWORD_NUM => 3,
     ADDR_WIDTH => 8)
    port map(
     rst => rst,
     clk => clk125,
     en  => ra.ten0,
     wr  => ra.twr0,
     we  => tag_we0,
     a   => ra.ta1,
     dw  => tag_dw0,                           -- 24 b => 5 b & 19 b
     dr  => tag_dr1,
     margin => "000" );

   tag_we0 <= ra.twr0 & ra.twr0 & ra.twr0;
   tag_dw0 <= "00000" & ra.tag0;
   ry.tag0 <= tag_dr0(18 downto 0);            -- 19 b => 24 b ( 19 b range)
   ry.tag1 <= tag_dr1(18 downto 0);            -- 19 b => 24 b ( 19 b range)

   -- Data RAM. Two write sources: port0 = CPU store (CCL, clk125), port1 = line
   -- refill (MCL, clk200). They are provably mutually exclusive per cycle (the
   -- blocking FSM forces wr0=0 while a refill is in flight), but a CPU load
   -- (port0 read) can occur concurrently with a refill (port1 write) on a
   -- different index (hit-under-miss). Two forms, selected by cache_clkmode:
   --
   --  * CACHE_SAME_CLOCK=false (true dual-clock ASIC): keep the 2-write-port
   --    dual-clock RAM (port0 RW on clk125, port1 W on clk200). The tech/sim
   --    model is a true two-clock memory; this is the form dcache_tb exercises.
   --
   --  * CACHE_SAME_CLOCK=true (single-clock FPGA, and the asic CI proxy): collapse
   --    to a simple-dual-port 1R+1W so FPGA block RAM (ECP5 DP16KD, iCE40 EBR,
   --    Xilinx/Intel) infers it. port0 is read-only (CPU loads); the single write
   --    port (port1) is muxed between refill and CPU store. Read is suppressed on
   --    store cycles (en0 = en0 and not wr0) so dr0 holds across a store, matching
   --    the 2-write-port form where a store wrote (not read) port0.
   ram : for i in 0 to 1 generate
     dc : if not CACHE_SAME_CLOCK generate
       ram_s : ram_2rw
       generic map (
       SUBWORD_WIDTH => 8,
       SUBWORD_NUM => 2,
       ADDR_WIDTH => 11)
       port map(
       rst0 => rst, clk0 => clk125,
       en0  => ra.en0,
       wr0  => ra.wr0,
       we0  => ra.we0( 2 * i +  1 downto  2 * i),
       a0   => ra.a0,
       dw0  => ra.d0 (16 * i + 15 downto 16 * i),
       dr0  => ry.d0 (16 * i + 15 downto 16 * i),
       rst1 => rst, clk1 => clk200,
       en1  => ra.en1,
       wr1  => ra.wr1,
       we1  => ra.we1( 2 * i +  1 downto  2 * i),
       a1   => ra.a1,
       dw1  => ra.d1 (16 * i + 15 downto 16 * i),
       dr1  => open,
       margin0 => '0',
       margin1 => '0' );
     end generate;

     sc : if CACHE_SAME_CLOCK generate
       -- single write port = mux(refill : CPU store). refill active <=> wr1='1'.
       signal r_en : std_logic;   -- port0 read enable (no read on a store)
       signal w_en : std_logic;
       signal w_wr : std_logic;
       signal w_we : std_logic_vector(1 downto 0);
       signal w_a  : std_logic_vector(ra.a0'range);
       signal w_d  : std_logic_vector(15 downto 0);
     begin
       r_en <= ra.en0 and not ra.wr0;
       w_en <= ra.en1                          when ra.wr1 = '1' else ra.en0;
       w_wr <= ra.wr1                          when ra.wr1 = '1' else ra.wr0;
       w_we <= ra.we1(2 * i + 1 downto 2 * i)  when ra.wr1 = '1'
               else ra.we0(2 * i + 1 downto 2 * i);
       w_a  <= ra.a1                           when ra.wr1 = '1' else ra.a0;
       w_d  <= ra.d1(16 * i + 15 downto 16 * i) when ra.wr1 = '1'
               else ra.d0(16 * i + 15 downto 16 * i);

       ram_s : ram_2rw
       generic map (
       SUBWORD_WIDTH => 8,
       SUBWORD_NUM => 2,
       ADDR_WIDTH => 11)
       port map(
       -- port0: read-only (CPU loads); no read on a store so dr0 holds (matches dc)
       rst0 => rst, clk0 => clk125,
       en0  => r_en,
       wr0  => '0',
       we0  => b"00",
       a0   => ra.a0,
       dw0  => x"0000",
       dr0  => ry.d0 (16 * i + 15 downto 16 * i),
       -- port1: the sole write port (refill or CPU store). clk1 tied to clk125.
       rst1 => rst, clk1 => clk125,
       en1  => w_en,
       wr1  => w_wr,
       we1  => w_we,
       a1   => w_a,
       dw1  => w_d,
       dr1  => open,
       margin0 => '0',
       margin1 => '0' );
     end generate;
   end generate;

end beh;
