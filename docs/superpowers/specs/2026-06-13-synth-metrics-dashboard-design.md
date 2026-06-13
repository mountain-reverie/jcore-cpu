# FPGA/ASIC Synthesis Metrics Dashboard — Design

Date: 2026-06-13
Branch: `synth-metrics-dashboard`
Status: approved (brainstorming)

## Goal

Capture FPGA and ASIC synthesis metrics from the existing `synth-cpu` CI on
every commit, persist them as per-commit history on the `gh-pages` branch,
alert on regressions in pull requests, and render trend, per-block, and
variant-comparison dashboards on GitHub Pages.

The dashboard serves four purposes, all selected during brainstorming:

1. **Historical trend showcase** — public graphs of how the core evolves.
2. **Regression detection** — flag PRs that bloat area, drop Fmax, or grow
   cell/resource counts.
3. **Per-block breakdown** — per-module visibility (decode, datapath, mult,
   register_file), not just whole-CPU totals.
4. **Design-space comparison** — compare variants side by side. This surface
   grows over time as the project adds the SH-4 instruction set, the ROM-based
   decoder table, ROM-width 64, etc.

## Non-Goals

- This project does **not** change the existing synthesizability or FPGA-fit
  **gates**. Those stay exactly as they are. Metrics are *reported*, never
  gated — consistent with the current "timing is reported, not gated" stance
  in `synth-cpu.yml`.
- No new synthesis *backends* or toolchain. We reuse the existing yosys /
  nextpnr-ecp5 / OpenSTA toolchain and the Nangate45 Liberty file already in
  the CI image. (Note: the ASIC *timing/area/power* pass must be **extended
  from the decoder to the full CPU** — see "Toolchain reality check" below.)
- No hard CI failure on regression (initially). Regressions comment + alert
  only; `fail-on-alert: false`. This can be tightened later.

## Metrics Tracked

### ASIC (yosys generic synth + Nangate45 tech-map + OpenSTA)

| Metric | Source | Direction | Scope |
| --- | --- | --- | --- |
| Cell count | yosys `stat` | smaller-better | top + per-block |
| Area (µm²) | yosys `stat -liberty Nangate45` | smaller-better | top + per-block |
| WNS / TNS (ns) | OpenSTA report | bigger-better (less negative) | top only |
| Fmax (MHz) | derived from OpenSTA critical path | bigger-better | top only |
| Power estimate (mW) | OpenSTA `report_power` | smaller-better | top only |

### FPGA (yosys `synth_ecp5` + nextpnr-ecp5, LFE5U-85F)

| Metric | Source | Direction | Scope |
| --- | --- | --- | --- |
| Logic utilisation: TRELLIS_COMB (LUT4) | nextpnr log | smaller-better | top |
| Logic utilisation: TRELLIS_FF | nextpnr log | smaller-better | top |
| Per-block LUT4 / FF | yosys `stat` (pre-P&R, hierarchical) | smaller-better | per-block |
| Fmax per clock (MHz) | nextpnr `Max frequency for clock` | bigger-better | top, per clock |
| Hard blocks: DP16KD, MULT18X18D, ALU54B, TRELLIS_IO, EHXPLLL | nextpnr log | smaller-better | top |

**Scope rationale.** Area / cell / utilisation are per-module quantities, so
they carry a per-block breakdown (`decode`, `datapath`, `mult`,
`register_file`). Timing, Fmax, and power are whole-design properties of the
flattened, placed netlist, so they are tracked top-level only. FPGA per-block
LUT/FF come from yosys's hierarchical `stat` *before* P&R flattens the design —
an estimate, but a consistent one suitable for trend tracking.

## Toolchain Reality Check (what exists vs. what's new)

What the synth flow produces **today**:

- `synth-asic` job: yosys generic synth + `check -assert` (gate) + `stat`
  giving the **cell count only** of the full CPU. No Nangate45 tech-map, no
  area in µm², no OpenSTA, no power.
- `synth-ecp5` job: `synth_ecp5 -noabc9` + nextpnr-ecp5 P&R. The nextpnr log
  already contains TRELLIS_COMB/FF, the hard-block counts, and Fmax per clock.
  FPGA metrics are genuinely parse-only.
- `regression.sh` Step 8: a Nangate45 `dfflibmap`/`abc -liberty` map + OpenSTA
  STA — but applied to the **decoder unit**, not the full CPU.

So FPGA metrics are parse-only, but **ASIC area-µm²/WNS/Fmax/power are new
work**: the toolchain and the Liberty file exist and are proven on the decoder,
yet a full-CPU Nangate45 map + OpenSTA pass must be added. This is an explicit
component below (1a), not hidden in the emitter. ASIC *cell count* is parse-only
from the existing `stat`.

## Architecture (Hybrid)

`github-action-benchmark` is the storage / alerting / PR-comment **engine**; a
custom Chart.js dashboard provides the rich per-block and variant views the
action's fixed per-metric layout cannot.

```
synth-cpu.yml  (runs on PR + master push)
  ├─ [existing] generate decoder → v2p preprocess → cpu_synth.sh asic|ecp5
  ├─ [existing] synthesizability + fit GATES (unchanged)
  ├─ [NEW] synth/cpu_sta.sh        full-CPU Nangate45 map + OpenSTA → reports
  │                                (asic job only; reuses image Liberty + sta)
  ├─ [NEW] synth/metrics.sh        netlist+logs → synth/metrics/<target>.json
  ├─ [NEW] synth/to-gha-bench.sh   canonical JSON → gha-bench-{size,speed}.json
  └─ [NEW] publish-metrics job:
        benchmark-action/github-action-benchmark@v1  (x2: size, speed suites)
          ├─ PR event:     comment + alert,  auto-push = false
          └─ push(master): append to window.BENCHMARK_DATA, auto-push = true

gh-pages branch
  ├─ dev/bench/         action's auto-generated per-metric charts (raw fallback)
  ├─ data.js            window.BENCHMARK_DATA — full history, our source of truth
  └─ index.html, app.js [NEW] custom dashboard reading data.js
```

## Components

### 1a. Full-CPU ASIC timing pass — `synth/cpu_sta.sh` (new)

Extends the proven decoder STA flow to the whole CPU. Single responsibility:
take the generic netlist `build/cpu_asic.v` (written by `cpu_synth.sh asic`),
tech-map it to Nangate45 and run OpenSTA. Mirrors `regression.sh` Step 8:
`read_verilog` → `dfflibmap -liberty $NANGATE_LIB` → `abc -liberty $NANGATE_LIB`
→ write mapped netlist; then `sta` with a virtual clock at a target period,
emitting `report_wns`, `report_tns`, critical-path, and `report_power`. Writes
`build/cpu_asic_mapped.v` and `build/cpu_asic_sta.rpt`. Reuses the image's
`NANGATE_LIB` and `sta`. Best-effort and non-gating: if `sta` or the Liberty
file is absent (local dev), it prints a `WARN` and exits 0 — `metrics.sh` then
emits the ASIC timing/power/area-µm² metrics as absent.

### 1. Metric emitter — `synth/metrics.sh` (new)

Single responsibility: turn the artifacts already produced by the synth flow
into one canonical, tool-agnostic JSON per target. Runs after `cpu_synth.sh`
in each job.

- **ASIC:** cell count from the existing generic `stat`; area in µm² from
  `yosys -p "read_verilog build/cpu_asic.v; stat -liberty $NANGATE_LIB"` for
  top + per-module; WNS/TNS/Fmax/power parsed from `build/cpu_asic_sta.rpt`
  produced by `synth/cpu_sta.sh` (component 1a).
- **ECP5:** `yosys ... stat` on the hierarchical `synth_ecp5` netlist for
  per-module LUT4/FF; parse `build/nextpnr.log` for top-level
  TRELLIS_COMB/FF, the hard-block counts, and Fmax per clock.

Canonical output, e.g. `synth/metrics/asic-nangate45.json`:

```json
{
  "target": "asic-nangate45",
  "variant": "direct-rom72",
  "commit": "<sha>",
  "metrics": [
    {"name": "cpu/area",       "unit": "um2", "value": 48210, "dir": "smaller"},
    {"name": "datapath/area",  "unit": "um2", "value": 19880, "dir": "smaller"},
    {"name": "decode/area",    "unit": "um2", "value": 11020, "dir": "smaller"},
    {"name": "mult/area",      "unit": "um2", "value": 8450,  "dir": "smaller"},
    {"name": "cpu/Fmax",       "unit": "MHz", "value": 71.4,  "dir": "bigger"},
    {"name": "cpu/WNS",        "unit": "ns",  "value": -0.83, "dir": "bigger"},
    {"name": "cpu/power",      "unit": "mW",  "value": 12.6,  "dir": "smaller"}
  ]
}
```

The `dir` field is how the converter routes each metric to the correct
smaller/bigger-better suite (the action's tool type is per-data-file, not
per-metric).

**Failure handling: best-effort, non-gating.** A parse miss emits the metric as
absent and prints a `WARN` line; it never fails the synth job. The metric
emitter runs *after* the existing gates, so a broken parser can never mask a
real synthesizability/fit failure.

### 2. Converter — `synth/to-gha-bench.sh` (new)

Reads all `synth/metrics/*.json`, splits metrics by `dir`, and writes two
files in `github-action-benchmark`'s `customSmallerIsBetter` /
`customBiggerIsBetter` format:

- `build/gha-bench-size.json` — all `dir: smaller` metrics
- `build/gha-bench-speed.json` — all `dir: bigger` metrics

Each entry's `name` carries the target + block prefix so the action's raw view
and our dashboard can both group on it, e.g.
`"asic-nangate45 · datapath/area"`. `unit` is preserved; `extra` carries the
variant string for future faceting.

### 3. CI wiring — extend `synth-cpu.yml` (no new workflow file)

- `synth-asic` gains a `Full-CPU STA` step (`synth/cpu_sta.sh`) after the
  existing synth gate; `synth-asic` and `synth-ecp5` each then gain
  `Emit metrics` (runs `synth/metrics.sh`) and upload `synth/metrics/*.json`
  as artifacts.
- A new `publish-metrics` job `needs: [synth-asic, synth-ecp5]`, downloads both
  metric artifacts, runs `synth/to-gha-bench.sh`, then runs
  `benchmark-action/github-action-benchmark@v1` twice (size + speed suites)
  with:
  - `tool: customSmallerIsBetter` / `customBiggerIsBetter`
  - `comment-on-alert: true`, `alert-threshold: "110%"`, `fail-on-alert: false`
  - `auto-push: ${{ github.event_name == 'push' }}`
  - `gh-pages-branch: gh-pages`, `benchmark-data-dir-path: dev/bench`
- A `deploy-pages` step (or job) publishes the `dashboard/` static files
  alongside `data.js` on `gh-pages`.

PR runs comment + alert but never push history; only master pushes append to
`window.BENCHMARK_DATA`. Standard `github-action-benchmark` behavior, keeps the
history clean.

### 4. Custom dashboard — `dashboard/` → deployed to `gh-pages` (new)

Vanilla JS + Chart.js, gcc-sh-monitor style. Reads the action's `data.js`
(`window.BENCHMARK_DATA`). Three views:

- **Trends** — line charts per metric over commits, faceted by target
  (asic-nangate45, ecp5-lfe5u-85f). Click a point → link to the commit.
- **Per-block** — stacked bar/area of `decode / datapath / mult /
  register_file` contribution to total area (and to LUT/FF), over time.
- **Variants** — latest-value comparison table across variants, one row per
  variant. Starts with a single row (`direct-rom72`) and grows as ROM-table /
  ROM-width-64 / SH-4 variants are added — no restructuring required.

The action's auto-generated `dev/bench/index.html` remains reachable as a raw
per-metric fallback.

## Data Model & Extensibility

- A **variant** is identified by the `variant` string in the canonical JSON
  (today: `direct-rom72`). Adding a variant = run the synth flow with a
  different config and emit with a new `variant` value. The converter and
  dashboard fan out automatically.
- A **target** is `<flow>-<part>` (today: `asic-nangate45`,
  `ecp5-lfe5u-85f`). New nodes/parts add targets the same way.
- Metric `name` is always `<block>/<metric>` so per-block and top-level
  (`cpu/...`) share one namespace.

## Testing

- `synth/metrics.sh`: unit-tested against **captured fixture logs** — a saved
  `nextpnr.log`, an OpenSTA report, and a yosys `stat` dump checked into
  `synth/tests/fixtures/`. Asserts the canonical JSON. No synthesis run needed
  to test parsing, so the test is fast and hermetic.
- `synth/to-gha-bench.sh`: fed a fixture canonical JSON, asserts valid
  action-format output and correct size/speed routing.
- Dashboard: a tiny committed `data.js` fixture + manual open. Optional
  Playwright smoke test as a follow-up (project already uses Playwright CI).

## Open Risks

- **Per-block area requires a hierarchical netlist.** `synth -top cpu` in
  `cpu_synth.sh` may flatten before writing `build/cpu_asic.v`. `metrics.sh`
  re-runs `stat -liberty` on that netlist; if it is already flat, per-block
  area is unavailable and we fall back to top-level only plus a `WARN`. Verify
  during implementation; if needed, produce a separate `keep_hierarchy` stat
  netlist without disturbing the gating netlist. Same caveat applies to ECP5
  per-block LUT/FF (hierarchical `stat` on the `synth_ecp5` netlist).
- **Full-CPU STA may be expensive or fail to converge** where the decoder pass
  was cheap. `cpu_sta.sh` is non-gating and time-boxed (`timeout`, as Step 8
  does); on timeout the ASIC timing metrics are simply absent for that commit.
- **OpenSTA power** depends on activity assumptions; treat as a rough trend
  number, label it as such on the dashboard.
- **nextpnr Fmax** is an estimate and run-to-run noisy; the 110% alert
  threshold and non-failing policy account for this.
