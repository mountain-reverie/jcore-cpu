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
    synth/cpu_synth.sh asic   # -> build/cpu_asic.v   (generic; feed to Nangate45/OpenSTA)
    synth/cpu_synth.sh ecp5   # -> build/cpu_ecp5.json (synth_ecp5 -noabc9)

## Notes
- Elaborates the `cpu_synth_direct` configuration (adds the `u_mult` binding the
  committed FPGA configs omit). Top entity stays `cpu`.
- ECP5 uses `synth_ecp5 -noabc9`: the cpu has one false combinational SCC
  (datapath+decode forwarding) that abc9 rejects; generic abc and production
  Xilinx/Altera tolerate it. `build/scc_report.txt` records it.
