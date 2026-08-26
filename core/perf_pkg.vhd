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

  -- Number of hardware counters. Also the number of live bits in PMOVF and in
  -- PMIDR's implemented-counter mask.
  --
  -- THE THREE DO NOT SCALE ALIKE, AND THE CEILING IS 8. PMOVF's live field
  -- (ovf_r / ovf_pad in perf.vhd) is derived and scales to 32; PMIDR's mask is
  -- a FIXED 8-bit field of a 32-bit register, so a ninth counter needs a PMIDR
  -- layout change, not merely a wider constant. The subtype below makes
  -- raising this past 8 an ELABORATION ERROR at this line rather than a silent
  -- truncation later, inside perf.vhd's to_unsigned(2**pmu_num_cnt - 1, 8) --
  -- numeric_std truncates with a warning, which is exactly the kind of thing
  -- nobody sees. A range constraint rather than an `assert`, on purpose: the
  -- area A/B for this block against a9ffac1 depends on the assertion count
  -- being identical at both ends (synth/README.md, "Running an area A/B"), so
  -- this file adds none.
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

  -- The P4 write side, exported by datapath. Strobe + select + data; no read
  -- data comes back on this path, so it adds no dependency edge.
  --   sel 0 .. PMU_NUM_CNT-1 : that counter is loaded with d
  --   sel PMU_SEL_PMCR       : PMCR   <- d
  --   sel PMU_SEL_PMOVF      : PMOVF  <- PMOVF and not d   (write-1-to-clear)
  constant pmu_sel_pmcr  : natural := 8;
  constant pmu_sel_pmovf : natural := 9;

  type perf_wr_t is record
    en  : std_logic;
    sel : std_logic_vector(3 downto 0);
    d   : std_logic_vector(31 downto 0);
  end record perf_wr_t;

  constant perf_wr_zero : perf_wr_t :=
  (
    en  => '0',
    sel => (others => '0'),
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
