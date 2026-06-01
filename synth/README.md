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
    synth/cpu_synth.sh asic   # -> build/cpu_asic.v   (generic gate netlist)
    synth/cpu_synth.sh ecp5   # -> build/cpu_ecp5.json (synth_ecp5 -noabc9; feed to nextpnr-ecp5)

## What CI gates vs reports
The `synth-cpu` workflow **gates** on synthesizability (`check -assert`: no
inferred latches / multi-driver nets) and **ECP5 fit** (nextpnr place-and-route
completes and `ecppack` produces a bitstream). Timing is **reported, not gated**
— see Notes.

## Notes
- Elaborates the `cpu_synth_direct` configuration (adds the `u_mult` binding the
  committed FPGA configs omit). Top entity stays `cpu`.
- The driver strips verification cells before writing the netlist
  (`chformal -remove; delete t:$check t:$print`) — VHDL `assert` statements
  otherwise become `$check`/`$assert` cells that downstream readers reject.
- ECP5 uses `synth_ecp5` with **abc9** (timing-driven mapping). This works
  because the issue/slot false combinational loop is broken in
  `core/datapath.vhm` (slot_o no longer depends on `instr.issue`; the CI guards
  that slot_o stays out of every SCC). The core reaches ~40 MHz on the 85F —
  still under 50, so nextpnr runs with `--timing-allow-fail` and timing is
  reported, not gated. Closing the gap to 50 MHz is separate critical-path work.
  (A residual lighter-`opt` SCC not involving slot_o may remain; abc9 resolves
  it, and CI synthesizes via `synth_ecp5`.)
