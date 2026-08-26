# J4 hardware performance counters (PMU)

**Status:** implemented in RTL (`core/perf.vhd`, `core/perf_pkg.vhd`, decoded in
`core/datapath.vhm`). Guards: `sim/tests/pmucnt.S`, `sim/tests/pmuovf.S`, and
the PMU rows of `sim/tests/mmup4priv.S`. The Linux `perf` backend is **not** in
this change — see §10.

**Authority:** `docs/soc/p4-mmio-map.md` (in `jcore-workspace`) owns the P4
address allocation; this document owns what the block does. §9 carries the map
amendment this change requires.

---

## 1. What was actually there before, and why it could not measure anything

The J4 remediation plan states that the cores "already expose PMU/walk counters
(`walk_cnt_walks/hits`, PMCYC/PMINS)". Half of that was false, and the half that
was true was not usable:

* `walk_cnt_walks` / `walk_cnt_hits` existed — 16 bits each, read-only at
  `P4_TSBCNT` (`0xFF000054`), packed `walks:hits`.
* **PMCYC and PMINS did not exist.** Neither did any other cycle or instruction
  counter anywhere in the RTL.
* **No cache counters existed.** The only `cnt_hits` in the tree was the TLB
  walker's.
* The counters that did exist were `walks_r <= walks_r + 1`: plain 16-bit wrap,
  no saturation, no overflow flag.

The consequence is stronger than "unmeasured". IPC needs a cycle counter and an
instruction counter; walk latency needs a cycle counter. Neither existed, so
both gates were **unmeasurable**, not merely unmeasured.

And the 16-bit wrap is not a cosmetic defect. A free-running counter is exactly
reconstructible by modular arithmetic — `total += (cur - prev) mod 2^W` — but
**only if the reader samples faster than the wrap period**. At the J4 ASIC
target of 400 MHz, 16 bits wrap every **164 µs**. No operating system samples a
counter that often, so between any two samples an unknown number of wraps has
occurred and the modular difference is not a count of anything. That is the
precise reason the existing pair could witness *"a walk happened"* (which is all
nine existing guards ever asked of it) and could not measure a rate.

---

## 2. Register map

The block lives at `0xFF001000`, the 4 KB per-CPU **PMU page the canonical P4
map already allocates** (`docs/soc/p4-mmio-map.md` §3). All registers are 32-bit
and word-aligned. Privileged (`SR.MD = 1`) only — see §7.

| Offset | Name  | Access | Meaning |
|--------|-------|--------|---------|
| `0x000` | PMCR   | RW  | bit 0 = `EN`. Resets **set**. |
| `0x004` | PMOVF  | R/W1C | bit *n* = counter *n* has wrapped since last cleared |
| `0x008` | PMIDR  | RO  | `[31:16]` magic `0x4A50`, `[15:8]` counter width (32), `[7:0]` implemented-counter bitmask |
| `0x00C`–`0x01C` | — | — | reserved: this is where `PMSEL0..3` go if the block ever becomes programmable (§4) |
| `0x020` | PMCYC | RW | counter 0 — cycles |
| `0x024` | PMINS | RW | counter 1 — instruction dispatches |
| `0x028` | PMIFR | RW | counter 2 — instruction-fetch bus references |
| `0x02C` | PMIFW | RW | counter 3 — instruction-fetch wait cycles |
| `0x030` | PMDAR | RW | counter 4 — data-access bus references |
| `0x034` | PMDAW | RW | counter 5 — data-access wait cycles |
| `0x038` | PMWLK | RW | counter 6 — TSB walks armed |
| `0x03C` | PMWHT | RW | counter 7 — TSB walks that found a usable PTE |

The counters occupy `0x20`–`0x3C` as one contiguous, naturally indexed block:
**address bits `[4:2]` are the counter number and also the PMOVF bit number**, so
software has one numbering to get wrong instead of three.

`P4_TSBCNT` (`0xFF000054`) is unchanged as an architected register and is now
served from `PMWLK[15:0] & PMWHT[15:0]`. `core/tlb_walk.vhd` holds no counter
state at all; it exports two event pulses (`ev_walk`, `ev_hit`) and the PMU does
the counting. There is now one counter implementation in the core, not two.

---

## 3. Decision: width and overflow semantics

**32-bit, free-running, wrapping, with a sticky per-counter overflow flag.**

**Not 16.** That is the defect being fixed; see §1.

**Not saturating.** Saturation looks like the safe choice and is the wrong one:
once a saturating counter pins at its maximum the reader learns *nothing further*
— not the total, not the rate, not even a lower bound on the excess. Wrapping
plus modular arithmetic reconstructs the total **exactly**, provided the sampling
interval is shorter than the wrap period. 32 bits at 400 MHz puts the wrap period
at **10.7 s** (107 s on the 40 MHz FPGA target), comfortably longer than a
scheduler tick, a `perf` sample interval, or a context switch.

**Not 64.** Doubling to 64 bits costs twice the flops (512 rather than 256 on the
counter file alone), puts a 64-bit incrementer in a 400 MHz path, and — because
the data bus is 32 bits — forces a tearing-safe two-word read protocol, which
needs a shadow latch per counter and therefore *more* than twice the state. It
buys nothing a `u64` accumulator in the driver does not already buy:
`perf_event`'s own `prev_count`/`local64_add` pattern accumulates exactly this
way. `j32ooo-spec.md` §12 specifies 64-bit counters; that is the out-of-order
core's spec, and this is a deliberate, argued divergence for the in-order J4.

**PMOVF is what makes wrapping safe rather than merely cheap.** Sticky, one bit
per counter, write-1-to-clear (so two independent readers cannot silently clear
each other's bits). It answers the one question a wrapping counter cannot answer
by itself: *did I sample too slowly?*

### 3.1 The reader protocol

```
prev[n], total[n]  are per-counter software state, total[n] a u64.

sample():
    ovf = read PMOVF
    write PMOVF = ovf                    # W1C: clear exactly the bits seen
    for n in counters:
        cur      = read PMCNT[n]
        total[n] += (cur - prev[n]) & 0xFFFFFFFF
        prev[n]  = cur
        if ovf & (1 << n):
            # at least one wrap since the last sample. With an interval well
            # under the wrap period this is the expected once-per-10.7s event
            # for PMCYC and the modular difference above is already correct.
            # If it is set on a counter whose interval CANNOT have covered
            # 2^32 events, that is a sampling-rate bug, not a hardware fault.
```

To take a **coherent** snapshot across all eight counters — one in which no
counter moves between the eight reads — clear `PMCR.EN`, read, and set it again.
That is what `EN` is for. It is not an arming bit: it **resets set**, so the
counters free-run out of reset exactly as the walker counters always have (nine
existing guards depend on that), and because a counter you must remember to
switch on is a counter that reads zero when you forget — the same
"reads zero, never faults, looks like the feature is disabled" failure mode that
`p4-mmio-map.md` records as a normative hazard for undecoded P4 offsets.

### 3.2 The sampling boundary — a measured property, not a bug

The counters are read as **registered** values, so an event whose cycle coincides
with the cycle the P4 read is served is **not** in the value returned; it lands in
the next sample. This is sharper on this core than on most, because
`datapath.vhm` issues the next access in the *same* process evaluation that
clears the previous one on ack — so a load and the counter read immediately
following it can be served in one cycle.

Measured with `sim/tests/pmucnt.S`: a window of exactly 8 loads reports a PMDAR
delta of **7** when the counter read follows the eighth load directly, and **8**
with a single `nop` between them. The guard therefore separates every measured
block from its snapshot with one `nop`, in both arms of every comparison. This is
what "sample the counter" means and it is self-cancelling across many samples;
software must simply not expect a counter read to include an access issued in the
same cycle.

---

## 4. Decision: fixed-function, not programmable

Eight dedicated counters, no event-select multiplexer, no `PMSELn`.

The usual argument for programmable event select is that the event inventory far
exceeds the counter count — `j32ooo-spec.md` §12 lists 25 events for 4 general
counters, and there the mux is obviously right. **Here it is not, and the reason
is that the inventory does not exceed the counter count**: the J4 pipeline
exposes eight events worth counting and there are eight counters. A programmable
design would save five counters' worth of flops (160) and spend four selector
registers plus four 8-way 32-bit event muxes to do it — a marginal trade at best.

What decides it is not area:

1. **Simultaneous observability is the entire point.** IPC needs cycles *and*
   instructions from the *same* window. Miss rate needs references *and* the
   quantity you are dividing by, from the same window. Time-multiplexing them
   across runs and dividing is exactly the mistake that produces confident wrong
   numbers on a non-deterministic system, and this project has been burned by
   that class of error repeatedly.
2. **It removes state from the security surface.** There is no "which event is
   counter 2 counting?" to virtualize, save, restore or leak. A hypervisor
   emulating this block needs to model eight monotone values, `PMCR`, and
   `PMOVF`, and nothing else.
3. **The driver is simpler and cannot mis-multiplex.** A fixed-function PMU maps
   one-to-one onto `perf`'s hardware event IDs with no scheduling logic.

Cost of the choice, stated plainly: it does not extend. When a J32-OOO-class
front end arrives with branch predictors and an L2, its events will not fit and
it will need the programmable scheme. The register layout above is chosen so
that scheme is additive: `PMCR`, `PMOVF`, `PMCYC` and `PMINS` keep the names and
roles `j32ooo-spec.md` §12 gives them, and `0x00C`–`0x01C` is left empty for
`PMSEL0..3`.

---

## 5. Decision: addresses

**Its own allocated page, `0xFF001000`.** `p4-mmio-map.md` §3 already reserves a
4 KB per-CPU PMU page there; the MMU page at `0xFF000000` is not the right home
and, on inspection, does not have the room the free-offset list suggests:
`0x30` is CPUINFO, `0x34` is reserved for the proposed PTEU, and `0x3C`/`0x40`
are QACR0/QACR1 (store-queue). `0x30`/`0x2C` additionally carry an unresolved
contradiction inside `p4-mmio-map.md` itself — §3.2 and its "Decision" paragraph
put CPUINFO at `0x030`, while §7 open question 4 says "CPUINFO moves to `0x02C`",
which is MMUFSR. That contradiction is another task's to resolve; using the PMU's
own page means this change does not depend on the answer either way.

**One decode consequence had to be handled.** Every existing P4 arm in
`datapath.vhm` matches on `ma_ad(7 downto 0)` **alone** — `seg_decode` returns
`SEG_P4` for the whole of `0xFF------`, so `0xFF001010` would have decoded as
`MMUCR` and the PMU would have been unreachable at every offset colliding with an
MMU register. The PMU arm is therefore tested **first** and on a whole-page match
(`ma_ad(23 downto 12) = x"001"`). Ordering it first means **no address outside
`0xFF001xxx` changes behaviour**: the residual aliasing of the MMU page across
the rest of the 16 MB P4 window is pre-existing and deliberately left alone here
rather than fixed as a side effect of an unrelated change.

---

## 6. Decision: compile-time optionality

**The PMU is gated on the existing `PRIV_ARCH` generic and gets no generic of its
own.** On `PRIV_ARCH = false` (J1/J2) the block is not instantiated and
`datapath`'s `pmu_i` port is tied to `PERF_REGS_ZERO` in the same
`g_no_mmu_counters` generate that already ties off the install counters — a hard
constant, not an open port, because `core/cpu.vhd` records **+526 LUT4 measured
on j2** from leaving counter inputs undriven (an undriven wire is a don't-care to
synthesis, and the don't-care propagates out of the dead port into unrelated
blocks). With `pmu_i` zero, `PMIDR` reads zero, which is the architected
"no PMU present" answer.

A second, orthogonal `PMU` generic was considered and rejected. It would double
the configuration matrix and create a build that nothing in CI runs — the trap
where an option exists, is never exercised, and is broken the day someone selects
it. And the area argument for it runs backwards: the counters exist precisely so
that the variant we intend to tape out can be measured, so **making them the
first thing dropped for area would tape out a chip we cannot measure**, which is
the situation this whole change exists to end.

---

## 7. Decision: privilege

**Privileged only. Not readable, and certainly not writable, from user mode.**

The Wave-0 fix added an `SR.MD` gate to the P4 path after a user→supervisor
escape (`sim/tests/mmup4priv.S`). That gate is computed once, before the offset
decode:

```
p4_refuse_v := seg_v = SEG_P4 and this.sr.md = '0';
p4_serve_v  := seg_v = SEG_P4 and this.sr.md = '1';
```

The PMU arm adds to the **`p4_sel_v` decode**, which runs ahead of that check and
feeds the *serve* arm only, so the block inherits the gate by construction. Two
properties keep it that way:

* The PMU write strobe (`pmu_wr_c`) is defaulted to `PERF_WR_ZERO` at the top of
  the process and overridden **only inside the served-write arm**. A user-mode
  store takes the refuse arm and cannot reach a counter.
* PMU reads have **no read side effect** — unlike `TSBVICT`, whose read advances
  an LFSR and which is why the refusal is a separate arm ahead of the decode. A
  refused PMU access therefore leaves no trace at all, and a hypervisor can
  emulate PMU reads statelessly.

That is asserted rather than assumed: `mmup4priv.S`'s address sweep now includes
`0xFF001000` (PMCR), `0xFF001008` (PMIDR) and `0xFF001020` (PMCYC), read and
write, and asserts the same `EXPEVT`/`MMUFSR`/`TEA`/no-GPR-write behaviour it
asserts for every MMU CSR. The PMU is the first P4 register **outside** the
`0xFF0000--` window that the decode reaches, and its arm is tested *ahead of* the
MMU chain — "ahead of the MMU chain" is one edit away from "ahead of the
privilege gate", so it is probed explicitly rather than trusted to inherit.

**Why not expose a user-readable cycle counter**, as x86 `rdtsc` and ARM
`PMCCNTR` (unlocked) do? A high-resolution cycle counter is the classic timing
side-channel primitive; this project's threat model treats a guest kernel as the
adversary, and `j32ooo-spec.md` §12.2 already requires the whole block to be
privileged for that reason. Nothing needs it: `perf` reads counters in the kernel
and delivers samples through its ring buffer, so user-space profiling works with
no user-mode MMIO at all. A *writable* counter reachable from user mode would be
worse still — unprivileged code could forge whatever the kernel's own profiler
reports.

Guest P4 is trapped wholesale, so a hypervisor can virtualize or deny the whole
page, exactly as `p4-mmio-map.md` §3.2 requires for `TSBCNT`.

---

## 8. What each counter counts, exactly

| Counter | Event | Notes |
|---------|-------|-------|
| PMCYC | every cycle while `PMCR.EN` | a level, not a pulse |
| PMINS | `slot and instr.issue` | one per **instruction dispatch**. Exactly one per instruction, including multi-slot forms (`MOV.L @Rm+,Rn`, MAC, CAS.L), because `if_issue` is asserted only on an instruction's final slot. An instruction restarted by an exception is counted again — which is the honest reading of "dispatched". |
| PMIFR | `sig_inst_o.en and dp_inst_i.ack` | one per **completed** instruction fetch |
| PMIFW | `sig_inst_o.en and not dp_inst_i.ack` | cycles with a fetch outstanding and unacked |
| PMDAR | `sig_db_o.en and dp_db_i.ack` | one per **completed** data access |
| PMDAW | `sig_db_o.en and not dp_db_i.ack` | cycles with a data access outstanding and unacked |
| PMWLK | `tlb_walk.ev_walk` (= `arm`) | one per walk armed |
| PMWHT | `tlb_walk.ev_hit` | one per probed way returning `V=1, STALE=0` |

`en`/`ack` partitions every outstanding-access cycle into **exactly one**
reference cycle and *n* wait cycles, and `datapath.vhm` clears `data_o`/`inst_o`
on ack, so `en and ack` cannot be true twice for one access. That is the whole
difference between a reference counter and a level counter, and it is asserted
exactly (`pmucnt.S` check `0x30`) rather than left to a "> 0" test.

The reference counters use the **datapath-visible** acks (`dp_*_i.ack`), not the
raw port acks: `db_i.ack` is also the walker's ack while the walker owns the bus,
and counting those would charge the core for accesses it never made. The wait
counters get the complement, so a walk's bus time lands in PMDAW — which is where
it belongs, since that is exactly the stall the core suffers.

### 8.1 What you can compute

* **IPC** = `PMINS / PMCYC`.
* **Average fetch latency** = `(PMIFR + PMIFW) / PMIFR`; likewise for data.
* **Stall attribution**: `PMIFW` and `PMDAW` are the memory-system share of
  `PMCYC` directly.
* **TSB hit rate** = `PMWHT / PMWLK`; **walk cost** = the `PMDAW` contribution
  during walks.

### 8.2 What is deliberately NOT here: L1 miss counts

There are no `L1_I_MISSES` / `L1_D_MISSES` counters, and this is a scoped
decision, not an oversight. Three facts drove it:

1. **The L1s are outside `entity cpu`.** `core/cpu.vhd` has no cache port; the
   caches are instantiated by `icache_cacheable_mux` / `dcache_cacheable_mux`
   above the CPU, in the testbench and in the SoC. The hit/miss state lives in
   `cache/icache_ccl.vhm` and `cache/dcache_ccl.vhm`.
2. **The plumbing crosses a repo boundary.** Reaching the CPU means new output
   ports on `icache_ccl` → `icache` → `icache_adapter` → `icache_cacheable_mux`
   (and the `dcache` mirror), matching `component` declarations in
   `cache/cache_pkg.vhd`, and updates to every instantiation — including board
   tops in `jcore-soc`, which cannot be built or tested from here.
3. **Decisively: the default testbench has no cache.** 140 of the ~155 guards in
   `sim/tests` run on `cpu_tb`, which wires the CPU straight to the bus fabric;
   only 15 run on `cpu_cache_tb`. A miss counter would therefore read a constant
   zero in the configuration almost every guard uses — a P4 register that reads
   zero and never faults, which is precisely the hazard `p4-mmio-map.md` calls
   normative, and it would ship with no non-vacuous guard covering it.

`PMIFR`/`PMIFW` and `PMDAR`/`PMDAW` measure the same traffic from a vantage point
that is correct **with or without** a cache, and are exactly testable in the
default configuration. Under `cpu_cache_tb` the wait counters *are* the L1 miss
cost; what they do not give you is the miss *count* independent of its penalty.

When the miss counters are added, `PMIDR[7:0]` is the mechanism that keeps
software honest: the implemented-counter bitmask widens, and a driver on an older
bitstream sees the new counters reported absent rather than reading zero and
computing a 0 % miss rate. The taps to use are `this.state = MISS1` in
`icache_ccl.vhm` (a guaranteed one-cycle registered pulse, entered only from
IDLE) and `RMISS1`/`WMISS1` in `dcache_ccl.vhm`; do **not** use `a.en`, which is
held across stalls.

---

## 8.3 Area

Measured 2026-08-25. **Both arms built from a real commit** with `git archive`
into a throwaway tree, per `synth/README.md` "Running an area A/B" —
`cpu_synth.sh` regenerates the J4 overlay decoder into *tracked* `decode/*.vhd`
behind a `|| true` restore, so it must never run in a tree whose diff matters.

Metric: `synth/cpu_synth.sh asic`, the **generic (pre-mapping) netlist**, taking
the design-hierarchy totals and a straight count of every DFF-family cell. ECP5
`LUT4` is deliberately **not** quoted: its measured noise floor on this core is
368 (`core/tlb.vhd`'s area note — two logically identical trees, differing only
in the order of two operands of an `or`, mapped 368 apart), which is inside the
margin that would matter here.

The A/B is legal on the assertion rule: **this branch adds and removes no
`assert` statement**, verified by
`git diff a9ffac1..HEAD -- '*.vhd' '*.vhm' | grep -E '^[+-].*\bassert\b'`
matching comment text only. Trees differing in assertion count cannot be
compared — the synthesis driver strips verification cells *after* mapping, and
one clocked `assert` has measured **−855 to +541 LUT4** on this design depending
on what else was in the tree.

| variant | tree | generic cells | flops |
|---------|------|--------------:|------:|
| j4 | `a9ffac1` (branch base) | 36827 | 4520 |
| j4 | `a3a57d5` (this branch)  | 39258 | 4784 |
| j2 | `a9ffac1`               | 17473 | 1700 |
| j2 | `a3a57d5`               | 17469 | 1700 |

**J4: +2431 generic cells (+6.6 %), +264 flops (+5.8 %).**
**J1/J2: +0 flops, −4 generic cells** — i.e. nothing, −4 being noise at this
scale. That is the tie-off in `g_no_mmu_counters` doing its job; a build without
the MMU pays nothing for the PMU.

The flop figure is not just plausible, it is **exactly** the state the design
specifies, which is the cross-check that the synthesised block is the block:

```
  8 counters x 32 bits   = 256
  PMCR (32 bits)         =  32
  PMOVF (8 live bits)    =   8
  walker walks_r/hits_r  = -32   (16 + 16, removed from tlb_walk.vhd)
                          -----
                           264
```

`synth` exit status was 0 on all four arms, which includes `check -assert` — so
the record-and-select structure in §3 introduces no inferred latch, no
multi-driver net, and no combinational loop through `datapath`'s process.

---

## 9. Amendment required in `docs/soc/p4-mmio-map.md`

That map lives in `jcore-workspace`, not in `jcore-cpu`, so this change cannot
carry it. The amendment is a new sub-section under §3, and the §3 table's PMU row
should gain a spec link to this document:

```markdown
### 3.4 PMU sub-allocation (`0xFF001000`–`0xFF001FFF`)

Implemented in `jcore-cpu/core/perf.vhd`, decoded in `core/datapath.vhm`
(`p4_sel_v`, the `ma_ad(23 downto 12) = x"001"` arm, which is tested BEFORE the
MMU chain because that chain matches on `VA[7:0]` alone). Privileged only.
Spec: `jcore-cpu/docs/pmu/perf-counters.md`.

| Offset | Register | Description |
|--------|----------|-------------|
| `0x000` | PMCR   | Global control; bit 0 = EN. Resets SET (counters free-run). RW. |
| `0x004` | PMOVF  | Sticky per-counter wrap flags, bit n = counter n. **Write-1-to-clear.** |
| `0x008` | PMIDR  | `[31:16]` = `0x4A50`, `[15:8]` = counter width (32), `[7:0]` = implemented-counter bitmask. Reads 0 when no PMU is present. RO. |
| `0x00C`–`0x01C` | reserved | future `PMSEL0..3` (programmable event select) |
| `0x020` | PMCYC  | cycles. RW. |
| `0x024` | PMINS  | instruction dispatches. RW. |
| `0x028` | PMIFR  | instruction-fetch bus references. RW. |
| `0x02C` | PMIFW  | instruction-fetch wait cycles. RW. |
| `0x030` | PMDAR  | data-access bus references. RW. |
| `0x034` | PMDAW  | data-access wait cycles. RW. |
| `0x038` | PMWLK  | TSB walks armed. RW. |
| `0x03C` | PMWHT  | TSB walks that hit. RW. |
| `0x040`–`0xFFF` | reserved | |

Counters are 32-bit, free-running and WRAPPING, and are **writable** (Linux
`perf` programs a sampling period by preloading one). `0xFF000054` TSBCNT is
unchanged and is now served from `PMWLK[15:0] & PMWHT[15:0]`.
```

The §3.2 note on TSBCNT should also record that the walker no longer holds its
own counters.

---

## 10. Left to the Linux half of D0a

Not in this change, and deliberately:

* `arch/sh/kernel/cpu/sh4/perf_event.c`-style backend exposing the eight
  counters as fixed-function `perf` hardware events, with the §3.1 accumulate
  loop as the read path and `PMIDR`'s magic as the probe.
* `#define`s for the block in `arch/sh/include/cpu-jcore/cpu/`, alongside the
  existing MMU register addresses.
* An overflow **interrupt** (`j32ooo-spec.md` §12.1 wants one for `perf record`
  sampling). There is no interrupt wire here: `PMOVF` is a polled flag. Adding
  the interrupt needs an AIC2 source line and is an SoC-level change, not a
  core-level one.
* Per-thread counter shadowing (`PMTID`). Meaningless on an in-order,
  single-threaded J4; it belongs with FGMT.
