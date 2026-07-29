# Handover 1 — VIPT caches: take address translation off the critical path

**Status:** proposal, not started. Largest of the three, addresses the root cause.
**Prereq reading:** `docs/j4-ecp5-fmax-findings.md` (measurement methodology, retracted figures).

## The problem, measured

ULX3S, 5 seeds per variant, jcore-soc master `17b43cd` / jcore-cpu `6711ebb`:

| variant | mean | range |
|---|---|---|
| j2-direct | 41.40 | 40.33–42.52 |
| j2-dual | 38.61 | 37.20–39.12 |
| j4-rom | 34.70 | 33.81–35.67 |
| j4-dual | 31.22 | 30.08–32.20 |

**J4 costs ~7.4 MHz** with core count and decoder held constant (j2-dual vs j4-dual).
Dual-core costs only ~2.8 MHz; the ROM decoder is roughly neutral. J4 is the
dominant term.

**Every** critical path measured — ~30 builds, both variants, every seed — ends at
`core1.u_cpu.u_datapath.this_c` / `this_r`. Sources vary freely (dcache tag BRAM,
icache control, bus mux, the core's own data master). Paths are **78–82% routing**
with only ~6 ns of logic.

## Why this is architectural, not incidental

`docs/architecture/j4.md` states the design plainly:

> the TLB combinationally selects a matching entry … and relocates the virtual
> address to the physical address so the L1 caches are **physically indexed (PIPT)**

**PIPT serialises translation ahead of cache access, in the same cycle.** Address
translation is inherently on the memory-access critical path — no access can
proceed until the VA is translated.

The historical fix, adopted by essentially every performance CPU since the MIPS
R4000 (ARM, x86, modern RISC-V cores), is **VIPT**: index the L1 with untranslated
VA offset bits *in parallel* with the TLB lookup, then compare the physical tag
afterwards. Translation stops preceding the access and overlaps it instead.

## Why this explains our data specifically

It accounts for all four observations that other hypotheses did not:

- why J4 costs 7.4 MHz while J2 does not (J2 has no translation step at all)
- why the datapath state record is the invariant sink (translation results feed it)
- why shrinking the TLB bought **zero** Fmax (`tlb_Brtl` 14350 → 13646, no gain)
- why paths are routing-dominated with shallow logic

## The catch, and the encouraging sign

VIPT permits **virtual aliasing**: two VAs mapping one PA can land in different
sets. Standard mitigations are page colouring (software) or constraining
`way size ≤ page size` (hardware).

**This repo already has `sim/dcache_color_tb`** — page colouring is a *VIPT*
concern, so aliasing may already have been considered here. Read that testbench
first; it may reveal prior thinking, or an existing partial mechanism.

## Suggested approach

1. **Establish the constraint arithmetic before designing.** What is
   `CACHE_INDEX_BITS` (`cache/cache_pkg.vhd`, 8 = 8 KB default), the associativity,
   and the minimum page size (4 KB, `pm=0`)? If `way size ≤ page size` already
   holds, VIPT is alias-free *by construction* and the whole problem collapses to
   a wiring change. **Check this first — it is cheap and it decides the scope.**
2. Read `sim/dcache_color_tb` and `docs/architecture/tlb.md` for existing aliasing
   assumptions.
3. Only then design the index/tag split.

## Success criteria

- ULX3S **j4-dual** above 32.20 (its current 5-seed max) and **j4-rom** above 35.67,
  both by more than the seed spread. Use 5 seeds; see the findings doc for why.
- The critical-path source should stop being translation-adjacent. If the sink
  remains `this_c` but Fmax rises, that is still a win — the sink is a placement
  attractor, not necessarily the cause.
- MMU guard regression **60 PASS / 0 FAIL** (`sim/mmu_sim.sh`).

## What would falsify the hypothesis

If the TLB is *not* actually in series with cache indexing today — i.e. the
translation fold at `core/cpu.vhd:434-457` is already off the binding path — then
VIPT buys nothing. **Verify this against a real critical-path report before
building anything.** Two prior restructures in this project were justified on
plausible reasoning and measured worse.

## Risks

- Largest of the three proposals; touches cache indexing and the MMU contract.
- Aliasing bugs are data-dependent and may not surface in the guard suite.
- Prior art warning: the two-level TLB reproduced a micro-TLB *structure* without
  the property that makes it pay in industry (pipelined lookup with hardware
  refill). It cost +7.7% area, 21 broken guards and 6 MHz. Do not repeat that
  pattern — confirm the mechanism applies here before committing.

## References

- [Utopia: address translation is on the critical path](https://arxiv.org/pdf/2211.12205)
- `docs/architecture/j4.md` (PIPT statement), `docs/architecture/tlb.md`
