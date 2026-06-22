# MMU-enabled ASIC synthesis for j4c (J4 + MMU + cache)

Branch `mmu/m3-miss`, worktree `/home/cedric/work/jcore/jcore-cpu-m3hard`.

## Goal
Enable `MMU_ARCH=true` for the `j4c` ASIC synth so the real J4+MMU+cache core
(TLB/CAM, D-store fault squash, MMU CSR register file, exception-detect, VIPT
seam) is actually synthesized and `check -assert`-gated — previously every
variant built with `MMU_ARCH=false`, so the MMU hardware was never synthesized
and its area/timing cost was invisible.

## Changes (file-by-file, tracked sources only)

1. **`synth/cpu_cache_timing_config.vhd`** — added configuration
   `cpu_cache_timing_j4_priv_mmu`, identical to `cpu_cache_timing_j4_priv` but
   binds `u_cpu` to `work.cpu_synth_j4` with
   `generic map (PRIV_ARCH => true, MMU_ARCH => true)`. The generic map sits on
   the configuration-of-cpu binding, so `MMU_ARCH` reaches the cpu entity
   directly — no threading through `cpu_synth_j4_config.vhd` was needed
   (`cpu_synth_j4` is a `configuration of cpu`, not a wrapper entity).

2. **`synth/cpu_synth.sh`** — for `SYNTH_VARIANT=j4c`:
   - `AREA_TOP` set to `cpu_cache_timing_j4_priv_mmu` (was `..._j4_priv`).
   - Added a synth-time `make -C decode generate-j4` so the J4 overlay decoder
     (the `mmu_reg_*` control signals that `cpu.vhd` references under
     `MMU_ARCH`) is generated transiently. The committed base tables are NOT
     touched: this regeneration runs inside the synth step on an ephemeral
     checkout; the CI decoder gate regenerates the BASE tables in a separate job.
   - j1/j2/j4/j2c branches untouched → byte-identical synth.

3. **`core/datapath.vhm`** (regenerated to `core/datapath.vhd` via jcore-soc
   `tools/v2p`; the `.vhd` is a gitignored artifact) — **MMU-hardware synth
   fix**, see below. Change is entirely inside `if MMU_ARCH then`, so
   MMU_ARCH=false (j1/j2/j4/j2c) elaborates byte-identically.

No change to committed decode tables, no change to `.github/workflows/synth-cpu.yml`
(the self-contained script regeneration covers j4c; touching the workflow would
double-generate and add no value).

## Synthesizability result + MMU-hardware issue found & fixed

First MMU build FAILED `check -assert` with **6 combinational-loop problems**,
all on net `datapath.p4_sel_v`:

```
Warning: found logic loop in module datapath_Bstru_...:
    cell :3521 ($mux)  wire \datapath.p4_sel_v [0..2]
ERROR: Found 6 problems in 'check -assert'.
```

Root cause (real MMU-hardware defect surfaced for the first time by synthesis):
in the datapath P4-MMIO decode (`core/datapath.vhm` ~line 490), the process
variable `p4_sel_v : mmu_reg_sel_t` is assigned only on the three address
matches (`x"08"`/`x"0C"`/`x"10"` → SEL_TTB/SEL_TEA/SEL_MMUCR) and then read in
the read/write `case p4_sel_v`. On any other address it is read holding the
value from the **previous process iteration** → an unconditional read-before-write
on a process variable, which yosys synthesises as a combinational feedback loop.

Fix: default `p4_sel_v := SEL_PTEH;` before the conditional assignments.
`SEL_PTEH` is a "none of TTB/TEA/MMUCR" sentinel here — it falls into the
`case ... when others` branch in both the write (no CSR written) and read
(`m_dr_next := 0`) paths, which is exactly the pre-fix intended behaviour for a
non-matching address. PTEH/PTEL/ASIDR are never P4-MMIO selected (they are LDC
targets), so reusing SEL_PTEH as the default is semantically safe. The
`mmu_reg_sel_t` enum (`decode/decode_pkg.vhd`) has no SEL_NONE, hence SEL_PTEH.

After the fix: **`check -assert` → "Found and reported 0 problems"**, EXIT=0,
`build/cpu_asic.v` written. No inferred latches, no comb loops, no multi-driver
in the TLB/CAM, store-squash, exception-detect, or `mmu_o`.

## Cell counts (yosys `read_verilog build/cpu_asic.v; flatten; stat`)

| build                                  | flat cells | delta            |
|----------------------------------------|-----------:|------------------|
| j4c PRIV-only baseline (MMU_ARCH=false)|   542,091  | —                |
| j4c PRIV+MMU (MMU_ARCH=true)           |   551,106  | **+9,015 (+1.66%)** |
| j2c (sanity, base decoder, unchanged)  |   541,251  | builds clean     |

+9,015 cells is the MMU's ASIC cost (TLB CAM + NRU + VIPT seam + MMU CSR file +
D-store fault squash + exception-detect). No nangate45 lib locally, so Fmax is
NOT measured — synthesizability + cell count is the local gate.

## Decoder gate
PASS. After `make -C decode clean && make -C decode generate`, `git status` shows
NO diff on the committed decode tables — the j4c `generate-j4` output is a pure
synth-time transient, fully reverted by a clean base regeneration. CI pr-quick
Step 2 still holds.

## Constraints check
- j1/j2/j4/j2c synth byte-identical: yes (only the j4c branch and MMU_ARCH-gated
  VHDL changed; j2c re-verified building clean).
- Committed decode tables untouched: yes.
- Only tracked changes: `core/datapath.vhm`, `synth/cpu_cache_timing_config.vhd`,
  `synth/cpu_synth.sh`.

## Concerns
- Local gate is synthesizability + cell count only; Fmax/timing cost of the
  MMU is NOT measured here (no Nangate45 lib). CI's ASIC timing flow will report
  it.
- The `p4_sel_v` read-before-write was a latent defect in committed MMU source
  that only surfaced once the hardware was actually synthesized — the exact kind
  of finding this task aimed to expose. Fix is minimal and behaviour-preserving.
