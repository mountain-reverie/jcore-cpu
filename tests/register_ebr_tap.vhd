-- Cross-check TAP for the J1 block-RAM register file, register_file(ebr).
-- register_file(two_bank) (async-read, proven -- the arch ebr replaces in J1)
-- is the ORACLE: both are driven by identical stimulus and ebr's
-- falling-edge-read result, sampled late in the slot, must match two_bank for
-- every read port every cycle. Mirrors tests/shifter_seq_tap.vhd.
--
-- two_bank (NOT flops) is the oracle on purpose: like ebr, it does NOT reset
-- the register RAM (block RAM has no reset), so an unwritten register reads 'U'
-- in both -- a true match. flops zero-fills its RAM on reset, which would flag
-- false mismatches on reads of never-written registers and mask the one thing
-- under test: that the falling-edge read reproduces the async read.
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
  -- ebr's full-cycle read needs the address one cycle EARLY (rising-edge read):
  -- addr_ra_early leads addr_ra by one cycle (same read-address sequence), so at
  -- each compare point ebr's q reflects the same register two_bank reads async.
  signal addr_ra_early, addr_rb_early : std_logic_vector(4 downto 0)
    := (others => '0');
  signal din_wb, din_ex : std_logic_vector(31 downto 0) := (others => '0');
  signal we_wb, we_ex : std_logic := '0';

  -- ebr (DUT) and two_bank (oracle) outputs
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
    test_equal(ae, af, desc & " : dout_a == two_bank");
    test_equal(be, bf, desc & " : dout_b == two_bank");
    test_equal(ze, zf, desc & " : dout_0 == two_bank");
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
      addr_ra_early => addr_ra_early, addr_rb_early => addr_rb_early,
      dout_0 => z_e, we_wb => we_wb, w_addr_wb => w_addr_wb, din_wb => din_wb,
      we_ex => we_ex, w_addr_ex => w_addr_ex, din_ex => din_ex, wr_data_o => open);

  oracle : entity work.register_file(two_bank)
    generic map (ADDR_WIDTH => 5, NUM_REGS => 16, REG_WIDTH => 32)
    port map (clk => clk, rst => rst, ce => slot,
      addr_ra => addr_ra, dout_a => a_f, addr_rb => addr_rb, dout_b => b_f,
      dout_0 => z_f, we_wb => we_wb, w_addr_wb => w_addr_wb, din_wb => din_wb,
      we_ex => we_ex, w_addr_ex => w_addr_ex, din_ex => din_ex, wr_data_o => open);

  process
  begin
    -- 3*S'length stimulus checks + 9 stretched-slot (ce=0) checks below.
    test_plan(3 * S'length + 9, "register_file ebr vs two_bank cross-check");
    rst <= '1'; slot <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0'; slot <= '1';
    -- Prime the leading early read address for the first compare point.
    addr_ra_early <= S(0).ra; addr_rb_early <= S(0).rb;
    for i in S'range loop
      wait until rising_edge(clk);   -- ebr q latches reg[ S(i).ra ] (early addr led)
      addr_ra   <= S(i).ra;  addr_rb   <= S(i).rb;
      we_wb     <= S(i).ewb; w_addr_wb <= S(i).awb; din_wb <= S(i).dwb;
      we_ex     <= S(i).eex; w_addr_ex <= S(i).aex; din_ex <= S(i).dex;
      -- lead the early read address by one cycle for the NEXT compare point
      if i < S'high then
        addr_ra_early <= S(i+1).ra; addr_rb_early <= S(i+1).rb;
      end if;
      wait until falling_edge(clk);
      wait for 1 ns;   -- let ebr's q_a/q_b settle, then both are comparable
      check(a_e, a_f, b_e, b_f, z_e, z_f, "cycle " & integer'image(i));
    end loop;

    -- Stretched-slot coverage (ce=0): the J1-unique case. During a shifter(seq)
    -- slot-stretch ce=0, so writes freeze (ce-gated, identical to two_bank)
    -- while ebr's read process is FREE-RUNNING -- it re-latches q_a/q_b on every
    -- falling edge regardless of ce. With the read address held (the frozen
    -- pipeline holds reg.num_x), q must re-latch the same value and stay equal
    -- to two_bank's async read, and a pending write must NOT commit. Drive a
    -- known commit, then hold ce=0 for three cycles with the read held and a
    -- suppressed EX write asserted, comparing ebr vs two_bank each cycle.
    wait until rising_edge(clk);            -- commit cycle (ce still '1')
    addr_ra <= "00001"; addr_rb <= "00010";
    -- Held read address: early addr equals it (full-cycle read of the held reg).
    addr_ra_early <= "00001"; addr_rb_early <= "00010";
    we_wb <= '1'; w_addr_wb <= "00001"; din_wb <= x"deadbeef"; we_ex <= '0';
    wait until rising_edge(clk);            -- reg1 := deadbeef commits here
    we_wb <= '0';
    slot <= '0';                            -- stall: ce=0, writes frozen
    we_ex <= '1'; w_addr_ex <= "00001"; din_ex <= x"00000000";  -- must not commit
    for i in 0 to 2 loop
      wait until falling_edge(clk);
      wait for 1 ns;
      check(a_e, a_f, b_e, b_f, z_e, z_f, "stretch ce=0 " & integer'image(i));
      wait until rising_edge(clk);          -- ce=0: no commit, no ex_pipes shift
    end loop;
    we_ex <= '0'; slot <= '1';

    test_finished("done");
    wait for 40 ns; ENDSIM := true; wait;
  end process;
end tb;
