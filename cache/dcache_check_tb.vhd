library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_pack.all;
use work.data_bus_pack.all;
use work.cache_pack.all;

entity dcache_check_tb is
  generic (DUAL_CLOCK : boolean := false);
end entity;

architecture tb of dcache_check_tb is
  signal clk125, clk200, rst : std_logic := '0';
  signal done : boolean := false;

  signal ctrl   : cache_ctrl_t := (en => '1', inv => '0');
  signal ibus_o : cpu_data_o_t := NULL_DATA_O;
  signal ibus_i : cpu_data_i_t;
  signal snpc_i : dcache_snoop_io_t := NULL_SNOOP_IO;
  signal snpc_o : dcache_snoop_io_t;
  signal dbus_o : cpu_data_o_t;
  signal dbus_i : cpu_data_i_t;
  signal dbus_lock, dbus_ddrburst, dbus_ack_r : std_logic;

  -- DDR model + golden scoreboard memory share this geometry.
  constant MEMW : integer := 16384;                 -- 2^14 words = 64 KB region
  subtype word_t is std_logic_vector(31 downto 0);
  type mem_t is array (0 to MEMW-1) of word_t;
  function init_word(i : integer) return word_t is
  begin return x"D0" & std_logic_vector(to_unsigned(i, 24)); end function;
  function init_mem return mem_t is
    variable m : mem_t;
  begin for i in 0 to MEMW-1 loop m(i) := init_word(i); end loop; return m; end function;
  function widx(a : std_logic_vector) return integer is        -- word index
    variable v : std_logic_vector(a'length-1 downto 0) := a;   -- normalize dir
  begin return to_integer(unsigned(v(15 downto 2))); end function;

  function hex(x : std_logic_vector) return string is          -- for reports
    constant N : integer := (x'length + 3) / 4;
    variable v : std_logic_vector(N*4-1 downto 0) := (others => '0');
    variable s : string(1 to N);
    constant T : string(1 to 16) := "0123456789ABCDEF";
    variable nib : integer;
  begin
    v(x'length-1 downto 0) := x;
    for i in 0 to N-1 loop
      nib := to_integer(unsigned(v(N*4-1-4*i downto N*4-4-4*i)));
      s(i+1) := T(nib+1);
    end loop;
    return s;
  end function;

  -- shared so the stimulus can back-door poke it for the snoop test (Task 4).
  shared variable ddr_mem : mem_t := init_mem;

  signal dbus_o_d5 : cpu_data_o_t := NULL_DATA_O;
  signal ddr_rdy   : std_logic := '0';
begin
  clk125 <= not clk125 after 4 ns when not done else '0';
  g_sc : if not DUAL_CLOCK generate clk200 <= clk125; end generate;
  g_dc : if DUAL_CLOCK generate
           clk200 <= not clk200 after 2.5 ns when not done else '0';
         end generate;
  rst <= '1', '0' after 15 ns;

  dut : entity work.dcache_adapter
    port map (clk125 => clk125, clk200 => clk200, rst => rst,
              ctrl => ctrl, ibus_o => ibus_o, lock => '0', ibus_i => ibus_i,
              snpc_o => snpc_o, snpc_i => snpc_i,
              dbus_o => dbus_o, dbus_lock => dbus_lock,
              dbus_ddrburst => dbus_ddrburst,
              dbus_i => dbus_i, dbus_ack_r => dbus_ack_r);

  -- Behavioral DDR: legacy 1-wait model -- ack one settled step after the cache
  -- presents en with a stable address; read data combinational (gated by ack);
  -- write on en&wr at the clock edge (idempotent across the hold).
  dbus_o_d5 <= dbus_o after 5 ns;
  ddr_ackgen : process(dbus_o, dbus_o_d5)
  begin
    if dbus_o_d5.en = '1' and dbus_o.en = '1' and dbus_o_d5.a = dbus_o.a then
      ddr_rdy <= '1';
    else
      ddr_rdy <= '0';
    end if;
  end process;
  dbus_i.ack <= ddr_rdy;
  dbus_ack_r <= ddr_rdy;
  ddr_rd : process(dbus_o, ddr_rdy)
  begin
    if ddr_rdy = '1' then dbus_i.d <= ddr_mem(widx(dbus_o.a));
    else                  dbus_i.d <= (others => '0'); end if;
  end process;
  ddr_wr : process(clk125)
  begin
    if rising_edge(clk125) then
      if dbus_o.en = '1' and dbus_o.wr = '1' then
        for i in 0 to 3 loop
          if dbus_o.we(i) = '1' then
            ddr_mem(widx(dbus_o.a))(8*i+7 downto 8*i)
              := dbus_o.d(8*i+7 downto 8*i);
          end if;
        end loop;
      end if;
    end if;
  end process;

  -- Watchdog: if the stimulus hasn't finished, fail loudly (a hung load would
  -- otherwise just run to stop-time and exit 0).
  watchdog : process
  begin
    wait for 900 us;
    assert done report "WATCHDOG: testbench did not finish" severity failure;
    wait;
  end process;

  stim : process
    variable errors  : integer := 0;
    variable testno  : integer := 0;
    variable ref_mem : mem_t := init_mem;          -- golden architectural memory
    variable lfsr    : std_logic_vector(15 downto 0) := x"ACE1";  -- fixed seed
    variable a       : std_logic_vector(31 downto 0);
    procedure tick is begin wait until rising_edge(clk125); end procedure;
    procedure nextr is begin                       -- 16-bit Galois LFSR
      if lfsr(0) = '1' then lfsr := ('0' & lfsr(15 downto 1)) xor x"B400";
      else                  lfsr := '0' & lfsr(15 downto 1); end if;
    end procedure;
    procedure do_load(addr : std_logic_vector(31 downto 0); expect : word_t) is
      variable got : word_t;
      variable cyc : integer := 0;
    begin
      ibus_o <= (en=>'1', a=>addr, rd=>'1', wr=>'0', we=>"0000", d=>(others=>'0'));
      loop tick; cyc := cyc + 1; exit when ibus_i.ack = '1'; end loop;
      got := ibus_i.d;
      ibus_o <= NULL_DATA_O;
      testno := testno + 1;
      report "LATENCY load @" & hex(addr) & " = " & integer'image(cyc) & " cycles" severity note;
      if got /= expect then
        errors := errors + 1;
        report "FAIL load @" & hex(addr) & " got=" & hex(got) &
               " exp=" & hex(expect) severity error;
      end if;
      tick;
    end procedure;
    procedure do_store(addr : std_logic_vector(31 downto 0);
                       data : word_t; be : std_logic_vector(3 downto 0)) is
    begin
      ibus_o <= (en=>'1', a=>addr, rd=>'0', wr=>'1', we=>be, d=>data);
      loop tick; exit when ibus_i.ack = '1'; end loop;
      ibus_o <= NULL_DATA_O;
      for i in 0 to 3 loop
        if be(i) = '1' then
          ref_mem(widx(addr))(8*i+7 downto 8*i) := data(8*i+7 downto 8*i);
        end if;
      end loop;
      tick;
    end procedure;
    procedure chk_load(addr : std_logic_vector(31 downto 0)) is
    begin do_load(addr, ref_mem(widx(addr))); end procedure;
    procedure do_snoop_inval(addr : std_logic_vector(31 downto 0)) is
    begin
      snpc_i <= (al => addr(27 downto 5), en => '1');
      tick;
      snpc_i <= NULL_SNOOP_IO;
      for i in 0 to 3 loop tick; end loop;   -- let the invalidation settle
    end procedure;
  begin
    wait until rst = '0';
    for i in 0 to 4 loop tick; end loop;
    -- cold miss: word 0 refills from DDR -> expect init_word(0); next word -> hit
    do_load(x"00000000", init_word(0));
    do_load(x"00000004", init_word(1));
    -- store-hit (line resident), then verify
    do_store(x"00000000", x"CAFEBABE", "1111"); chk_load(x"00000000");
    -- another full-word store, same line (write-port lane coverage). NOTE:
    -- byte-enable (sub-word) stores need SH big-endian byte-lane modeling in this
    -- TB (CPU we/data lane vs DDR lane differ by endianness) -- deferred; all
    -- stores here are full-word (we=1111) so every write-port lane is exercised.
    do_store(x"00000004", x"AABBCCDD", "1111"); chk_load(x"00000004");
    -- store-miss (WFILL) to a fresh line
    do_store(x"00001000", x"12345678", "1111"); chk_load(x"00001000");
    -- eviction: 0x2000 apart collide in the direct-mapped index
    chk_load(x"00000000");                 -- line A resident
    chk_load(x"00002000");                 -- line B evicts A (same index)
    do_store(x"00002000", x"DEADBEEF", "1111");
    chk_load(x"00000000");                 -- A reloads (B's write-back intact)
    chk_load(x"00002000");
    -- snoop: load a clean line, let an "external master" rewrite DDR, snoop-
    -- invalidate, then the next load MUST miss and re-fetch the new value.
    chk_load(x"00003000");
    ddr_mem(widx(x"00003000")) := x"5A5A5A5A";   -- back-door external write
    ref_mem(widx(x"00003000")) := x"5A5A5A5A";   -- golden follows
    do_snoop_inval(x"00003000");
    chk_load(x"00003000");                 -- must refetch 0x5A5A5A5A, not stale
    -- seeded pseudo-random stress over a small window (forces hits/misses/evicts)
    for n in 0 to 2000 loop
      nextr;
      a := (others => '0');
      a(15 downto 13) := lfsr(2 downto 0);     -- tag-ish (collisions in window)
      a(12 downto 5)  := lfsr(10 downto 3);    -- index
      a(4 downto 2)   := lfsr(13 downto 11);   -- word in line
      if lfsr(14) = '1' then do_store(a, lfsr & lfsr, "1111");
      else                   chk_load(a); end if;
    end loop;
    report "dcache_check_tb: " & integer'image(testno) & " tests, " &
           integer'image(errors) & " errors" severity note;
    assert errors = 0 report "DCACHE SCOREBOARD FAILED" severity failure;
    report "ALL TESTS PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture;
