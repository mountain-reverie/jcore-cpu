# Handover 3 — Reduce `this_c` fanout / width

**Status:** proposal, not started. Cheapest of the three; also the least certain
to pay.
**Prereq reading:** `docs/j4-ecp5-fmax-findings.md`, and
`.superpowers/sdd/mmu-csr-extraction-feasibility.md` (a rejected variant of this idea).

## The invariant this addresses

Across ~30 builds — both variants, both cores, every seed — the critical-path
**sink is always** `core1.u_cpu.u_datapath.this_c` / `this_r`. Sources vary
freely. Paths are 78–82% routing with ~6 ns of logic.

`this_c` is the combinational next-state of `datapath_reg_t`
(`core/components_pkg.vhd:172`) — the two-process (Gaisler) idiom, where **all**
datapath sequential state lives in one record. Observed net indices reach
`this_c[698]`.

## Width breakdown (from the type definitions)

**J4-only fields:**

| field | bits |
|---|---|
| `mmu : mmu_reg_t` — PTEH, PTEL, ASIDR, MMUCR, TEA, TTB, TSBBR, TSBCFG, TSBPTR | **288** |
| PC shadows — `ma_pc`, `if_pc_next`, `if_pc`, `ma_if_pc`, `tlb_exc_pc` | **160** |
| `ma_base`, `tlb_restore_val` | 64 |
| `priv` — EXPEVT/INTEVT/TRA | 34 |
| `tlb_exc_sr`, `ma_numz`, `tlb_fault_zreg`, 6 single-bit flags | ~40 |
| **J4-only total** | **~585** |

Against roughly 200 bits on J2. **The record that is always the critical-path sink
is ~4× wider on J4** — the best mechanistic explanation we have for the 7.4 MHz
J4 penalty.

## The technique, and its crucial caveat

Register duplication is the standard FPGA remedy for a wide, high-fanout record.
But [Intel's guidance](https://www.intel.com/content/dam/support/us/en/programmable/support-resources/fpga-wiki/asset01/register-duplication-for-timing-closure.pdf)
carries a warning that applies directly to us:

> a large component of FPGA delays come from the actual routes themselves,
> independent of load, so duplicating a register is useful **only if it reduces
> the routing distance**

and each replica's loads must sit *"in a small region on the logic fabric;
otherwise the result is large routing delays due to physical distance."*

Our loads are spread across the die — which is both why duplication *might* help
and why it might not. **This must be measured, not reasoned about.**

## What has already been ruled out — do not repeat

**MMU CSR extraction (288 bits) — NOT VIABLE as scoped.** Investigated in full;
see `.superpowers/sdd/mmu-csr-extraction-feasibility.md`. Two findings:

1. The premise was wrong. `mmu_regs_o` (`core/datapath.vhd:75,1360`) **already
   exports the full 288-bit record every cycle** to the TLB and AT muxes. The CSRs
   are not cold state locked inside the record.
2. The hardware fault capture shares the `tlb_exc_captured` one-shot with
   `tlb_exc_pc`, `tlb_exc_sr`, `tlb_fault_zreg`, `tlb_restore_val/pend` and
   `tlb_squash` — all of which must stay in the datapath. Splitting means
   duplicating a correctness-critical one-shot across two entities, against the
   exact IMISS-persistence bug it exists to prevent.

Also note: only **~70 of the 288 exported bits** are consumed outside the datapath
(`mmucr(0)`, `mmucr(2)`, `asidr(15:0)`, `pteh(31:12)`, `ptel`). `tea`, `ttb`,
`tsbbr`, `tsbcfg`, `tsbptr` are never read outside it. **Narrowing the port does
not help** — those registers stay in `this_c` because STC reads them
combinationally (`core/datapath.vhd:1347-1353`); they are in the record because
they are datapath *state*, not because of the port.

## What remains available

- **Register duplication of `this_c` fanout** — no RTL restructure; try
  `MAX_FANOUT`-style attributes or explicit replication of the highest-fanout
  slices, then measure. Cheapest possible experiment.
- **Partial relocation of software-only CSRs.** `TTB`, `TSBBR`, `TSBCFG` (96 bits)
  are written only by software and never read outside the datapath, so they avoid
  the fault-capture coupling. **The controller's judgement was: not worth it** —
  96 bits of a ~780-bit record is ~12%, well inside the seed spread we are fighting
  (j4-dual ranges 30.08–32.20). Recorded for completeness, not recommended.
- **PC shadow consolidation** (160 bits). `if_pc`/`if_pc_next` and `ma_pc`/`ma_if_pc`
  are suspiciously paired; some may be expressible as deltas. Their comments
  justify each at a distinct pipeline point — read those carefully before touching
  anything, they encode real fault-restart bugs.

## A note on coding style

The two-process idiom is sometimes said to have fallen out of favour. On
investigation the picture is mixed — explicit two-process with signals remains a
defensible default, and single-process-with-variables carries its own combinational
depth warnings. **Either way it is not our Fmax problem:** process count does not
determine the netlist. A single-process rewrite that still bundles ~780 bits into
one record yields the same wide cone. A wholesale `datapath.vhm` restyle would be
an enormous, high-risk refactor of the most exception-critical file in the core for
no measured benefit. **Not recommended as a performance lever.**

## Success criteria

- Any j4 variant clear of its 5-seed spread (j4-rom 33.81–35.67, j4-dual 30.08–32.20).
- **Expect little.** Two prior area reductions bought zero Fmax: the TLB shrink
  (14350 → 13646 cells, −744 LUT4 at SoC level) moved Fmax not at all. At ~80%
  routing, area and speed are only loosely coupled here.

## Risks

- Highest chance of measuring nothing. Timebox it.
- Duplication increases area, which can worsen congestion — the opposite of intent.
- Do **not** re-litigate the MMU CSR extraction without new evidence.

## References

- [Register Duplication for Timing Closure (Intel)](https://www.intel.com/content/dam/support/us/en/programmable/support-resources/fpga-wiki/asset01/register-duplication-for-timing-closure.pdf)
- [A structured VHDL design method (Gaisler)](https://download.gaisler.com/research_papers/vhdl2proc.pdf)
- [Using variables as registers in VHDL — EmLogic, 2024](https://emlogic.no/2024/01/using-variables-as-registers-in-vhdl/)
