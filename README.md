# J-Core CPU (J1 / J2 / J4)

[![synth-cpu](https://github.com/mountain-reverie/jcore-cpu/actions/workflows/synth-cpu.yml/badge.svg)](https://github.com/mountain-reverie/jcore-cpu/actions/workflows/synth-cpu.yml)
[![full-regression](https://github.com/mountain-reverie/jcore-cpu/actions/workflows/full-regression.yml/badge.svg)](https://github.com/mountain-reverie/jcore-cpu/actions/workflows/full-regression.yml)
[![PR checks](https://github.com/mountain-reverie/jcore-cpu/actions/workflows/pr-quick.yml/badge.svg)](https://github.com/mountain-reverie/jcore-cpu/actions/workflows/pr-quick.yml)
[![synthesis metrics](https://img.shields.io/badge/synthesis%20metrics-dashboard-2b7bb9)](https://mountain-reverie.github.io/jcore-cpu/)

An open-source 32-bit RISC processor implementing the SH-2 (SuperH-2)
instruction set architecture. The repository contains the VHDL hardware
description, a C/VHDL co-simulation testbench, and a Go-based instruction
decoder generator.

## Variants

The J-Core CPU is implemented as a single VHDL entity with three variants
selected via VHDL configurations:

| Variant | Description |
|---|---|
| **J2** | Baseline core targeting ASIC and FPGA; runs Linux no-MMU. Implements the SH-2 ISA plus SH-4 dynamic shift instructions (SHAD/SHLD). 2–3 cycle Karatsuba multiplier. |
| **J1** | Smaller variant targeting iCE40 and other small FPGAs; microcontroller-oriented core. Sequential shift-add multiplier (~34 cycles) replaces the hardware array — same ISA, multiply stalls longer, ~9% fewer cells. |
| **J4** | J2 + full SH-4 extensions targeting complete Linux (MMU, privileged modes, banked registers). Placeholder today — byte-identical to J2 while extensions are developed. |

See [`docs/architecture/cpu-variants.md`](docs/architecture/cpu-variants.md) for
the full design, configuration guide, and build commands.

## 📊 Synthesis metrics dashboard

**<https://mountain-reverie.github.io/jcore-cpu/>**

Every push to `master` synthesizes the core for FPGA (Lattice ECP5) and ASIC
(Nangate45) and publishes the results to GitHub Pages: area, cell/LUT/FF and
hard-block utilisation, timing (WNS/TNS), power, and representative ECP5 Fmax —
tracked per commit, with regression alerts commented on pull requests. The
dashboard is rebuilt from history fetched back off the live site (no `gh-pages`
branch); see [`synth/README.md`](synth/README.md) for the pipeline.

## Architecture

A 5-stage pipelined 32-bit processor (fetch / decode / execute / write-back).
The top-level `cpu` entity (`core/cpu.vhd`) instantiates three sub-units:

- `decode` — instruction decoder with pipeline control
- `mult` — multiplier / MAC unit (multi-cycle, microcode-driven)
- `datapath` — execution datapath (ALU, shifter, register file, buses)

The pipeline description above reflects the **J2** baseline.

See [`CLAUDE.md`](CLAUDE.md) for a full repository map and conventions.

## Build & test

```bash
# Simulator (needs ghdl, gcc, sh2-elf-gcc)
cd sim && make
./cpu_ctb --stop-time=180us

# Regenerate the instruction decoder from the TOML spec (needs Go 1.26+)
make -C decode generate

# End-to-end regression (generator tests + simulator + TAP testbenches)
decode/gen-go/regression.sh

# Synthesis (ASIC + ECP5) and the metrics scripts
cd synth && cat README.md
```

## Repository layout

| Path | Contents |
| --- | --- |
| `core/` | CPU core: datapath, decoder glue, register file, multiplier |
| `decode/` | Generated decoder VHDL + the Go generator (`decode/gen-go/`) |
| `cache/` | I-cache and D-cache |
| `sim/` | GHDL + C co-simulation testbench |
| `testrom/` | SH-2 boot ROM and instruction test programs |
| `tests/` | VHDL component unit testbenches (arith, logic, shifter, …) |
| `synth/` | ASIC/ECP5 synthesis drivers + the metrics pipeline |

## License

See the upstream [j-core](https://j-core.org/) project for licensing.
