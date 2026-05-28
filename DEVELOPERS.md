# J-Core J2 CPU - Developer Guide

[![pr-quick](https://github.com/j-core/jcore-cpu/actions/workflows/pr-quick.yml/badge.svg)](https://github.com/j-core/jcore-cpu/actions/workflows/pr-quick.yml)
[![full-regression](https://github.com/j-core/jcore-cpu/actions/workflows/full-regression.yml/badge.svg)](https://github.com/j-core/jcore-cpu/actions/workflows/full-regression.yml)

## What Is This?

The J-Core J2 is an open-source 32-bit RISC CPU core implementing the **SH-2 (SuperH-2)** instruction set architecture. The hardware is described in VHDL, synthesizable to FPGA, and comes with a full simulation and test environment.

The SH-2 ISA uses fixed-width 16-bit instructions with a 32-bit datapath, 16 general-purpose registers (R0-R15), and a 5-stage pipeline (fetch, decode, execute, writeback). It supports multiply-accumulate (MAC) operations, a barrel shifter, and an optional coprocessor interface.

This project was originally developed by Smart Energy Instruments Inc. (2015) and later by CoreSemi Pte Ltd. (2020). It is released under a BSD 2-Clause license.

- Repository: https://github.com/j-core/jcore-cpu
- License: BSD 2-Clause (see `LICENSE`)

## System Requirements

### Required Tools

| Tool | Purpose | Install |
|------|---------|---------|
| **GHDL** | VHDL simulator and compiler | Package manager or [github.com/ghdl/ghdl](https://github.com/ghdl/ghdl) |
| **GCC** | C compiler for testbench and `.vhm` preprocessing | System package (`gcc`, `build-essential`) |
| **GNU Make** | Build system | System package (`make`) |

### For Running Test ROMs

| Tool | Purpose | Install |
|------|---------|---------|
| **sh2-elf-gcc** | SH-2 cross-compiler toolchain | Build from source or use [buildroot](https://buildroot.org/) / [crosstool-NG](https://crosstool-ng.github.io/) |
| **sh2-elf-ld** | SH-2 linker | Included with cross-compiler toolchain |
| **sh2-elf-objcopy** | Binary conversion | Included with cross-compiler toolchain |

### For Regenerating the Instruction Decoder (optional)

| Tool | Purpose | Install |
|------|---------|---------|
| **Go 1.26+** | Go toolchain for the cpugen generator | [go.dev/dl](https://go.dev/dl/) or `sudo apt install golang-go` |

### Optional Tools (gated by regression.sh skip paths)

| Tool | Purpose | Install |
|------|---------|---------|
| **Iverilog** | Alternative Verilog simulation | Package manager (`iverilog`) |
| **GTKWave** | Waveform viewer for `.ghw` files | Package manager (`gtkwave`) |
| **sh2-elf-gcc** (Step 6) | SH-2 cross-compiler for sim/tests | Build from source — see `decode/gen-go/docs/sh2-elf-build.md` |
| **yosys + ghdl-yosys-plugin** (Step 7) | Synthesis check of generated decoder | See "Installing Optional Synthesis Tools" below |
| **openSTA + Nangate45** (Step 8) | Static timing analysis | See "Installing Optional Synthesis Tools" below |

### Installing on Debian/Ubuntu

```bash
# Core tools
sudo apt install ghdl gcc make

# For waveform viewing
sudo apt install gtkwave

# For decoder regeneration (optional)
# Install Go 1.26+: https://go.dev/dl/
# or: sudo apt install golang-go
```

### Installing on Arch Linux

```bash
sudo pacman -S ghdl-gcc gcc make gtkwave go
```

### Installing on macOS

```bash
brew install ghdl gcc make gtkwave go
```

## Repository Layout

```
jcore-cpu/
├── cpu2j0_pkg.vhd       # Top-level CPU interface (ports, types, signals)
├── build.mk             # Build configuration
├── build_core.mk        # Core VHDL file list
├── core/                # CPU core implementation
│   ├── cpu.vhd          #   Top-level entity (structural)
│   ├── datapath.vhm     #   Execution datapath (ALU, buses, registers)
│   ├── mult.vhm         #   Multiplier/MAC unit
│   ├── register_file*.vhd  # Register file implementations
│   └── cpu_config.vhd   #   VHDL configurations (sim vs FPGA)
├── decode/              # Instruction decoder
│   ├── decode_core.vhm  #   Pipeline control and orchestration
│   ├── decode_table*.vhd #  Three decoder variants (simple/direct/ROM)
│   ├── gen-go/          #   Go-based decoder generator (production)
│   └── gen-clj-archive/ #   Legacy Clojure generator (archived, reference only)
├── cache/               # Cache controllers
│   ├── icache*.vhm      #   Instruction cache
│   ├── dcache*.vhm      #   Data cache (write-back, snoop support)
│   └── tests/           #   Cache test suites
├── sim/                 # Simulation environment
│   ├── Makefile         #   Main build file
│   ├── cpu_ctb.c        #   C-VHDL co-simulation testbench
│   ├── cpu_tb.vhd       #   VHDL testbench
│   ├── mem/             #   Memory models (SRAM, asymmetric RAM)
│   ├── sim/             #   GHDL C interface library
│   └── tests/           #   Simulator tests (interrupts, RTE)
├── testrom/             # Test programs for SH-2
│   ├── Makefile         #   Cross-compilation build
│   ├── startup/         #   Boot code and linker scripts
│   └── tests/           #   Per-instruction test suites
└── tests/               # VHDL unit testbenches
```

## Building

### Quick Start

```bash
cd sim
make
./cpu_ctb --stop-time=180us
```

This compiles the VHDL design with GHDL, builds the C testbench, cross-compiles the test ROM (if `sh2-elf-gcc` is available), and runs the CPU simulation for 180 microseconds.

### What `make` Builds

The `sim/Makefile` auto-detects which tools are installed and builds accordingly:

| Target | Requires | Description |
|--------|----------|-------------|
| `cpu_tb` | GHDL | Pure VHDL testbench |
| `cpu_pure_tb` | GHDL + sh2-elf-gcc | VHDL testbench with embedded ROM |
| `cpu_ctb` | GHDL + GCC | C-VHDL co-simulation testbench (recommended) |
| `pinst` | GCC | SH-2 instruction pretty-printer |
| `ram.img` | sh2-elf-gcc | Binary test ROM image |
| `sim/vpibridge.vpi` | Iverilog | Verilog VPI bridge (optional) |

### Build Configuration

Edit `sim/Makefile` or pass variables on the command line:

```bash
make CONFIG_RING_BUS=1       # Include optional ring bus interconnect
make CONFIG_PREFETCHER=1     # Include optional instruction prefetcher
```

The `TOOLS_DIR` variable must point to a directory containing `ghdl.mk` (shared GHDL build rules). By default it looks in `../../mcu_lib/tools` or `../../../tools`.

## Running Simulations

### Basic Simulation

```bash
cd sim
./cpu_ctb --stop-time=180us
```

The test ROM exercises all SH-2 instructions and prints results to stdout. Success ends with "Test Passed".

### Waveform Capture

```bash
./cpu_ctb --stop-time=180us --wave=wave.ghw
gtkwave wave.ghw    # view the waveforms
```

### Memory Delay Configuration

The simulator can inject per-address-range memory access delays to model realistic bus timing:

```bash
./cpu_ctb -d delays.cfg --stop-time=180us
```

See `sim/delays.cfg` for the configuration format.

### Running Specific Tests

```bash
# Interrupt handling test
./cpu_ctb --stop-time=10us -i tests/interrupts.img

# Stack save/restore (RTE) test
./cpu_ctb --stop-time=10us -i tests/rte.img
```

## Test Suite

### Instruction Tests (`testrom/tests/`)

Comprehensive tests for every SH-2 instruction category:

| Test File | Coverage |
|-----------|----------|
| `testbra.o` | Branch instructions (BRA, BSR, BT, BF, JMP, JSR, RTS) |
| `testmov.o`, `testmov2.o`, `testmov3.o` | Move instructions (MOV, MOV.B/W/L, MOVA) |
| `testalu.o` | ALU operations (ADD, SUB, AND, OR, XOR, CMP, NEG, NOT) |
| `testshift.o` | Shift operations (SHAL, SHAR, SHLL, SHLR, ROTL, ROTR) |
| `testmul.o`, `testmulu.o`, `testmuls.o`, `testmull.o` | Multiply variants |
| `testdmulu.o`, `testdmuls.o` | Double-length multiply |
| `testmulconf.o` | Multiply edge cases |
| `testdiv.o` | Division (DIV0S, DIV0U, DIV1) |
| `testmacw.o`, `testmacl.o` | Multiply-accumulate (MAC.W, MAC.L) |

### Component Unit Tests (`tests/`)

VHDL testbenches for individual functional units:
- `arith_tap.vhd` - Arithmetic unit
- `logic_tap.vhd` - Logic operations
- `bshift_tap.vhd` - Barrel shifter
- `mult_tap.vhd` - Multiplier
- `divider_tap.vhd` - Divider
- `manip_tap.vhd` - Bit manipulation operations
- `register_tap.vhd` - Register file

### Cache Tests (`cache/tests/`)

- `ictest00*`, `ictest02*` - Instruction cache tests
- `dctest13h_we_replace` - Data cache write/eviction
- `dctest39h_writepath_accvari8` - Data cache write paths
- `dctest40h_tas_variation` - Test-and-Set atomic access
- `fpga_sp/` - Single-processor FPGA tests
- `fpga_smp/` - Multi-processor (SMP) FPGA tests

## Understanding the Source Code

### File Types

| Extension | Description | Editable? |
|-----------|-------------|-----------|
| `.vhd` | Standard VHDL | Yes |
| `.vhm` | VHDL with C preprocessor macros | Yes (source of truth) |
| `.vhh` | Preprocessed VHDL (generated from `.vhm`) | No (build artifact) |
| `.ods` | LibreOffice spreadsheet (legacy Clojure generator input; archived in `decode/gen-clj-archive/`) | No (not used by Go generator) |
| `.toml` | TOML instruction spec (decoder generator input) | Yes (edit files under `decode/gen-go/spec/`) |

The `.vhm` files use the C preprocessor (`gcc -E`) for conditional compilation and macro expansion. The generated `.vhh` files should not be edited directly.

### CPU Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CPU (core/cpu.vhd)                    │
│                                                         │
│   ┌──────────┐    ┌──────────┐    ┌──────────────────┐ │
│   │  DECODE   │───▶│   MULT   │    │    DATAPATH      │ │
│   │ (decoder, │    │ (MAC     │    │ (ALU, shifter,   │ │
│   │  pipeline │    │  unit)   │    │  register file,  │ │
│   │  control) │    │          │    │  bus interface)   │ │
│   └──────────┘    └──────────┘    └──────────────────┘ │
│        │               │                   │            │
│        └───────────────┴───────────────────┘            │
│                 Control + Data Signals                   │
├─────────────────────────────────────────────────────────┤
│  Ports: inst_o/i (fetch), db_o/i (data), debug_o/i,    │
│         event_o/i (interrupts), cop_o/i (coprocessor)   │
└─────────────────────────────────────────────────────────┘
```

### Decoder Variants

Three decoder implementations are generated and selectable at compile time via VHDL configurations (`decode/decode_config.vhd`):

1. **Simple** (`decode_table_simple.vhd`) - Lookup table based
2. **Direct** (`decode_table_direct.vhd`) - Combinational logic, used for simulation
3. **ROM** (`decode_table_rom.vhd`) - ROM-based microcode, used for FPGA synthesis

### VHDL Configurations (`core/cpu_config.vhd`)

| Configuration | Decoder | Register File | Use Case |
|--------------|---------|---------------|----------|
| `cpu_sim` | Direct table | Two-bank RAM | GHDL simulation |
| `cpu_decode_direct_fpga` | Direct table | FPGA RAM | FPGA synthesis |
| `cpu_decode_rom_fpga` | ROM-based | FPGA RAM | FPGA synthesis |

## Regenerating the Instruction Decoder

The instruction decoder is generated from TOML spec files by the Go `cpugen` tool.

```bash
# Regenerate with default ROM width (72 bits):
make -C decode generate

# Regenerate with 64-bit ROM width:
make -C decode generate ROM_WIDTH=64

# Check that the generated files match what the generator would produce:
make -C decode diff
```

**Input**: TOML files under `decode/gen-go/spec/` (one file per instruction category:
`arithmetic.toml`, `branch.toml`, `compare.toml`, `divide.toml`, `logic.toml`,
`mov.toml`, `multiply.toml`, `shift.toml`, `system.toml`, plus `static/`)

**Output** (written to `decode/`):
- `decode_pkg.vhd` - Package with decoder control types
- `decode.vhd` - Decoder entity
- `decode_body.vhd` - Decode logic
- `decode_table_simple.vhd` - If-elsif lookup table (sim-only, source-of-truth)
- `decode_table_direct.vhd` - QMC-minimized combinational decoder (FPGA)
- `decode_table_rom.vhd` - ROM-based microcode decoder (FPGA)

**Full end-to-end regression** (generator unit tests + simulator + TAP testbenches +
optional synthesis and STA checks):

```bash
TOOLS_DIR=/path/to/jcore-soc/tools decode/gen-go/regression.sh
```

The regression script auto-detects optional tools (sh2-elf-gcc, yosys,
ghdl-yosys-plugin, opensta) and skips steps whose prerequisites are absent.

## Common Development Workflows

### Modifying CPU Behavior

1. Edit the relevant `.vhm` or `.vhd` file in `core/` or `decode/`
2. Rebuild: `make -C sim`
3. Run simulation: `cd sim && ./cpu_ctb --stop-time=180us`
4. Check for "Test Passed" output
5. Optionally capture waveforms with `--wave=wave.ghw`

### Adding a New Instruction Test

1. Write a test in SH-2 assembly in `testrom/tests/`
2. Add the object file to `TESTS_OBJS` in `testrom/Makefile`
3. Call the test from `testrom/main.c`
4. Rebuild: `make -C testrom && make -C sim ram.img`
5. Run: `cd sim && ./cpu_ctb --stop-time=180us`

### Modifying the Instruction Set

1. Edit the relevant TOML file under `decode/gen-go/spec/` (e.g. `arithmetic.toml`)
2. Regenerate: `make -C decode generate`
3. Rebuild and test: `make -C sim && cd sim && ./cpu_ctb --stop-time=180us`

### Debugging with GDB

The simulator includes GDB stub support for interactive debugging of test programs running on the simulated CPU. The C testbench (`cpu_ctb.c`) bridges VHDL signals to a GDB-compatible debug interface.

## Installing Optional Synthesis Tools

The `regression.sh` Steps 7 and 8 are skipped automatically when their prerequisites
are absent. This section documents how to install them if you want the full regression.

### Step 7: yosys + ghdl-yosys-plugin

yosys synthesizes the generated VHDL decoder files and checks for latches and
multi-driver nets — problems that simulate correctly but would produce wrong hardware.

The ghdl-yosys-plugin bridges ghdl's VHDL front-end into yosys. It must match your
installed ghdl version exactly. Build both from source:

```bash
# Install build dependencies
sudo apt install build-essential flex bison libreadline-dev \
    libffi-dev libboost-all-dev pkg-config

# Build yosys
git clone https://github.com/YosysHQ/yosys
cd yosys && make -j$(nproc) && sudo make install && cd ..

# Build ghdl-yosys-plugin (must match installed ghdl)
git clone https://github.com/ghdl/ghdl-yosys-plugin
cd ghdl-yosys-plugin && make && sudo make install && cd ..

# Verify the plugin loads
yosys -m ghdl -p 'help ghdl'
```

### Step 8: openSTA + Nangate45 Liberty file

openSTA reports critical-path delay and slack against a virtual clock target.
Results are informational — Nangate45 is an academic cell library, not a production
silicon flow. Negative slack at the 100 MHz target is not a regression failure.

```bash
# Install openSTA (Ubuntu/Debian)
sudo apt install opensta
```

The Nangate45 Liberty file is downloaded separately at the path `regression.sh` looks
for by default (`/tmp/sky130/lib/nangate45.lib`):

```bash
mkdir -p /tmp/sky130/lib
curl -L https://raw.githubusercontent.com/The-OpenROAD-Project/OpenSTA/master/examples/nangate45_slow.lib.gz \
  | gunzip > /tmp/sky130/lib/nangate45.lib
```

**Note**: `/tmp/` does not survive a reboot. After a reboot, re-run the `curl`
command, or move the file to a persistent location and override the path:

```bash
mkdir -p ~/local/lib
cp /tmp/sky130/lib/nangate45.lib ~/local/lib/nangate45.lib
# Then invoke regression.sh with:
NANGATE_LIB=~/local/lib/nangate45.lib decode/gen-go/regression.sh
```

## Continuous Integration

Two GitHub Actions workflows live under `.github/workflows/`:

### `pr-quick.yml` — every push and pull request

Runs on `ubuntu-24.04` with apt-installed GHDL. Covers Steps 1–5 of
`decode/gen-go/regression.sh`:

1. `go test ./...` in `decode/gen-go/`
2. `make -C decode generate`
3. `cpu_ctb` 180us with the direct decoder
4. `cpu_ctb` 180us with the ROM decoder
5. `make -C tests check` (228 TAP unit tests)

Target budget: under 10 minutes. The workflow checks out
`j-core/jcore-soc` as a sibling for `TOOLS_DIR` and patches
`core/cpu_config.vhd` for Step 4 with a `trap` that restores the file
even on failure.

### `full-regression.yml` — push to main + nightly schedule

Runs the complete 8-step `regression.sh`, including Step 6 (SH-2
simulator tests via `sh2-elf-gcc`), Step 7 (yosys + ghdl-yosys-plugin
synthesis), and Step 8 (openSTA on the Nangate45-mapped netlists). The
heavy toolchain is preinstalled in a container image, so per-run wall
time stays under ~30 minutes once the image is cached.

Synthesis and STA artifacts are uploaded as the `synth-out` build
artifact for inspection.

### `build-ci-image.yml` — toolchain image builder

Builds and pushes `ghcr.io/<owner>/jcore-cpu-ci:latest`. See
`.github/ci/README.md` for the toolchain inventory, version-pinning
rationale, and on-demand rebuild instructions. The image must exist
before `full-regression.yml` can run; rebuild it whenever
`.github/ci/Dockerfile` changes (push to main triggers it
automatically) or manually via the Actions tab.

## Troubleshooting

### GHDL "library not found" errors

GHDL must be built with the Synopsys IEEE library. Check with:
```bash
ghdl --version
```

### `sh2-elf-gcc` not found

The SH-2 cross-compiler is not included in most package managers. Build it using [crosstool-NG](https://crosstool-ng.github.io/) with an `sh2-elf` target, or use [buildroot](https://buildroot.org/).

### `TOOLS_DIR` errors

The build expects shared GHDL makefiles at `../../mcu_lib/tools` or `../../../tools`. If building standalone, you may need to provide these files or adjust the path in `sim/Makefile`.

### `.vhm` preprocessing failures

The `.vhm` to `.vhh` conversion uses `gcc -E` (C preprocessor). Ensure GCC is installed and in `PATH`.
