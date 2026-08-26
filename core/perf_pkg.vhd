-- Performance-monitor (PMU) types, register offsets and the read/write
-- interface between core/perf.vhd (which holds the counters) and
-- core/datapath.vhm (which owns the P4 access path).
--
-- WHY THE COUNTERS ARE NOT IN datapath.vhm. The P4 read path is served from
-- inside datapath's one big process, so the obvious shape -- hand the process
-- an address and let perf.vhd return the selected word -- would make
-- datapath's output (the address) feed perf.vhd and perf.vhd's output (the
-- read data) feed datapath. Yosys sees that whole process as ONE cell, so that
-- is a combinational SCC at cell granularity even though the logic is acyclic.
-- This design has already paid for a false SCC once (synth/README.md, the
-- slot_o/instr.issue note), so instead perf.vhd publishes ALL counters
-- unconditionally as a record and datapath selects among them with the same
-- `case p4_sel_v` it already uses for TSBCNT. Nothing flows back.
--
-- WHY THE COUNTERS ARE NOT IN cpu.vhd EITHER: they need a reset, a write port
-- and overflow capture, and cpu.vhd is structural. A separate entity is also
-- what lets `SYNTH` report the block's flops as their own line.

library ieee;
  use ieee.std_logic_1164.all;

package perf_pack is

  -- Number of hardware counters.
  --
  -- FIVE THINGS ARE COUPLED TO THIS NUMBER AND THEY DO NOT ALL SCALE ALIKE.
  -- Listed in full because an earlier revision of this comment named only the
  -- first two and the most dangerous one was invisible:
  --
  --   1. PMOVF's live field (ovf_r / ovf_pad in perf.vhd) -- DERIVED, scales
  --      to 32 on its own.
  --   2. PMIDR's implemented-counter mask -- a FIXED 8-bit field of a 32-bit
  --      register. This is what sets the ceiling at 8: a ninth counter needs a
  --      PMIDR LAYOUT change, not a wider constant.
  --   3. The P4 counter-window decode in core/datapath.vhm. Shares
  --      pmu_cnt_idx_bits / pmu_cnt_tag below so the literal exists once, but
  --      the agreement is HAND-MAINTAINED -- GHDL does not enforce it, as that
  --      comment records in detail. Guard pmucnt is the backstop.
  --   4. The write selector. Formerly an integer numbering shared with the
  --      counter indices, which made PMU_SEL_PMCR = 8 collide with counter 8:
  --      a ninth counter would have turned every PMCR write into a write of
  --      counter 8 as well. That is now UNCONSTRUCTIBLE -- see
  --      perf_wr_target_t below -- rather than merely documented.
  --   5. sim/tests/pmucnt.S's `p_idr_exp` literal (0x4A5020FF). Assembly
  --      cannot be coupled to a VHDL constant, so this one is a genuine
  --      hand-maintained site; guard check 0x01 fails loudly if it drifts,
  --      which is the best available substitute.
  --
  -- The subtype below stops pmu_num_cnt exceeding what item 2 can express.
  -- WHAT IT ACTUALLY PRINTS, so nobody expects better: GHDL reports
  -- `raised CONSTRAINT_ERROR : elab-vhdl_decls.adb:77 access check failed`
  -- with no source file, line or symbol, and under the guard harness that
  -- surfaces only as `FAIL pmucnt`. It is a hard stop at elaboration, which is
  -- the point -- but it will not tell you where to look, so look here.
  --
  -- A range constraint rather than an `assert`, on purpose: the area A/B for
  -- this block against a9ffac1 depends on the assertion count being identical
  -- at both ends (synth/README.md, "Running an area A/B"), so this file adds
  -- none.
  subtype pmu_cnt_count_t is natural range 1 to 8;

  constant pmu_num_cnt : pmu_cnt_count_t := 8;

  -- Counter width. 32, NOT 16 and NOT 64 -- see docs/pmu/perf-counters.md for
  -- the argument. Short version: a WRAPPING counter is exactly reconstructible
  -- by modular arithmetic provided the reader samples faster than the wrap
  -- period. At the J4 ASIC target of 400 MHz a 16-bit cycle counter wraps every
  -- 164 us, which no OS samples faster than -- that is why the pre-existing
  -- 16-bit walker counters could not be used to measure anything. 32 bits moves
  -- the wrap period to 10.7 s, comfortably longer than a scheduler tick.
  constant pmu_cnt_w : natural := 32;

  -- Counter indices. These are ALSO the PMOVF bit numbers and the low nibble of
  -- the P4 offset within the counter block, so there is one numbering to get
  -- wrong rather than three.
  constant pmu_cyc : natural := 0; -- cycles
  constant pmu_ins : natural := 1; -- instruction dispatches
  constant pmu_ifr : natural := 2; -- I-fetch bus references (acks)
  constant pmu_ifw : natural := 3; -- I-fetch wait cycles
  constant pmu_dar : natural := 4; -- D-access bus references (acks)
  constant pmu_daw : natural := 5; -- D-access wait cycles
  constant pmu_wlk : natural := 6; -- TSB walks started
  constant pmu_wht : natural := 7; -- TSB walks that hit

  -- THE P4 COUNTER WINDOW, shared with core/datapath.vhm's decode so the
  -- literal exists once. The counters are pmu_num_cnt consecutive words based
  -- at P4 page offset 0x020, so within the 12-bit page offset the decode
  -- splits as: ma_ad(11 downto 2 + pmu_cnt_idx_bits) = pmu_cnt_tag, counter
  -- index in ma_ad(1 + pmu_cnt_idx_bits downto 2), ma_ad(1 downto 0) = "00".
  -- datapath.vhm derives BOTH slices from pmu_cnt_idx_bits rather than
  -- spelling them out, so the window and the index cannot be edited apart.
  --
  -- THIS COUPLING IS HAND-MAINTAINED, NOT COMPILER-ENFORCED, and saying so is
  -- the point. An earlier revision declared a `pmu_cnt_span` constrained to
  -- equal pmu_num_cnt and called it an elaboration rail. It is not one: with
  -- pmu_cnt_idx_bits set to 2 the design ANALYSED AND BUILT CLEANLY -- first
  -- with the constant unreferenced, and still after it was made to size
  -- perf_cnt_array_t, at which point GHDL only downgraded the mismatch to
  -- `warning: default value constraints don't match object type ones
  -- [-Wruntime-error]`. Measured on this tree, both times. A construct that
  -- merely LOOKS like a rail is worse than none -- it is the same trap as the
  -- hand-synced component declaration deleted from core/components_pkg.vhd,
  -- where a correct warning comment sat on top of a real mismatch through two
  -- separate drifts. So the fake rail is gone and the real backstop is named:
  -- guard sim/tests/pmucnt.S. Checks 0x03/0x04 pin the window's edges and the
  -- exact-delta checks pin the counters behind it, so an index/window mismatch
  -- fails the guard rather than passing quietly.
  --
  -- (pmu_num_cnt's own subtype IS load-bearing, but be precise about what it
  -- does: setting it to 9 was observed to raise
  -- `CONSTRAINT_ERROR : elab-vhdl_decls.adb:77 access check failed` at
  -- elaboration -- a hard stop with no file, line or symbol, surfacing under
  -- the harness only as `FAIL pmucnt`. Whether that check is the subtype
  -- itself or an array access downstream of it was not determined; what was
  -- observed is that it stops, not where.)
  constant pmu_cnt_idx_bits : natural := 3;
  constant pmu_cnt_tag      : std_logic_vector(11 - (2 + pmu_cnt_idx_bits) downto 0)
    := "0000001";

  type perf_cnt_array_t is array (0 to PMU_NUM_CNT - 1)
    of std_logic_vector(PMU_CNT_W - 1 downto 0);

  -- Everything perf.vhd publishes to the P4 read path. Read-only from
  -- datapath's point of view; nothing in here depends on the P4 address, which
  -- is what keeps the two blocks acyclic (see the header).

  type perf_regs_t is record
    cnt  : perf_cnt_array_t;
    ovf  : std_logic_vector(31 downto 0);
    pmcr : std_logic_vector(31 downto 0);
    idr  : std_logic_vector(31 downto 0);
  end record perf_regs_t;

  -- Tie-off for builds with no PMU (PRIV_ARCH = false). A hard zero, not an
  -- open port: core/cpu.vhd:326 records +526 LUT4 measured on j2 from leaving
  -- counter inputs undriven, because an undriven wire is a don't-care to
  -- synthesis and the don't-care propagates out of the dead port into blocks
  -- that have nothing to do with it. PMIDR = 0 is also the architectural
  -- "no PMU present" answer software tests for.
  constant perf_regs_zero : perf_regs_t :=
  (
    cnt  => (others => (others => '0')),
    ovf  => (others => '0'),
    pmcr => (others => '0'),
    idr  => (others => '0')
  );

  -- The P4 write side, exported by datapath. Target + index + data; no read
  -- data comes back on this path, so it adds no dependency edge.
  --
  --   pmu_wr_cnt   : counter `idx` is loaded with d
  --   pmu_wr_pmcr  : PMCR  <- d
  --   pmu_wr_pmovf : PMOVF <- PMOVF and not d   (write-1-to-clear)
  --   pmu_wr_none  : no write this cycle
  --
  -- AN ENUM, NOT A SHARED INTEGER NUMBERING, and that is the whole point. The
  -- first version encoded the target as a 4-bit `sel` in which 0..7 meant
  -- "counter n" and 8/9 meant PMCR/PMOVF -- so PMU_SEL_PMCR = 8 sat in the
  -- same numbering as the counter indices, and raising pmu_num_cnt to 9 would
  -- have made every PMCR write also clobber counter 8. Nothing would have
  -- reported it; the two `if` arms in perf.vhd would simply both have matched.
  -- With a separate target field that collision cannot be written down, so it
  -- needs no rail, no comment and no test.
  --
  -- There is also no separate `en` bit: pmu_wr_none IS the idle state, so
  -- "a write is happening" and "what it targets" cannot disagree.
  type perf_wr_target_t is (pmu_wr_none, pmu_wr_cnt, pmu_wr_pmcr,
                            pmu_wr_pmovf);

  type perf_wr_t is record
    tgt : perf_wr_target_t;
    idx : natural range 0 to PMU_NUM_CNT - 1;
    d   : std_logic_vector(31 downto 0);
  end record perf_wr_t;

  constant perf_wr_zero : perf_wr_t :=
  (
    tgt => pmu_wr_none,
    idx => 0,
    d   => (others => '0')
  );

  -- The event bundle perf.vhd counts: one bit per counter, each of which must
  -- be a single-cycle pulse per event -- NOT a level held across stalls. That
  -- distinction is the whole difference between a reference counter and a
  -- stall-cycle counter, and getting it wrong is invisible to a "> 0" test.
  -- PMU_CYC and the two wait-cycle events are the deliberate exceptions: they
  -- ARE levels, because a cycle counter counting cycles is the point.

  subtype perf_ev_t is std_logic_vector(PMU_NUM_CNT - 1 downto 0);

  constant perf_ev_zero : perf_ev_t := (others => '0');

  -- PMIDR. [31:16] magic, [15:8] counter width, [7:0] implemented-counter
  -- bitmask. The magic exists because an undecoded P4 offset reads as a hard
  -- zero and raises nothing (docs/soc/p4-mmio-map.md calls this a normative
  -- hazard), so "the PMU is absent" and "the PMU is present and idle" are
  -- otherwise indistinguishable to software. The mask, rather than a count, so
  -- that a build which sources only some events can say which.
  constant pmu_idr_magic : std_logic_vector(15 downto 0) := x"4A50"; -- "JP"

  -- NO `component perf` IS DECLARED HERE, DELIBERATELY. core/cpu.vhd
  -- instantiates the block directly (`entity work.perf`), so a component
  -- declaration would have no users -- and an unused, hand-maintained mirror
  -- of a port list is exactly the trap that cost `component tlb_walk` its
  -- place in core/components_pkg.vhd (see the note there: it drifted twice,
  -- silently, with a correct warning comment sitting on top of it). Add one
  -- here only when something binds it by component, so that the thing using
  -- it is also the thing checking it.

end package perf_pack;
