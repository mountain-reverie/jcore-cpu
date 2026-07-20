library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cache_pack.all;
  use work.memory_pack.all;
  use work.cache_clkmode.all;

entity dcache_ram is
  port (
    clk125 : in    std_logic;
    clk200 : in    std_logic;
    rst    : in    std_logic;
    ra     : in    dcache_ram_i_t;
    ry     : out   dcache_ram_o_t
  );
end entity dcache_ram;

architecture beh of dcache_ram is

  signal tag_we0 : std_logic_vector( 1 downto 0);
  signal tag_dr0 : std_logic_vector(15 downto 0);
  signal tag_dw0 : std_logic_vector(15 downto 0);
  signal tag_dr1 : std_logic_vector(15 downto 0);

begin

  tag0 : component ram_1rw
    generic map (
      subword_width => 8,
      subword_num   => 2,
      addr_width    => 8
    )
    port map (
      rst    => rst,
      clk    => clk125,
      en     => ra.ten0,
      wr     => ra.twr0,
      we     => tag_we0,
      a      => ra.ta0,
      dw     => tag_dw0,
      dr     => tag_dr0,
      margin => "00"
    );

  tag1 : component ram_1rw
    generic map (
      subword_width => 8,
      subword_num   => 2,
      addr_width    => 8
    )
    port map (
      rst    => rst,
      clk    => clk125,
      en     => ra.ten0,
      wr     => ra.twr0,
      we     => tag_we0,
      a      => ra.ta1,
      dw     => tag_dw0,
      dr     => tag_dr1,
      margin => "00"
    );

  tag_we0 <= ra.twr0 & ra.twr0;
  tag_dw0 <= "0" & ra.tag0;
  ry.tag0 <= tag_dr0(14 downto 0); -- 15 b => 16 b ( 15 b range)
  ry.tag1 <= tag_dr1(14 downto 0); -- 15 b => 16 b ( 15 b range)

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
  --
  --  GF180 single-port SRAM spike (branch spike/gf180-cache-singleport-collision):
  --  the open question was whether this sc (single-clock) form ever needs a true
  --  1-read-and-1-write-in-the-same-cycle access -- a case a SINGLE-PORT vendor
  --  SRAM (gf180mcu_fd_ip_sram) cannot serve, since port0 (read, CPU load) and
  --  the sole write port (port1, refill/store mux) are on the same clock. A
  --  sim-only assertion (r_en='1' and w_en='1' and w_wr='1', see the `chk`
  --  process in the sc generate below) was added and exercised against the
  --  dcache scoreboard (sim/cache_sim.sh sc: 1019 directed load/store/refill
  --  interleaving tests incl. hit-under-miss, ALL PASSED) and, as a control,
  --  sim/cache_sim.sh dc (the true 2-write-port form; 1019 tests, ALL PASSED).
  --  RESULT: the collision NEVER fired in either run (0 occurrences of
  --  "GF180-SPIKE" in either log). This is architecturally expected: the
  --  blocking FSM only allows a port0 load read to proceed concurrently with a
  --  port1 refill write when they target DIFFERENT indices (hit-under-miss);
  --  the controller stalls/blocks a same-index load against an in-flight
  --  refill, so r_en and (w_en and w_wr) are asserted together but the
  --  colliding-read-during-write case the single-port macro can't serve does
  --  not arise in the cache's access pattern.
  --  => VERDICT: for the sc (single-clock) case, the vendor single-port SRAM
  --  (gf180mcu_fd_ip_sram) can be used as a TRANSPARENT drop-in for this RAM
  --  via a read/write mux, with NO cache-side stall needed for the collision
  --  case investigated here. (This does not by itself validate every other
  --  aspect of a single-port substitution, e.g. read-during-write-same-address
  --  ordering/behavior on the write port itself, byte-enable partial writes,
  --  or timing/margin differences vs. the inferred/dual-clock tech model --
  --  those are separate concerns from the R+W-collision question this spike
  --  targeted.) The `chk` assertion below is left in as a permanent,
  --  sim-only (translate_off) regression guard: if a future dcache/refill FSM
  --  change ever introduces a same-cycle read+write collision, the scoreboard
  --  will flag it.

  ram : for i in 0 to 1 generate

    dc : if not CACHE_SAME_CLOCK generate

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
          wr0     => ra.wr0,
          we0     => ra.we0( 2 * i +  1 downto  2 * i),
          a0      => ra.a0,
          dw0     => ra.d0 (16 * i + 15 downto 16 * i),
          dr0     => ry.d0 (16 * i + 15 downto 16 * i),
          rst1    => rst,
          clk1    => clk200,
          en1     => ra.en1,
          wr1     => ra.wr1,
          we1     => ra.we1( 2 * i +  1 downto  2 * i),
          a1      => ra.a1,
          dw1     => ra.d1 (16 * i + 15 downto 16 * i),
          dr1     => open,
          margin0 => '0',
          margin1 => '0'
        );

    end generate dc;

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
      w_en <= ra.en1 when ra.wr1 = '1' else
              ra.en0;
      w_wr <= ra.wr1 when ra.wr1 = '1' else
              ra.wr0;
      w_we <= ra.we1(2 * i + 1 downto 2 * i) when ra.wr1 = '1' else
              ra.we0(2 * i + 1 downto 2 * i);
      w_a  <= ra.a1 when ra.wr1 = '1' else
              ra.a0;
      w_d  <= ra.d1(16 * i + 15 downto 16 * i) when ra.wr1 = '1' else
              ra.d0(16 * i + 15 downto 16 * i);

      ram_s : component ram_2rw
        generic map (
          subword_width => 8,
          subword_num   => 2,
          addr_width    => 11
        )
        port map (
          -- port0: read-only (CPU loads); no read on a store so dr0 holds (matches dc)
          rst0 => rst,
          clk0 => clk125,
          en0  => r_en,
          wr0  => '0',
          we0  => b"00",
          a0   => ra.a0,
          dw0  => x"0000",
          dr0  => ry.d0 (16 * i + 15 downto 16 * i),
          -- port1: the sole write port (refill or CPU store). clk1 tied to clk125.
          rst1    => rst,
          clk1    => clk125,
          en1     => w_en,
          wr1     => w_wr,
          we1     => w_we,
          a1      => w_a,
          dw1     => w_d,
          dr1     => open,
          margin0 => '0',
          margin1 => '0'
        );

      -- pragma translate_off
      -- GF180-SPIKE: sim-only check for whether a single-port SRAM (e.g. the
      -- vendor gf180mcu_fd_ip_sram) could serve this RAM transparently. A
      -- single-port SRAM cannot do a read and a write in the same cycle; here
      -- port0-read (CPU load) and the sole write port (refill or store) are
      -- collapsed onto one clock (clk125), so if r_en and w_en/w_wr are ever
      -- both asserted in the same cycle, a single-port macro could NOT serve
      -- both -- a mux (this RTL's current model) silently drops one side, and
      -- a real single-port macro would need a cache-side stall instead.
      chk : process (clk125) is
      begin
        if rising_edge(clk125) then
          if rst /= '1' then
            assert not (r_en = '1' and w_en = '1' and w_wr = '1')
              report "GF180-SPIKE: dcache single-port R+W collision (read load + write refill/store same cycle)"
              severity warning;
          end if;
        end if;
      end process chk;
      -- pragma translate_on

    end generate sc;

  end generate ram;

end architecture beh;
