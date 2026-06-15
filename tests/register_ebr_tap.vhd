-- Cross-check TAP for the J1 block-RAM register file, register_file(ebr).
-- register_file(flops) (async-read, proven) is the ORACLE: both are driven by
-- identical stimulus and ebr's falling-edge-read result, sampled late in the
-- slot, must match flops for every read port every cycle. Mirrors
-- tests/shifter_seq_tap.vhd.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;
use work.test_pkg.all;

entity register_ebr_tap is
end register_ebr_tap;

architecture tb of register_ebr_tap is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal slot : std_logic := '0';

  signal addr_ra, addr_rb, w_addr_wb, w_addr_ex : std_logic_vector(4 downto 0)
    := (others => '0');
  signal din_wb, din_ex : std_logic_vector(31 downto 0) := (others => '0');
  signal we_wb, we_ex : std_logic := '0';

  -- ebr (DUT) and flops (oracle) outputs
  signal a_e, b_e, z_e : std_logic_vector(31 downto 0);
  signal a_f, b_f, z_f : std_logic_vector(31 downto 0);

  shared variable ENDSIM : boolean := false;

  type stim_t is record
    ra  : std_logic_vector(4 downto 0);
    rb  : std_logic_vector(4 downto 0);
    ewb : std_logic;
    awb : std_logic_vector(4 downto 0);
    dwb : std_logic_vector(31 downto 0);
    eex : std_logic;
    aex : std_logic_vector(4 downto 0);
    dex : std_logic_vector(31 downto 0);
  end record;
  type stim_arr is array(natural range <>) of stim_t;

  -- Coverage: WB write then read same/next cycle (W-bus forwarding + RAM),
  -- EX writes drained through the 3-stage pipe then read at +1/+2/+3/+4
  -- (ex_pipes forwarding paths and finally the RAM), reg0 writes/reads, and
  -- simultaneous distinct read/write ports.
  constant S : stim_arr := (
    -- ra      rb      ewb awb     dwb            eex aex     dex
    ("00001","00000", '1',"00001",x"11111111", '0',"00000",x"00000000"),
    ("00001","00010", '1',"00010",x"22222222", '0',"00000",x"00000000"),
    ("00010","00001", '0',"00000",x"00000000", '1',"00011",x"33333333"),
    ("00011","00010", '0',"00000",x"00000000", '1',"00100",x"44444444"),
    ("00011","00100", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00100","00011", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00100","00001", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00000","00000", '1',"00000",x"aaaaaaaa", '0',"00000",x"00000000"),
    ("00000","00000", '0',"00000",x"00000000", '1',"00000",x"bbbbbbbb"),
    ("00000","00101", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00101","00000", '1',"00101",x"55555555", '1',"00110",x"66666666"),
    ("00110","00101", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00110","00001", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00001","00010", '1',"00111",x"77777777", '0',"00000",x"00000000"),
    ("00111","00110", '0',"00000",x"00000000", '0',"00000",x"00000000"),
    ("00111","00101", '0',"00000",x"00000000", '0',"00000",x"00000000"));

  procedure check(signal ae, af, be, bf, ze, zf : in std_logic_vector(31 downto 0);
                  desc : string) is
  begin
    test_equal(ae, af, desc & " : dout_a == flops");
    test_equal(be, bf, desc & " : dout_b == flops");
    test_equal(ze, zf, desc & " : dout_0 == flops");
  end procedure;
begin
  clk_gen : process begin
    if not ENDSIM then clk <= '0'; wait for 5 ns; clk <= '1'; wait for 5 ns;
    else wait; end if;
  end process;

  dut : entity work.register_file(ebr)
    generic map (ADDR_WIDTH => 5, NUM_REGS => 16, REG_WIDTH => 32)
    port map (clk => clk, rst => rst, ce => slot,
      addr_ra => addr_ra, dout_a => a_e, addr_rb => addr_rb, dout_b => b_e,
      dout_0 => z_e, we_wb => we_wb, w_addr_wb => w_addr_wb, din_wb => din_wb,
      we_ex => we_ex, w_addr_ex => w_addr_ex, din_ex => din_ex, wr_data_o => open);

  oracle : entity work.register_file(flops)
    generic map (ADDR_WIDTH => 5, NUM_REGS => 16, REG_WIDTH => 32)
    port map (clk => clk, rst => rst, ce => slot,
      addr_ra => addr_ra, dout_a => a_f, addr_rb => addr_rb, dout_b => b_f,
      dout_0 => z_f, we_wb => we_wb, w_addr_wb => w_addr_wb, din_wb => din_wb,
      we_ex => we_ex, w_addr_ex => w_addr_ex, din_ex => din_ex, wr_data_o => open);

  process
  begin
    test_plan(3 * S'length, "register_file ebr vs flops cross-check");
    rst <= '1'; slot <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0'; slot <= '1';
    for i in S'range loop
      wait until rising_edge(clk);
      addr_ra   <= S(i).ra;  addr_rb   <= S(i).rb;
      we_wb     <= S(i).ewb; w_addr_wb <= S(i).awb; din_wb <= S(i).dwb;
      we_ex     <= S(i).eex; w_addr_ex <= S(i).aex; din_ex <= S(i).dex;
      wait until falling_edge(clk);
      wait for 1 ns;   -- let ebr's q_a/q_b settle, then both are comparable
      check(a_e, a_f, b_e, b_f, z_e, z_f, "cycle " & integer'image(i));
    end loop;
    test_finished("done");
    wait for 40 ns; ENDSIM := true; wait;
  end process;
end tb;
