-- Hardware performance counters (PMU).
--
-- Eight 32-bit free-running counters, a global enable, a sticky per-counter
-- overflow register and an identity register, published as one record to
-- core/datapath.vhm's P4 read path and written through a strobe/select/data
-- port from the same place. The full design argument -- widths, overflow
-- semantics, why fixed-function rather than programmable event select, the
-- privilege story and the reader protocol -- is docs/pmu/perf-counters.md.
--
-- WHAT THIS BLOCK IS FIXING. Before it, the only counters in the core were
-- tlb_walk's walks/hits: 16 bits, `walks_r <= walks_r + 1`, plain wrap, no
-- saturation and no overflow flag. A sampling reader cannot tell one wrap from
-- two, so the pair could witness "did a walk happen" (which is all the guards
-- ever asked of it) but could not measure a rate. There was no cycle counter
-- and no instruction counter anywhere in the RTL, which made IPC and walk
-- latency not merely unmeasured but unmeasurable. Those two walker counters are
-- now counters 6 and 7 here -- tlb_walk exports the two event pulses instead of
-- holding its own state, so there is one counter implementation, not two.
-- P4_TSBCNT keeps its architected value bit-for-bit FOR SOFTWARE THAT NEVER
-- TOUCHES THE PMU PAGE; clearing PMCR.EN freezes it, and writing counter 6 or 7
-- sets it. Both are intended, both are privileged, and both are new.
--
-- AREA. Against base a9ffac1 (SYNTH_VARIANT=j4, synth/cpu_synth.sh asic, both
-- arms built from a real commit into a throwaway `git archive` tree): +2419
-- generic cells and +264 flops on j4, and +0 flops / -4 generic cells on j2 --
-- i.e. nothing, the g_no_mmu_counters tie-off doing its job. The +264 is
-- EXACTLY 8*32 counters + 32 PMCR + 8 PMOVF - 32 for tlb_walk's removed 16-bit
-- pair, which is the cross-check that the synthesised block is this block.
-- ECP5 LUT4 is deliberately not quoted: its measured noise floor on this core
-- is 368 (core/tlb.vhd's area note). Full table and method in
-- docs/pmu/perf-counters.md section 8.3.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.perf_pack.all;

entity perf is
  port (
    clk : in    std_logic;
    rst : in    std_logic;
    -- One pulse per event, except ev(PMU_CYC) which is a level. See perf_pkg.
    ev : in    perf_ev_t := PERF_EV_ZERO;
    -- P4 write side (privileged; the SR.MD gate is in datapath.vhm).
    wr : in    perf_wr_t := PERF_WR_ZERO;

    regs_o : out   perf_regs_t
  );
end entity perf;

architecture rtl of perf is

  -- PMCR reset value. Bit 0 = EN, and it RESETS SET, i.e. the counters
  -- free-run out of reset.
  --
  -- Not a default chosen for convenience. (a) Counters 6/7 back the P4_TSBCNT
  -- alias, which has always been free-running from reset and which 41 of the
  -- 157 guard sources in sim/tests read; resetting EN to '0' would freeze it
  -- and change architected behaviour. (b) A counter you have to remember to switch on is a
  -- counter that reads zero when you forget, and a P4 register that reads zero
  -- and never faults is exactly the failure mode docs/soc/p4-mmio-map.md flags
  -- as a normative hazard. EN's purpose is therefore to FREEZE, not to arm: a
  -- reader clears it to take a coherent snapshot across all eight counters and
  -- sets it again afterwards.
  constant pmcr_reset : std_logic_vector(31 downto 0) := x"00000001";

  constant cnt_ones : std_logic_vector(PMU_CNT_W - 1 downto 0) := (others => '1');
  constant ovf_pad  : std_logic_vector(31 downto PMU_NUM_CNT)  := (others => '0');

  -- Implemented-counter bitmask for PMIDR, one bit per counter.
  constant idr_mask : std_logic_vector(7 downto 0) :=
                                                      std_logic_vector(to_unsigned(2 ** PMU_NUM_CNT - 1, 8));

  signal cnt_r  : perf_cnt_array_t                           := (others => (others => '0'));
  signal ovf_r  : std_logic_vector(PMU_NUM_CNT - 1 downto 0) := (others => '0');
  signal pmcr_r : std_logic_vector(31 downto 0)              := pmcr_reset;

begin

  -- One aggregate, not four per-field assignments: separate concurrent
  -- assignments to separate fields of one output port are legal VHDL but give
  -- the port several drivers, and yosys `check -assert` is run on this design.
  regs_o <=
  (
    cnt  => cnt_r,
    ovf  => ovf_pad & ovf_r,
    pmcr => pmcr_r,
    idr  => PMU_IDR_MAGIC & std_logic_vector(to_unsigned(PMU_CNT_W, 8)) & idr_mask
  );

  p_perf : process (clk) is

    variable ovf_v : std_logic_vector(PMU_NUM_CNT - 1 downto 0);

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        cnt_r  <= (others => (others => '0'));
        ovf_r  <= (others => '0');
        pmcr_r <= pmcr_reset;
      else
        -- PMOVF write-1-to-clear, applied to the OLD bits FIRST so that the
        -- wrap capture inside the loop below folds in AFTERWARDS and a wrap
        -- landing in the same cycle as a clearing write SURVIVES it.
        --
        -- THE ORDER IS THE WHOLE BEHAVIOUR, AND IT WAS WRONG UNTIL 2026-08-26.
        -- This block used to sit after the loop, which reads as "the clear is
        -- folded in after the set" -- a true sentence about the mechanism, and
        -- the exact opposite of the required result: applying the clear last
        -- means the CLEAR WINS and the coincident wrap is LOST. Measured at
        -- entity level: wrap alone gave PMOVF = 0x1, wrap in the same cycle as
        -- the W1C gave 0x0. Losing a wrap notification is precisely what this
        -- register exists to prevent, so "set wins" is not a preference here,
        -- it is the contract (docs/pmu/perf-counters.md section 3).
        --
        -- The coincidence is reachable, not theoretical: the counter-write arm
        -- that suppresses an increment is guarded on wr.tgt = pmu_wr_cnt,
        -- which is false during a PMOVF write, so the increment arm still
        -- fires; nothing gates EN off during a store; and the sampling
        -- protocol in section 3.1 does its W1C with the counters running.
        --
        -- Write-1-to-clear rather than a plain write so that two independent
        -- readers cannot silently clear each other's bits.
        ovf_v := ovf_r;

        if (wr.tgt = pmu_wr_pmovf) then
          ovf_v := ovf_v and not wr.d(PMU_NUM_CNT - 1 downto 0);
        end if;

        if (wr.tgt = pmu_wr_pmcr) then
          pmcr_r <= wr.d;
        end if;

        for i in 0 to PMU_NUM_CNT - 1 loop

          -- A software write and a hardware event in the same cycle: the WRITE
          -- WINS and that one event is dropped. Deliberate, and it is the only
          -- choice that makes `write N; expect N + k` reasoning work at all --
          -- the alternative (adding the event on top of the written value)
          -- means software can never know what it just installed. The loss is
          -- bounded by one count per write, and perf only writes a counter when
          -- it is (re)arming a sampling period, i.e. when it is discarding the
          -- old value anyway.
          if (wr.tgt = pmu_wr_cnt and wr.idx = i) then
            cnt_r(i) <= wr.d;
          elsif (pmcr_r(0) = '1' and ev(i) = '1') then
            cnt_r(i) <= std_logic_vector(unsigned(cnt_r(i)) + 1);
            -- Overflow is captured HERE, at the wrap, and not by comparing
            -- values later: the whole point of the bit is that a reader which
            -- MISSED the wrap can still find out it happened.
            if (cnt_r(i) = cnt_ones) then
              ovf_v(i) := '1';
            end if;
          end if;

        end loop;

        -- The wrap capture in the loop above has folded into ovf_v after the
        -- clear, so this commits "clear the bits software named, then set any
        -- bit that wrapped this cycle" -- set wins on a tie. See the header of
        -- the clear block for why that ordering is the contract.
        ovf_r <= ovf_v;
      end if;
    end if;

  end process p_perf;

end architecture rtl;
