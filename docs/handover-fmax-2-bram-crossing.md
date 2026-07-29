# Handover 2 — Pipeline register at the BRAM → datapath crossing

**Status:** proposal, not started. Incremental; textbook remedy; matches a
measured path directly.
**Prereq reading:** `docs/j4-ecp5-fmax-findings.md`.

## The measured path this addresses

From a retained nextpnr log, **j2-dual at 37.20 MHz (26.9 ns total, 9.9 ns logic /
16.9 ns routing)**:

| # | stage | cost |
|---|---|---|
| 1 | `ddr_ram_mux.u_dcache1.u_dcache_ram.tag0.mem.DOA5` — dcache tag **BRAM** clock-to-out | **5.6 ns** |
| 2 | 20 cell hops through `udcache_ccl.this_c` — cache-control LUT cascade | ~11 ns |
| 3 | `core1.u_cpu.t_bcc` — branch-condition mux at die grid **(92,50)** | 0.3 ns |
| 4 | **one net → `u_datapath.this_c.D` at grid (39,67)** — 53 columns | **4.5 ns** |
| 5 | → `core1.u_cpu.u_datapath.this_r` | setup |

The chain crosses **two subsystems combinationally in one cycle**: dcache tag read
→ hit/control resolution → branch-condition mux → CPU datapath register.

## The technique

The timing-closure literature recommends additional pipeline registers precisely
*"in datapath regions spanning distant CLB columns or crossing BRAM/DSP
boundaries"* — which is literally stages 1→2 and 3→4 above.

There is also **direct precedent in this codebase**: commit `8609f29` fixed the
dual-core `shared_ram` half-cycle path by moving to a rising edge plus a wait
state, worth **+27%** on j4-dual at the time. The shape is the same — a long
cross-subsystem path broken by a register, paid for with a wait state.

## IMPORTANT CAVEAT — read before designing

**This chain is one placement instance, not the invariant.** Two j4-dual seeds
show *different* sources:

| build | source | logic | routing |
|---|---|---|---|
| j2-dual 37.20 | dcache1 tag BRAM | 9.9 | 16.9 |
| j4-dual 32.20 | `core1.data_master_o` FF | 6.7 | 24.4 |
| j4-dual 30.08 | `icache1.uicache_ccl.a[en]` FF | 6.1 | 27.1 |

Only the **sink** (`core1…u_datapath.this_c/this_r`) is invariant. So registering
the dcache-hit path may fix one seed's binding path and leave the others intact —
the controller initially over-read the single j2-dual log and drew exactly that
wrong conclusion.

**Consequence:** this proposal is most defensible for **j2-dual**, where logic
depth is genuinely high (9.9 ns) and the BRAM chain was observed binding. On
j4-dual there is only ~6 ns of logic total, so breaking a combinational chain has
little to give — that variant is routing-bound and better served by Handover 1 or 3.

## Suggested approach

1. Re-run j2-dual across 5 seeds retaining each nextpnr log, and check how often
   the dcache-tag→datapath chain actually binds. If it binds on 1 of 5, this is a
   placement lottery, not a structure — **stop here**.
2. If it binds consistently, read how dcache hit/miss reaches the datapath
   (`cache/dcache_*.vhm`, `ddr_ram_mux`, and the load interlock in
   `core/datapath.vhm`) and determine whether a cycle of latency is tolerable —
   the same question that killed the `illegal`-signal pipelining idea (see
   `.superpowers/sdd/illegal-pipelining-assessment.md`).
3. Follow the `8609f29` pattern: register + wait state, not an edge change.

## Success criteria

- **j2-dual** 5-seed mean above its current 38.61, clear of the 37.20–39.12 spread.
- No regression on j2-direct (41.40) — it has one cache and one core, so the
  change should be neutral there. A drop means the wait state is costing more
  than the timing gained.
- Guards green; cache scoreboards (`dcache scoreboard (sc)`/`(dc)` in CI) pass.

## Risks

- A wait state costs IPC. Measure cycles, not just MHz — a faster clock that
  stalls more can be a net loss.
- Beware of "fixing" a path that only binds on one seed.
- `sim/mmu_sim.sh` and the cache scoreboards must both stay green.

## References

- [Practical Timing Closure in FPGA and ASIC Designs](https://arxiv.org/pdf/2510.26985)
- commit `8609f29` (dual-core `shared_ram` rising-edge + wait state, +27%)
