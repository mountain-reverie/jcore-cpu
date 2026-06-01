# CPU synthesis (ASIC + ECP5)

`cpu_synth.sh` is a thin driver: it assembles the cpu VHDL file list and runs
one `yosys -m ghdl` invocation to produce a netlist. All orchestration lives in
`.github/workflows/synth-cpu.yml`.

## Local prerequisites
- ghdl 6.x + yosys 0.44 + ghdl-yosys-plugin (`yosys -m ghdl -p 'help ghdl'`)
- Go toolchain (for `make -C decode generate`)
- a checkout of `j-core/jcore-soc` (provides `tools/v2p`)
- ECP5 P&R also needs `nextpnr-ecp5` + `ecppack` (e.g. via oss-cad-suite)

## Prepare inputs
    make -C decode generate
    JS=/path/to/jcore-soc
    for f in core/mult core/datapath decode/decode_core; do
      LD_LIBRARY_PATH='' perl "$JS/tools/v2p" < "$f.vhm" > "$f.vhd"
    done

## Synthesize
    synth/cpu_synth.sh asic    # -> build/cpu_asic.v    (generic gate netlist)
    synth/cpu_synth.sh ecp5    # -> build/cpu_ecp5.json  (bare cpu; feed to nextpnr-ecp5)
    synth/cpu_synth.sh timing  # -> build/cpu_timing.json (cpu_timing_top harness; Fmax gate)

## What CI gates vs reports
The `synth-cpu` workflow **gates** on:
- synthesizability (`check -assert`: no inferred latches / multi-driver nets),
- **ECP5 fit** (nextpnr P&R completes and `ecppack` produces a bitstream), and
- a **representative-Fmax floor** measured on the `cpu_timing_top` harness
  (`ECP5_FMIN_MHZ`, currently 40), so frequency can't silently erode.

The *bare-cpu* ECP5 Fmax is **reported, not gated** — it's depressed by the
unconstrained-IO measurement artifact (see `cpu_timing_top.vhd` header).

## Why two ECP5 measurements
The bare `cpu` exposes ~348 ports as pads; synthesized alone on the sparse 85F
that scatters the core and inflates routing, so its reported Fmax (~40 MHz) is a
measurement artifact, **not** a logic-depth or placement-density problem (proven:
Fmax is flat ~42 MHz across 6%–23% device utilisation). `cpu_timing_top`
registers the boundary down to 4 IO, giving the true register→core→register
Fmax (~42–43 MHz) that the regression gate measures.

## Notes
- Elaborates the `cpu_synth_direct` configuration (adds the `u_mult` binding the
  committed FPGA configs omit). Top entity stays `cpu`.
- The driver strips verification cells before writing the netlist
  (`chformal -remove; delete t:$check t:$print`) — VHDL `assert` statements
  otherwise become `$check`/`$assert` cells that downstream readers reject.
- ECP5 uses `synth_ecp5` with **abc9** (timing-driven mapping). This works
  because the issue/slot false combinational loop is broken in
  `core/datapath.vhm` (slot_o no longer depends on `instr.issue`; the CI guards
  that slot_o stays out of every SCC). nextpnr runs with `--timing-allow-fail`,
  and the `cpu_timing_top` harness Fmax (~42–43 MHz) is gated against
  `ECP5_FMIN_MHZ`. Reaching 50 MHz needs microarchitectural work (the path is
  ~6 ns logic + ~18 ns intrinsic routing through the regfile-read/MAC-accumulate
  datapath; the multiplier output is already registered) — deferred to a future
  pipelining project. (A residual lighter-`opt` SCC not involving slot_o may
  remain; abc9 resolves it, and CI synthesizes via `synth_ecp5`.)

## Synthesis metrics dashboard

Every push to `master` publishes FPGA/ASIC synthesis metrics to GitHub Pages
(`https://<owner>.github.io/jcore-cpu`). PRs get a regression comment but do not
update the published history. The site is the database — history is bootstrapped
each run by fetching the prior `bench-{size,speed}/benchmark-data.json` back
from the live site (no `gh-pages` branch).

One-time setup: repo Settings → Pages → Source = "GitHub Actions".

Pipeline (in `.github/workflows/synth-cpu.yml`):
1. `synth-asic` / `synth-ecp5` run the existing synth flow, then
   `synth/cpu_sta.sh` (full-CPU OpenSTA, ASIC only) and `synth/metrics.py`
   emit `synth/metrics/<target>.json`.
2. `publish-pages` merges them via `synth/to_gha_bench.py`, runs
   `github-action-benchmark` (size = smaller-better, speed = bigger-better),
   and on `master` deploys the dashboard via the Actions Pages pipeline.

Tracked metrics: ASIC cell count, area (µm²), WNS/TNS, Fmax, power (Nangate45);
ECP5 LUT4/FF utilisation, hard blocks (DP16KD/MULT18X18D/ALU54B/IO/PLL), and
Fmax per clock. Area/utilisation carry a per-block breakdown
(decode/datapath/mult/register_file); timing and power are whole-CPU only.

Reproduce a metric locally (requires the CI image toolchain):

    make -C decode generate
    JS=/path/to/jcore-soc
    for f in core/mult core/datapath decode/decode_core; do \
      LD_LIBRARY_PATH='' perl "$JS/tools/v2p" < "$f.vhm" > "$f.vhd"; done
    synth/cpu_synth.sh asic && synth/cpu_sta.sh
    python3 synth/metrics.py --target asic-nangate45 --commit local \
      --out /tmp/m.json --stat build/cpu_asic_mapped_stat.txt \
      --sta build/cpu_asic_sta.rpt --period-ns 20

Run the parser unit tests (no toolchain needed):

    cd synth/tests && python3 -m unittest -v
