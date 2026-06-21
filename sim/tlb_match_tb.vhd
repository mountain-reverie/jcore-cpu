library ieee;
use ieee.std_logic_1164.all;
use work.cpu2j0_components_pack.all;

entity tlb_match_tb is
end entity;

architecture sim of tlb_match_tb is
  signal clk      : std_logic := '0';
  signal i_va     : std_logic_vector(31 downto 0) := (others => '0');
  signal i_pa_tag : std_logic_vector(14 downto 0);
  signal i_hit    : std_logic;
  signal i_prot   : std_logic;
  signal d_va     : std_logic_vector(31 downto 0) := (others => '0');
  signal d_we     : std_logic := '0';
  signal d_pa_tag : std_logic_vector(14 downto 0);
  signal d_hit    : std_logic;
  signal d_prot   : std_logic;
  signal asid     : std_logic_vector(15 downto 0) := x"0001";
  signal md       : std_logic := '1';
  signal at       : std_logic := '1';
  signal tlb_wr   : std_logic := '0';
  signal pteh_vpn : std_logic_vector(31 downto 12) := (others => '0');
  signal ptel     : std_logic_vector(31 downto 0)  := (others => '0');
  signal asidr    : std_logic_vector(15 downto 0)  := x"0001";
  signal ti       : std_logic := '0';

  procedure clk_tick(signal c : inout std_logic) is
  begin
    wait for 5 ns; c <= '1'; wait for 5 ns; c <= '0';
  end procedure;

  -- Install one TLB entry via the write interface.
  -- ppn_in: PA[31:10] (22 bits).  flags[7:0] = {w,x,u,d,c,global,stale,0}.
  -- PTEL encoding: ptel[31:10]=ppn, ptel[7:0]=flags.
  procedure install(
    signal tlb_wr_s   : out std_logic;
    signal pteh_vpn_s : out std_logic_vector(31 downto 12);
    signal ptel_s     : out std_logic_vector(31 downto 0);
    signal asidr_s    : out std_logic_vector(15 downto 0);
    signal clk_s      : inout std_logic;
    vpn_in  : std_logic_vector(31 downto 12);
    ppn_in  : std_logic_vector(31 downto 10);   -- 22-bit PPN = PA[31:10]
    asid_in : std_logic_vector(15 downto 0);
    flags   : std_logic_vector(7 downto 0)       -- {w,x,u,d,c,global,stale,0}
  ) is
    variable p : std_logic_vector(31 downto 0);
  begin
    p := (others => '0');
    p(31 downto 10) := ppn_in;
    p(7 downto 0)   := flags;
    pteh_vpn_s <= vpn_in;
    ptel_s     <= p;
    asidr_s    <= asid_in;
    tlb_wr_s   <= '1';
    clk_tick(clk_s);
    tlb_wr_s   <= '0';
  end procedure;

begin
  uut: entity work.tlb
    port map (
      clk      => clk,
      i_va     => i_va, i_pa_tag => i_pa_tag, i_hit => i_hit, i_prot => i_prot,
      d_va     => d_va, d_we => d_we, d_pa_tag => d_pa_tag, d_hit => d_hit, d_prot => d_prot,
      asid     => asid, md => md, at => at,
      tlb_wr   => tlb_wr, pteh_vpn => pteh_vpn, ptel => ptel, asidr => asidr,
      ti       => ti
    );

  process
    -- ppn1: PA[31:10] = 22 bits.  PA[13]=1 => PA base = 0x0000_2000
    variable ppn1 : std_logic_vector(31 downto 10) := "0000000000000000001000";
    -- ppn2: PA[14]=1 => PA base = 0x0000_4000
    variable ppn2 : std_logic_vector(31 downto 10) := "0000000000000000010000";
  begin
    -- ---- Test 1: Install entry, hit on matching VPN+ASID ----
    -- VPN=0x00001 (page 1), PPN=ppn1, ASID=0x0001, flags: x=1,u=1,c=1 => "01100100" wait --
    -- flags[7:0] = {w,x,u,d,c,global,stale,0}
    -- w=1,x=1,u=1,d=0,c=1,global=0,stale=0,0 => "11010000" hmm let's be explicit:
    -- bit7=w=1, bit6=x=1, bit5=u=1, bit4=d=0, bit3=c=1, bit2=global=0, bit1=stale=0, bit0=0
    -- => "11101000" = 0xE8  -- but use "01100100" from brief? use corrected encoding:
    -- {w=1,x=1,u=1,d=0,c=1,global=0,stale=0,rsv=0} = "11101000"
    install(tlb_wr, pteh_vpn, ptel, asidr, clk,
            x"00001", ppn1, x"0001", "11101000");
    i_va <= x"00001000";  asid <= x"0001";
    wait for 1 ns;
    assert i_hit = '1'
      report "T1: miss on installed entry" severity failure;
    assert i_prot = '0'
      report "T1: spurious prot on readable+executable entry" severity failure;
    -- pa_tag = ppn1(27 downto 13) = PA[27:13] = 15 bits (28-bit cache region)
    assert i_pa_tag = ppn1(27 downto 13)
      report "T1: wrong PA tag" severity failure;

    -- ---- Test 2: VPN bit flip → miss ----
    i_va <= x"00002000";
    wait for 1 ns;
    assert i_hit = '0'
      report "T2: false hit on VPN mismatch" severity failure;

    -- ---- Test 3: ASID mismatch on non-global entry → miss ----
    i_va  <= x"00001000";
    asid  <= x"0002";
    wait for 1 ns;
    assert i_hit = '0'
      report "T3: false hit on ASID mismatch" severity failure;
    asid  <= x"0001";

    -- ---- Test 4: GLOBAL entry hits regardless of ASID ----
    -- global = bit2 set => flags "11101100"
    install(tlb_wr, pteh_vpn, ptel, asidr, clk,
            x"00002", ppn1, x"0001", "11101100");
    i_va  <= x"00002000";
    asid  <= x"FFFF";
    wait for 1 ns;
    assert i_hit = '1'
      report "T4: global entry missed on ASID mismatch" severity failure;
    asid  <= x"0001";

    -- ---- Test 5: X=0 on I-fetch → i_prot ----
    -- x=0: flags "10101000"
    install(tlb_wr, pteh_vpn, ptel, asidr, clk,
            x"00003", ppn1, x"0001", "10101000");
    i_va  <= x"00003000";
    wait for 1 ns;
    assert i_hit = '1'
      report "T5: miss when should hit" severity failure;
    assert i_prot = '1'
      report "T5: i_prot not raised for X=0" severity failure;

    -- ---- Test 6: W=0 on D-write → d_prot ----
    -- w=0: flags "01101000"
    install(tlb_wr, pteh_vpn, ptel, asidr, clk,
            x"00004", ppn1, x"0001", "01101000");
    d_va  <= x"00004000"; d_we <= '1';
    wait for 1 ns;
    assert d_hit = '1'
      report "T6: d miss" severity failure;
    assert d_prot = '1'
      report "T6: d_prot not raised for W=0 on write" severity failure;
    d_we  <= '0';

    -- ---- Test 7: TI flush clears all entries ----
    ti <= '1'; clk_tick(clk); ti <= '0';
    i_va <= x"00001000";
    wait for 1 ns;
    assert i_hit = '0'
      report "T7: hit after TI flush" severity failure;

    -- ---- Test 8: Independent I and D lookups ----
    install(tlb_wr, pteh_vpn, ptel, asidr, clk,
            x"00010", ppn1, x"0001", "11101000");
    install(tlb_wr, pteh_vpn, ptel, asidr, clk,
            x"00020", ppn2, x"0001", "11101000");
    i_va <= x"00010000"; d_va <= x"00020000";
    wait for 1 ns;
    assert i_hit = '1'
      report "T8: i miss" severity failure;
    assert d_hit = '1'
      report "T8: d miss" severity failure;
    assert i_pa_tag /= d_pa_tag
      report "T8: same PA tag for different entries" severity failure;

    report "tlb_match_tb: all tests passed" severity note;
    wait;
  end process;
end architecture;
