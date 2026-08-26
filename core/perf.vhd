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
    ev  : in    perf_ev_t := PERF_EV_ZERO;
    -- P4 write side (privileged; the SR.MD gate is in datapath.vhm).
    wr  : in    perf_wr_t := PERF_WR_ZERO;

    regs_o : out   perf_regs_t
  );
end entity perf;

architecture rtl of perf is

  -- PMCR reset value. Bit 0 = EN, and it RESETS SET, i.e. the counters
  -- free-run out of reset.
  --
  -- Not a default chosen for convenience. (a) Counters 6/7 back the P4_TSBCNT
  -- alias, which has always been free-running from reset and which nine guards
  -- assert exact deltas on; resetting EN to '0' would freeze it and change
  -- architected behaviour. (b) A counter you have to remember to switch on is a
  -- counter that reads zero when you forget, and a P4 register that reads zero
  -- and never faults is exactly the failure mode docs/soc/p4-mmio-map.md flags
  -- as a normative hazard. EN's purpose is therefore to FREEZE, not to arm: a
  -- reader clears it to take a coherent snapshot across all eight counters and
  -- sets it again afterwards.
  constant PMCR_RESET : std_logic_vector(31 downto 0) := x"00000001";

  constant CNT_ONES : std_logic_vector(PMU_CNT_W - 1 downto 0) := (others => '1');
  constant OVF_PAD  : std_logic_vector(31 downto PMU_NUM_CNT) := (others => '0');

  -- Implemented-counter bitmask for PMIDR, one bit per counter.
  constant IDR_MASK : std_logic_vector(7 downto 0) :=
    std_logic_vector(to_unsigned(2 ** PMU_NUM_CNT - 1, 8));

  signal cnt_r  : perf_cnt_array_t := (others => (others => '0'));
  signal ovf_r  : std_logic_vector(PMU_NUM_CNT - 1 downto 0) := (others => '0');
  signal pmcr_r : std_logic_vector(31 downto 0) := PMCR_RESET;

begin

  -- One aggregate, not four per-field assignments: separate concurrent
  -- assignments to separate fields of one output port are legal VHDL but give
  -- the port several drivers, and yosys `check -assert` is run on this design.
  regs_o <= (
    cnt  => cnt_r,
    ovf  => OVF_PAD & ovf_r,
    pmcr => pmcr_r,
    idr  => PMU_IDR_MAGIC
            & std_logic_vector(to_unsigned(PMU_CNT_W, 8))
            & IDR_MASK
  );

  p_perf : process (clk) is

    variable ovf_v : std_logic_vector(PMU_NUM_CNT - 1 downto 0);
    variable sel_v : integer range 0 to 15;

  begin

    if rising_edge(clk) then
      if rst = '1' then
        cnt_r  <= (others => (others => '0'));
        ovf_r  <= (others => '0');
        pmcr_r <= PMCR_RESET;
      else
        sel_v := to_integer(unsigned(wr.sel));
        ovf_v := ovf_r;

        if wr.en = '1' and sel_v = PMU_SEL_PMCR then
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
          if wr.en = '1' and sel_v = i then
            cnt_r(i) <= wr.d;
          elsif pmcr_r(0) = '1' and ev(i) = '1' then
            cnt_r(i) <= std_logic_vector(unsigned(cnt_r(i)) + 1);
            -- Overflow is captured HERE, at the wrap, and not by comparing
            -- values later: the whole point of the bit is that a reader which
            -- MISSED the wrap can still find out it happened.
            if cnt_r(i) = CNT_ONES then
              ovf_v(i) := '1';
            end if;
          end if;

        end loop;

        -- PMOVF write-1-to-clear, folded in AFTER the set above via the
        -- variable so that a wrap landing in the same cycle as the clearing
        -- write survives it. Write-1-to-clear rather than a plain write so two
        -- independent readers cannot silently clear each other's bits.
        if wr.en = '1' and sel_v = PMU_SEL_PMOVF then
          ovf_v := ovf_v and not wr.d(PMU_NUM_CNT - 1 downto 0);
        end if;

        ovf_r <= ovf_v;
      end if;
    end if;

  end process p_perf;

end architecture rtl;
