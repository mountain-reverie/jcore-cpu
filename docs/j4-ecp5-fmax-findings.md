# J4 ECP5 Fmax: measured findings

**Board:** ULX3S (LFE5U-85F, CABGA381), variant `j4-rom`
**Flow:** ghdl → yosys `synth_ecp5` → nextpnr-ecp5 → ecppack, via `jcore-soc/tools/fpga/soc_fmax.sh`
**Date:** 2026-07-28

Every number here is measured. Where something is unverified it says so.

## Why seeds matter — read this before quoting any figure

nextpnr's placer is seed-sensitive on this design. Single-seed numbers have
produced two wrong conclusions in this investigation already, so:

**A single-seed Fmax measurement is not a result.** Quote a 5-seed mean and
range, and compare distributions rather than point values.

Worked example of the trap: a TLB change measured **36.45 MHz** on one seed
against a 33.91 MHz baseline and was reported as a +2.5 MHz improvement,
including in a merged PR description. A later 5-seed run of the *same tree* gave
**33.82 mean, range 33.21–34.59** — Fmax-neutral. 36.45 was above even that
tree's own 5-seed maximum. **That figure is retracted.**

## Current state

| tree | mean | range | seeds |
|---|---|---|---|
| cpu `850fb17` (pre-bump baseline) | 33.91 | — | 5 |
| cpu `850fb17` + TLB install-overlap fix | 33.82 | 33.21–34.59 | 5 |
| cpu `c58528f` (current master) | **32.75** | 32.53–32.96 | 5 |
| current master, `ILLEGAL=none` | **35.46** | 34.69–36.15 | 5 |

## Finding 1 — the TLB install-overlap fix is Fmax-neutral

33.82 vs a 33.91 baseline. The fix is worth having for its correctness bug (a
4 KB page installed inside a resident 1 MB superpage no longer becomes a fatal
S-I5 multi-hit) and for a ~5% TLB area reduction (`tlb_Brtl` 14350 → 13646,
independently corroborated by SoC-level LUT4 −744, flip-flops unchanged). It is
**not** an Fmax lever.

## Finding 2 — a ~1.1 MHz regression landed in the `850fb17..c58528f` bump

33.82 → 32.75. The two trees differ *only* by those commits; both are
`850fb17`-based and both carry the TLB fix.

**Every one of the five pre-bump seeds beat every one of the five post-bump
seeds** (33.21 min vs 32.96 max). Non-overlapping distributions — a permutation
test on 5-vs-5 with clean separation gives p ≈ 0.004. This is a real regression,
not seed noise.

## Finding 3 — illegal-instruction decode costs ~2.7 MHz, and is the dominant lever

Rebuilding current master with `make -C decode generate ILLEGAL=none` gives
**35.46 mean (34.69–36.15)**, clearing both other ranges with no overlap.

The diff is **one file, six lines**: `decode_body.vhd`'s per-nibble
illegal-instruction boolean in `illegal()` becomes `return '0'`. Attribution is
therefore unusually clean.

It recovers *more* than the bump removed (+1.6 MHz above even the pre-bump
33.82), because `ILLEGAL=none` strips the whole function, including checking
that predates the bump. So illegal-instruction decode has been on the critical
path all along; the recent exhaustive per-nibble work deepened it.

**`ILLEGAL=none` is a diagnostic, not a shippable configuration.** It removes
illegal-instruction trapping, which is architecturally required and guarded by
`j4_illegal_trap`. It measures where the time goes; it is not a fix.

### Where the time goes

| build | logic ns | routing ns | routing % | edges |
|---|---|---|---|---|
| master | 5.5–7.0 | 23.3–24.6 | 78–81% | posedge → posedge |
| `ILLEGAL=none` | 6.1 | 21.8 | 78% | posedge → posedge |

The **sink is consistently `soc.cpus.core0.u_cpu.u_datapath.this_r`**, reached
through a cone crossing `u_decode.core.delay_jump` and `t_bcc`.

The **source moves**. On master it lands on the decoder, the boot RAM
(`bootram_infer`), the icache, or the core's own data-master register depending
on seed — structurally-equivalent long paths shuffling under the placer, which
is what the 0.43 MHz band looks like. With `ILLEGAL=none` the source moves *off*
the decoder in 4 of 5 seeds (to `icache_ccl` or `data_master_o`).

That is the useful part: `illegal()` adds depth and fanout to the decode side of
the cone feeding `this_r`. Remove it and the decoder stops being the dominant
contributor.

## The candidate fix, not yet attempted

`illegal` is a **trap** signal. Unlike a mux select it does not obviously need
to resolve combinationally in the cycle the instruction decodes — registering it
one stage would take it off the critical path while preserving behaviour.

**This is unverified.** Whether a cycle of delay is compatible with this core's
precise-exception contract is a real design question and must be answered
against the RTL before anyone builds it.

## Levers that are exhausted or counter-indicated

- **Half-cycle paths: exhausted for `j4-rom`.** All 16 builds across this
  investigation confirm posedge → posedge. The 25.11 → 33.91 jump (+35%) came
  from eliminating a `posedge → negedge` read in `bootram_infer`, and that class
  of win is gone at this pin. Still worth checking on other variants — it is
  worth ~2× when present, because a half-cycle path gets half the period.
- **Floorplanning: counter-indicated.** A prior attempt gained +5.7% and was
  superseded by a rising-edge fix worth +27%. Routing here looks like general
  congestion and distance, not one fixable BRAM-column relationship.
- **Shrinking logic does not reliably buy Fmax.** The TLB fix removed 744 LUT4s
  at SoC level and bought nothing. At ~80% routing, area and speed are only
  loosely coupled on this design.

## Pattern worth remembering

This is the second decoder change to cost ECP5 Fmax on this core (see the
base-decoder J4-overlay regression). **The decode cone feeding `this_r` is
load-bearing for timing** — decoder changes deserve a synthesis check, not only
a functional one.

## Reproducing

```bash
# 5-seed sweep; the positional arg is the nextpnr seed
cd jcore-soc
for s in 1 2 3 4 5; do tools/fpga/soc_fmax.sh j4-rom "$s"; done

# the ILLEGAL=none diagnostic (regenerates decoder tables --
# NEVER commit them; restore with: git checkout -- decode/)
make -C components/cpu/decode generate ILLEGAL=none
```

Builds are ~3 min each and deterministic at a given seed.
