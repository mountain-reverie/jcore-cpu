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
precise reason the existing pair could witness *"a walk happened"* — which is all
any existing guard ever asked of it — and could not measure a rate.

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

### 2.1 Reset values, and exactly how PMCR behaves on write

| Register | Value out of reset |
|----------|--------------------|
| PMCR  | `0x00000001` — the **whole word**, not just bit 0. Guard `pmucnt` check `0x02` asserts this exact value. |
| PMOVF | `0x00000000` |
| PMCNT0–7 | `0x00000000`, and counting immediately (PMCR.EN resets set) |
| PMIDR | `0x4A5020FF`, constant — `0x00000000` on a build without the PMU |

**PMCR bits `[31:1]` are plain read/write storage, not RAZ/WI.** They are
implemented as flops, they read back exactly what was written, and nothing in
hardware consumes them. This is stated because the alternative matters to a
driver: with RAZ/WI a plain `writel(1, PMCR)` is always correct, whereas here it
**clobbers** whatever a previous writer left in the upper bits. Today nothing
uses them, so `writel(1, PMCR)` is correct *and* is what the guards do — but if
a future revision defines a bit up there (freeze-on-overflow and
interrupt-enable are the obvious candidates, and `j32ooo-spec.md` §12.1 lists
both), every existing plain write becomes a bug. **Use read-modify-write on
PMCR** and the driver survives that revision unchanged.

The counters occupy `0x20`–`0x3C` as one contiguous, naturally indexed block:
**address bits `[4:2]` are the counter number and also the PMOVF bit number**, so
software has one numbering to get wrong instead of three.

**All 12 offset bits are decoded.** Unlike the MMU page at `0xFF000000` — which
matches on `[7:0]` alone and therefore repeats across its page and beyond — the
PMU page has **no aliases**: `0xFF001100` is not a second PMCR, `0xFF001120` is
not a second PMCYC, and everything from `0x040` up reads as a hard zero. §5
explains why this is worth the extra four bits of compare, and `pmucnt.S` checks
`0x03`–`0x05` hold it in place.

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

### 3.1a Freezing: what `PMCR.EN` costs, and how to program a period

To take a **coherent** snapshot across all eight counters — one in which no
counter moves between the eight reads — clear `PMCR.EN`, read, and set it again.
That is what `EN` is for. It is not an arming bit: it **resets set**, so the
counters free-run out of reset exactly as the walker counters always have (41 of
the 157 guard sources in `sim/tests` reference `0xFF000054`; counted with
`grep -l 0xFF000054 sim/tests/*.S | wc -l`), and because a counter you must
remember to switch on is a counter that reads zero when you forget — the same
"reads zero, never faults, looks like the feature is disabled" failure mode that
`p4-mmio-map.md` records as a normative hazard for undecoded P4 offsets.

**`EN = 0` freezes PMCYC too.** There is no exemption: `perf.vhd` gates every
counter on `PMCR.EN`, cycles included, and guard `pmuovf` check `0x10` asserts
exactly that by equality. Two consequences a driver author must plan for:

* **Ratios stay correct.** The frozen window is excluded from numerator and
  denominator alike, so IPC, miss rate and TSB hit rate are unaffected by
  snapshotting.
* **PMCYC stops tracking wall clock.** Across an eleven-register read burst it
  systematically undercounts, and the deficit accumulates over every sample. So
  **do not use PMCYC as an elapsed-time source if you freeze.** If you need
  elapsed cycles, read PMCYC *first and unfrozen* — a single 32-bit read cannot
  tear — and freeze only for the multi-counter set that actually needs
  coherence.

**Programming a sampling period — freeze first.** A counter write and a hardware
event in the same cycle resolve **write wins, and that event is dropped**
(`perf.vhd`: the write arm precedes the increment arm on the same counter).
That is deliberate — the alternative, adding the event on top of the written
value, means software can never know what it just installed — but it means a
naive `writel(period, PMCNT[n])` on a running counter can lose one count. The
loss is bounded at one per write and lands on a value being discarded anyway,
so it is usually irrelevant; it is *not* irrelevant if the driver is
reconstructing an exact total across the write. The recipe that has no loss at
all:

```
    clear PMCR.EN                  # freeze
    write PMCNT[n] = period_start  # no event can be in flight to lose
    write PMOVF    = 1 << n        # W1C: clear this counter's stale wrap flag
    set   PMCR.EN                  # resume
```

Overflow is captured *at the wrap*, and the write-1-to-clear is applied to the
**old** bits first so the capture folds in afterwards — **set wins on a tie**, so
a wrap landing in the same cycle as a clearing write survives it. That is what
makes a W1C safe to issue with the counters running, which §3.1's sampling loop
depends on.

> **This paragraph was wrong until 2026-08-26, and the shape of the error is
> worth keeping.** The RTL applied the clear *after* the capture, so the clear
> won and the coincident wrap was **lost** — the exact failure PMOVF exists to
> prevent. The sentence describing the mechanism ("folded in after the set") was
> *accurate*; only the conclusion drawn from it was inverted, which is why it
> read as correct, survived a review, and was then promoted from an RTL comment
> into this spec with a stronger claim attached. Measured at entity level, wrap
> alone vs wrap in the W1C cycle: `PMOVF = 01000000` / `00000000` before the
> fix, `01000000` / `01000000` after. If you are checking a claim in this
> document, check the conclusion separately from the mechanism.

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
and, on inspection, does not have the room a glance at the decode suggests:
`0x30` is CPUINFO, `0x34` is reserved for the proposed PTEU, and `0x3C`/`0x40`
are QACR0/QACR1 (store queue). Only `0x44` and `0x5C` upward are genuinely
unallocated there — not enough for eleven registers, and taking them would have
scattered the block.

> An earlier revision of this section, and of the `datapath.vhm` decode comment
> and commit `e208745`'s message, also cited an *unresolved contradiction* about
> whether CPUINFO lives at `0x030` or `0x02C`. **That is no longer true and the
> claim is withdrawn**: `p4-mmio-map.md` §7 item 4 was corrected on 2026-08-25
> (it now records that its own "moves to `0x02C`" was wrong, `0x02C` being
> MMUFSR, and that CPUINFO is at `0x030`). The decision here never rested on it
> — the three allocations above are independent grounds — but the premise was
> stale and is corrected rather than quietly dropped.

**Two decode consequences had to be handled.**

*Ordering.* Every existing P4 arm in `datapath.vhm` matches on
`ma_ad(7 downto 0)` **alone** — `seg_decode` returns `SEG_P4` for the whole of
`0xFF------`, so `0xFF001010` would have decoded as `MMUCR` and the PMU would
have been unreachable at every offset colliding with an MMU register. The PMU arm
is therefore tested **first** and on a whole-page match
(`ma_ad(23 downto 12) = x"001"`). Ordering it first means **no address outside
`0xFF001xxx` changes behaviour**: the residual aliasing of the MMU page across
the rest of the 16 MB P4 window is pre-existing and deliberately left alone here
rather than fixed as a side effect of an unrelated change.

Addresses *inside* the page did change, and a hypervisor or emulator author
needs the sentence spelled out rather than inferred from "outside". Before this
block existed, the MMU page's `[7:0]`-only decode answered across the whole P4
window, so **`0xFF001010` was a writable alias of `MMUCR`**, `0xFF001014` of
`TSBBR`, and so on for every MMU register. Those aliases are gone: `0xFF001xxx`
is now claimed by the PMU arm, and any offset in it that the PMU does not decode
reads as a hard zero and discards writes. Nothing is known to have used them —
they were never documented and no guard or kernel path references them — but a
model built by observing the old RTL will differ here, and "the MMU registers
answer at `0xFF0010xx`" was a true statement about `a9ffac1`.

*Width.* The offset compares inside the page are **12-bit**
(`ma_ad(11 downto 0)`), not 8-bit like every other arm in the chain. This is not
stylistic, and it must not be "tidied" for symmetry — it is load-bearing twice:

1. **It closes an aliasing hole.** With 8-bit compares, bits `[11:8]` are
   undecoded and every PMU register acquires 15 further aliases across the page:
   `0xFF001100` would be a second, *writable* PMCR, `0xFF001120` a second,
   *writable* PMCYC, and so on — at addresses the map records as reserved. The
   MMU page aliases this way too, but *that* aliasing is documented and covered
   by `mmup4alias`; a new block should not inherit an old block's undocumented
   habits. Guard `pmucnt.S` checks `0x03`/`0x04` assert `0xFF001100` and
   `0xFF001120` read as hard zero, with check `0x05` (PMCYC is non-zero) as the
   anti-vacuity partner so "reads zero" cannot pass on a dead block.
2. **It keeps `p4-offsets-match-rtl` honest.** That check (Wave-1 task B0c,
   `jcore-workspace/scripts/check-doc-facts.py`) finds decoded registers with
   `ma_ad(7 downto 0) = x"NN" then p4_sel_v := P4_NAME` and reads `NN` as a P4
   offset. With 8-bit compares the three PMU control lines match it, and it
   reports PMCR at `0x000`, PMOVF at `0x004` and PMIDR at `0x008` — offsets that
   belong to PTEH, PTEL and TTB. Measured with the check's own parsing logic:
   **18 decoded registers at `a9ffac1`, 21 with the 8-bit form**, the three
   extra ones "absent from the map". They cannot be documented away either —
   writing `PMCR` at `0x000` into the map's register table collides with PTEH
   and trips the same check's *duplicate offset* arm instead. The 12-bit form
   states the truth (these are offsets in a *different page*), the regex
   correctly does not match it, and the check sees exactly the 18 registers it
   saw at base.

---

## 6. Decision: compile-time optionality

**The PMU is gated on the existing `PRIV_ARCH` generic and gets no generic of its
own.** On `PRIV_ARCH = false` (J1/J2) the block is not instantiated and
`datapath`'s `pmu_i` port is tied to `PERF_P4_ZERO` in the same
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

* **IPC** = `PMINS / PMCYC` — with one caveat that must travel with the number.
  `PMINS` counts instruction **dispatches**, not retirements, and this core has
  no retirement stage to count instead. The two differ only when an instruction
  is restarted: a TLB fault, a P4 privilege refusal or any other precise
  exception re-runs its instruction, and the counter charges for each attempt.
  So **IPC is optimistic under heavy faulting**, in exactly the workload where
  the walk counters are most interesting, and IPC read next to a large `PMWLK`
  should be treated as an upper bound. On fault-free straight-line code
  dispatches and retirements coincide exactly — `pmucnt.S` check `0x10` pins
  that to the instruction.
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
2. **The plumbing crosses a repo boundary, and it does so on the *input* side
   of `cpu`.** The signal has to travel *down*, not up: the caches sit **above**
   `entity cpu`, so the miss pulse must leave `icache_ccl` (through `icache`,
   `icache_adapter`, `icache_cacheable_mux`, and the `dcache` mirror) and then
   **enter** `cpu` as a new **input port**. The output ports on the way up are
   the cheap half — an unassociated formal `out` is legal VHDL, so existing
   instantiations need not change for those. The expensive half is the `cpu`
   input: **every** instantiation of `cpu` must drive it, including `jcore-soc`'s
   target tops, which cannot be built or tested from here. And an input left
   undriven is not a benign default — it is precisely the don't-care hazard
   `core/cpu.vhd` measures at **+526 LUT4 on j2**, propagating out of the dead
   port into unrelated blocks, which is why `perf_pkg.vhd`'s `PERF_P4_ZERO`
   exists at all.
3. **Decisively: the default testbench has no cache.** `sim/tests` holds 157
   `.S` guard sources and `sim/mmu_sim.sh` names `cpu_cache_tb` on exactly 15
   `run_guard` lines (counted, not estimated:
   `ls sim/tests/*.S | wc -l` and `grep -c 'run_guard.*cpu_cache_tb'`). Every
   other guard runs on `cpu_tb`, which wires the CPU straight to the bus fabric
   with no cache RTL at all. A miss counter would therefore read a constant
   zero in the configuration almost every guard uses — a P4 register that reads
   zero and never faults, which is precisely the hazard `p4-mmio-map.md` calls
   normative, and it would ship **with no non-vacuous guard in the default
   configuration**. Note the qualifier: a guard *was* available. Fifteen guards
   already run under `cpu_cache_tb` and a sixteenth could have been written, so
   "untestable" would be false. What is true is narrower and still decisive —
   the counter would be dead in the configuration that runs on nearly every
   invocation of the suite, and a register that reads zero for almost everyone
   is worse than a register that is absent.

`PMIFR`/`PMIFW` and `PMDAR`/`PMDAW` measure the same traffic from a vantage point
that is correct **with or without** a cache, and are exactly testable in the
default configuration.

**Under `cpu_cache_tb` they are more than a proxy.** With the L1s present, the
CPU's fetch and data ports go *to the caches*, so `PMIFR` and `PMDAR` count
exactly the I-side and D-side **L1 reference streams** — that is, `L1_I_ACCESSES`
and `L1_D_ACCESSES` in `j32ooo-spec.md` §12.2's inventory, delivered rather than
deferred — and `PMIFW`/`PMDAW` are the L1 miss *cost* in cycles. The single
quantity still missing is the miss **count** independent of its penalty; miss
*rate* is recoverable from average latency given the hit and miss latencies.

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
| j4 | `a9ffac1` (branch base)   | 36827 | 4520 |
| j4 | `a3a57d5` (8-bit decode)  | 39258 | 4784 |
| j4 | `30463ca` (12-bit decode) | 39248 | 4784 |
| j4 | `0b0e48b8` (last logic change) | 39246 | 4784 |
| j4 | `bdc41d6b` (branch tip)   | 39246 | 4784 |
| j2 | `a9ffac1`                 | 17473 | 1700 |
| j2 | `a3a57d5`                 | 17469 | 1700 |
| j2 | `30463ca`                 | 17469 | 1700 |
| j2 | `0b0e48b8` (last logic change) | 17469 | 1700 |

**J4: +2419 generic cells (+6.6 %), +264 flops (+5.8 %) against base.**
**J1/J2: +0 flops, −4 generic cells** — nothing, which is the tie-off working.

The tip row is a comment-only commit after the last logic change and measures
identically, which was checked rather than assumed — the same discipline
`f61e0619` exists for.

The base row reproduced to the cell across every re-measurement in this table
(36827 / 4520 each time), which is the check that the measurement pipeline
itself is stable rather than the numbers being drift.

Three things are worth reading off the intermediate rows rather than assumed.
The comment-only commits between `a3a57d5` and the widening measured
**identical** (39258 / 4784) — what a comment-only change must be, and checked
rather than trusted. Widening the PMU compares from 8 bits to 12 (§5) cost
**−10 generic cells and zero flops**. And the write-target enum, the page-first
`case`, and the overflow-ordering fix together cost a further **−2 cells and
zero flops**. None of those three deltas is a saving worth claiming — all are
far inside any sensible noise band for a generic-cell count — but together they
settle that closing the alias hole, removing the selector collision and fixing
the overflow ordering were all free. A tighter compare and a resolved
`case` both remove downstream don't-cares, which is the direction that makes
small negatives plausible.

> **Refresh this table when logic changes, not when it feels stale.** It has now
> been wrong twice by exactly this route: figures measured at one commit, then
> two commits that changed logic, and the table still describing the older tree.
> `f61e0619` exists solely to record that a comment-only change moved nothing —
> which is the same discipline pointing the other way.
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

## 8.4 The read interface into the datapath, and what it cost

**Half of everything the PMU added to this core was the way it was READ, not the
counters.** Measured on the ECP5 representative harness (`SYNTH_VARIANT=j4`,
`cpu_timing_top`, LFE5U-85F CABGA381), mapped cell counts from the same netlist
the Fmax sweeps below used:

| netlist | cells | flops |
|---------|------:|------:|
| PMU publishing the whole register file | 21541 | 3511 |
| PMU with the read interface narrowed    | 20003 | 3511 |
| PMU deleted outright                    | 18534 | 3215 |
| `origin/master`, no PMU at all          | 16800 | 3247 |

The flop count is the mutation check and it is the point of the middle row: it
is **identical** across the first two, so all eight counters are still
instantiated and still counting. Only the interface changed.

### What the old shape was

`perf.vhd` published `perf_regs_t` — eight 32-bit counters, PMOVF, PMCR, PMIDR,
**352 bits** — and `datapath.vhm` selected inside its process, which put an 8:1
32-bit mux in the middle of the largest combinational block in the design. The
reason given (§3, and `perf_pkg.vhd`'s header) was real: handing `perf.vhd` the
P4 address and taking the answer back is a combinational cycle **at cell
granularity**, because yosys treats that whole process as one cell, and this
design has already paid for one false SCC.

### Why that was avoidable

The counter index is three bits of the **data address**, and the data address is
a mux of `xbus`/`ybus`/`zbus` — architecture-level *signals*, every one of them
register-sourced — selected by `mem.addr_sel`, which comes from decode. None of
that is inside the process. So the address is computed **concurrently**
(`ma_ad_c`), the process consumes it through the same `ma_ad` variable as
before, `pmu_idx_o` is a slice of that same net, and `perf.vhd` returns one
selected word. The dependency is registers → `ma_ad_c` → `perf.vhd` → process,
which is acyclic at cell granularity too. `synth/cpu_synth.sh scc` reports
**0 SCCs**, and `check -assert` passes.

`perf_p4_t` carries five words — selected counter, pre-packed `P4_TSBCNT`,
PMOVF, PMCR, PMIDR — 160 bits instead of 352.

### Fmax

16 nextpnr seeds per arm, one netlist P&Rd 16 times, `+/-` is the 95% CI of the
mean:

| arm | Fmax (MHz) | logic / routing |
|-----|-----------:|-----------------|
| whole register file, default placer | 30.97 +/- 0.61 | 7.34 / 25.02 ns |
| narrowed, default placer            | 32.91 +/- 0.85 | 6.69 / 23.79 ns |
| whole register file, `--placer-heap-timingweight 100` | 32.51 +/- 0.41 | 7.50 / 23.27 ns |
| narrowed + timingweight             | 33.85 +/- 0.67 | 6.98 / 22.61 ns |
| `origin/master` for reference (no PMU) | 35.87 +/- 0.40 | 6.04 / 21.85 ns |

**+1.94 MHz** for the narrowing alone, and the 0.65 ns that comes off the LOGIC
half of the path is the mux leaving. The two changes are **sub-additive**
(+1.54 and +1.94 separately, +2.88 together): they are partly the same win seen
twice, since a netlist with 1538 fewer cells is also a netlist the placer finds
easier.

**2.02 MHz of the gap to `origin/master` is still open**, and it is not this
interface: 1734 mapped cells and most of the remaining depth survive deleting
the PMU entirely (the third row of the area table above), so what is left is on
the datapath side of the P4 read path, not in `perf.vhd`.

The critical path no longer touches this interface at all. In both narrowed
arms it runs from a `datapath` state flop into `tlb_walk`'s retry logic and the
debug port.

### The one hazard this shape creates

The **read** index is the concurrent `pmu_idx_o`; the **write** index is still
`pmu_idx_v` inside the process. Two expressions, sharing `ma_ad_c` and
`PMU_CNT_IDX_BITS` so that neither the address mux nor the offset literal is
duplicated — but nothing in the language couples them, and both sites say so.

Keeping them independent is deliberate, and wiring the write index from the
concurrent net too would look tidier while **masking** the failure: both halves
would drift together and a write-then-read would still agree with itself.
Verified by mutation — shifting the concurrent slice by one bit fails
`pmucnt` with result `0x10` (PMINS delta over an 8-nop window is not 8) and
`pmuovf` with result `0x01` (PMWLK does not read back what was written), each
with its own code and neither by timeout.

The sampling boundary of §3.2 is **unchanged**: the read is still served in the
cycle the access is decoded. A variant that registered the index and returned
the counter one cycle later was considered and rejected for exactly that reason
— it would have moved an architecturally visible, documented and guard-pinned
property to save nothing the concurrent form does not already save.

---

## 9. Amendment required in `docs/soc/p4-mmio-map.md`

That map lives in `jcore-workspace`, not in `jcore-cpu`, so this change cannot
carry it.

> **This section is NOT paste-ready, and an earlier revision wrongly said it
> was.** The obvious form — a new §3.4 with its own `Offset | Register |
> Description` table — does not work, for a reason worth writing down because it
> will catch the next person too. `p4-offsets-match-rtl`
> (`scripts/check-doc-facts.py`, Wave-1 task B0c) locates the register table
> with `find_table_by_header`, which returns the **first** table carrying those
> headers, and the map has **exactly one** today (verified by running
> `find_tables_by_header` against the current map: one match, 21 parsed
> name/offset pairs). A second table with the same headers is therefore never
> read.
>
> Nor can the PMU rows simply be appended to §3.2, the table that *is* parsed:
> its offset column is matched by `` ^`0x([0-9A-Fa-f]{2,3})`$ ``, so a row
> written `` `0xFF001000` `` is skipped as unparseable, while a row written
> `` `0x000` `` for PMCR **collides with PTEH at `0x000`** and trips the check's
> duplicate-offset arm. Both were confirmed by running the check's own parsing
> logic, not inferred.
>
> **Nothing in `jcore-cpu` is blocked by this.** The RTL's 12-bit PMU compares
> (§5) mean the check parses exactly the 18 registers it parsed at `a9ffac1`,
> so it stays green when this branch lands. What remains is a *documentation*
> gap, not a red check: the PMU page is allocated in §3 but its registers are
> undocumented. Closing it properly needs one of — a second parsed table
> (`find_table_by_header` → `find_tables_by_header`, plus per-table base
> offsets), or a `Base | Offset | Register | Description` shape, or an explicit
> per-block scoping key. That is a change to B0c's own check and is its owner's
> call, which is why the table below is offered as **content for whatever shape
> they choose** rather than as a patch.

The §3 top-level table's PMU row should also gain a spec link to this document.
The content to place, once the parser can carry it:

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
| `0x040`–`0xFFF` | reserved | genuinely undecoded: the decode compares all 12 offset bits, so these read as hard zero and are NOT aliases of the registers above |

Counters are 32-bit, free-running and WRAPPING, and are **writable** (Linux
`perf` programs a sampling period by preloading one). `0xFF000054` TSBCNT is
unchanged **for software that does not touch this page** and is now served from
`PMWLK[15:0] & PMWHT[15:0]`; clearing `PMCR.EN` freezes it and writing `0x038`
or `0x03C` sets it.
```

The §3.2 note on TSBCNT should also record that the walker no longer holds its
own counters.

---

## 9a. A correction to this branch's own commit messages

Commit `e208745`'s message says "the nine guards that assert exact TSBCNT
deltas are the regression net for the move". **The number nine is wrong**, and
it is wrong because it was copied out of `p4-mmio-map.md` §3.2 ("nine
anti-vacuity guards assert on it") rather than measured. Counted here:

    $ grep -l 0xFF000054 sim/tests/*.S | wc -l
    41

41 of the 157 guard sources in `sim/tests` read `0xFF000054`. The conclusion the
sentence drew is unaffected — the regression net is larger than claimed, not
smaller, and the whole suite passes — but the figure in that commit message
should not be quoted. `p4-mmio-map.md` §3.2 should be corrected too.

Two further claims in `e208745`'s message need the same treatment, because a
commit message cannot be edited after the fact and leaving them unqualified is
how they get quoted:

* **"its architected value is bit-for-bit unchanged"** (of `P4_TSBCNT`) is true
  only for software that never touches the PMU page. Clearing `PMCR.EN` freezes
  the register, and a write to `0xFF001038`/`0xFF00103C` sets it. Both are
  intended and both are privileged, but both are new, and a hypervisor
  virtualizing TSBCNT must virtualize the PMU page with it.
* **the CPUINFO `0x030`/`0x02C` contradiction** it cites as a reason not to use
  the MMU page was **resolved in `p4-mmio-map.md` before that commit was
  written** (§7 item 4, corrected 2026-08-25). The address decision stands on
  the other three grounds in §5; the premise does not. Withdrawn there and in
  the `datapath.vhm` decode comment.

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
