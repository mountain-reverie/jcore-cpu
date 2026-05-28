# CLAUDE.md - J-Core J2 CPU

## Project Overview

This is the J-Core J2 CPU core: an open-source 32-bit RISC processor implementing the SH-2 (SuperH-2) instruction set architecture. It contains VHDL hardware descriptions, a C-VHDL co-simulation testbench, and a Go-based instruction decoder generator (`decode/gen-go/`). The legacy Clojure generator is archived under `decode/gen-clj-archive/` for reference.

## Repository Structure

```
jcore-cpu/
├── cpu2j0_pkg.vhd          # Top-level CPU interface types and component declaration
├── build.mk                # Top-level build config (includes build_core.mk)
├── build_core.mk           # Core VHDL source file list
├── core/                   # CPU core: datapath, decoder, register file, multiplier
│   ├── cpu.vhd             # Top-level CPU entity (structural architecture)
│   ├── datapath.vhm        # 32-bit execution datapath (ALU, buses, registers)
│   ├── datapath_pkg.vhd    # Pipeline register and datapath types
│   ├── mult.vhm            # Multiplier/MAC unit (microcode-driven)
│   ├── mult_pkg.vhd        # Multiplier types and microcode constants
│   ├── components_pkg.vhd  # Internal arithmetic/logic/shift operation types
│   ├── cpu_config.vhd      # VHDL configurations (sim vs FPGA variants)
│   ├── register_file.vhd   # Register file entity
│   ├── register_file_flops.vhd      # FF-based register file
│   └── register_file_two_bank.vhd   # Dual-port RAM register file
├── decode/                 # Instruction decoder
│   ├── decode_pkg.vhd      # Generated decoder control types
│   ├── decode.vhd          # Generated decoder entity
│   ├── decode_body.vhd     # Generated decode logic
│   ├── decode_core.vhm     # Pipeline orchestration and control
│   ├── decode_table*.vhd   # Three decoder implementations (simple/direct/ROM)
│   ├── decode_config.vhd   # Configuration selecting decoder variant
│   ├── Makefile             # 'make -C decode generate' regenerates VHDL via cpugen
│   ├── gen-go/              # Go code generator (production)
│   │   ├── cmd/cpugen/      # Main CLI
│   │   ├── internal/        # spec/parser/microcode/logic/model/emit
│   │   ├── spec/            # TOML instruction set definition
│   │   └── regression.sh    # End-to-end check (go test + sim + TAP)
│   └── gen-clj-archive/    # Legacy Clojure generator (reference only)
│       ├── project.clj      # Leiningen project file
│       ├── SH-2 Instruction Set.ods  # Original instruction spreadsheet
│       └── src/cpugen/      # Clojure source
├── cache/                  # I-cache and D-cache implementations
│   ├── cache_pkg.vhd       # Cache config (8KB default, 4K-16K configurable)
│   ├── icache*.vhm         # Instruction cache controller
│   ├── dcache*.vhm         # Data cache controller (write-back, snoop support)
│   └── tests/              # Cache test suites (single/multi-processor)
├── sim/                    # Simulation infrastructure
│   ├── Makefile             # Main simulation build (GHDL + C testbench)
│   ├── README.txt           # Simulator usage guide
│   ├── cpu_ctb.c            # C-VHDL co-simulation testbench (main)
│   ├── cpu_tb.vhd           # VHDL testbench (preprocessed to .vhh via C preprocessor)
│   ├── cpu_pure_tb.vhh      # Pure VHDL testbench (no C bridge)
│   ├── cpu_signals.h        # Signal definitions for C-VHDL bridge
│   ├── sh2instr.c           # SH-2 instruction disassembler
│   ├── debug*.c             # GDB debugging support
│   ├── delays.c / delays.cfg  # Memory access delay configuration
│   ├── mem/                 # Memory models (SRAM, asymmetric RAM)
│   ├── sim/                 # GHDL simulator C interface library
│   └── tests/               # Simulator-level tests (interrupts, RTE)
├── testrom/                # Boot ROM and test programs targeting SH-2
│   ├── Makefile             # Cross-compilation with sh2-elf-gcc
│   ├── startup/             # Startup code, linker scripts (sh32.x)
│   ├── main.c               # Test ROM main
│   └── tests/               # SH-2 instruction test objects
└── tests/                  # VHDL component unit testbenches
    ├── arith_tap.vhd        # Arithmetic unit tests
    ├── logic_tap.vhd        # Logic operation tests
    ├── bshift_tap.vhd       # Barrel shifter tests
    ├── mult_tap.vhd         # Multiplier tests
    ├── divider_tap.vhd      # Divider tests
    ├── manip_tap.vhd        # Manipulation operation tests
    └── register_tap.vhd     # Register file tests
```

## Architecture

The CPU is a 5-stage pipelined 32-bit processor:
- **Fetch (IF)**: Instruction cache fetch, PC increment
- **Decode (ID)**: Instruction decode, register file read
- **Execute (EX1-EX3)**: ALU, MAC, shifter; address generation
- **Write-back (WB1-WB3)**: Register file write, memory data capture

Top-level entity `cpu` (in `core/cpu.vhd`) instantiates three sub-units:
- `decode` - instruction decoder with pipeline control
- `mult` - multiplier/MAC unit (multi-cycle, microcode-driven)
- `datapath` - execution datapath (ALU, shifter, register file, buses)

Key interfaces defined in `cpu2j0_pkg.vhd`:
- `cpu_instruction_o_t` / `cpu_instruction_i_t` - instruction bus (16-bit opcodes)
- `cpu_data_o_t` / `cpu_data_i_t` - data bus (32-bit)
- `cpu_debug_*_t` - debug interface (breakpoints, single-step, register access)
- `cpu_event_i_t` / `cpu_event_o_t` - interrupt/exception interface
- `cop_*_t` - optional coprocessor interface (controlled by `COPRO_DECODE` generic)

## File Types

- `.vhd` - Standard VHDL source
- `.vhm` - VHDL with C preprocessor macros (preprocessed to `.vhd` or `.vhh` at build time using `gcc -E`)
- `.vhh` - Preprocessed VHDL output (generated, do not edit)
- `.ods` - LibreOffice spreadsheet (legacy; archived in `decode/gen-clj-archive/`; not used by the Go generator)

## Build System

### Prerequisites

- **GHDL** (with Synopsys IEEE library) - VHDL simulator/compiler
- **GCC** - for C testbench code and `.vhm` preprocessing
- **sh2-elf-gcc** toolchain - cross-compiler for SH-2 test ROMs
- **Go 1.26+** - needed to regenerate the instruction decoder from the TOML spec in `decode/gen-go/spec/`
- **Iverilog** (optional) - alternative Verilog simulation

### Building the Simulator

```bash
cd sim
make          # builds cpu_tb, cpu_pure_tb, cpu_ctb, pinst, and ram.img
```

The Makefile auto-detects available tools (`ghdl`, `iverilog`, `sh2-elf-gcc`) and builds what it can. `TOOLS_DIR` must point to shared build tool makefiles (typically `../../mcu_lib/tools` or `../../../tools`).

### Running Simulation

```bash
cd sim
./cpu_ctb --stop-time=180us                              # run test ROM
./cpu_ctb --stop-time=180us --wave=wave.ghw              # with waveform dump
./cpu_ctb -d delays.cfg --stop-time=180us                # with memory delays
./cpu_ctb --stop-time=10us -i tests/interrupts.img       # run specific test
```

### Building Test ROMs

```bash
cd testrom
make main.elf     # cross-compile with sh2-elf-gcc
```

### Regenerating the Decoder

```bash
make -C decode generate                  # default ROM width 72
make -C decode generate ROM_WIDTH=64     # 64-bit ROM
```

Under the hood this runs `go -C decode/gen-go run ./cmd/cpugen -o decode`. The
spec is the TOML tree under `decode/gen-go/spec/`. Generated outputs in `decode/`:
`decode_pkg.vhd`, `decode.vhd`, `decode_body.vhd`, `decode_core.vhd`,
`decode_table_{simple,direct,rom}.vhd`.

End-to-end regression (generator unit tests + simulator + TAP testbenches):

```bash
decode/gen-go/regression.sh
```

## VHDL Configurations

In `core/cpu_config.vhd`:
- `cpu_sim` - for GHDL simulation (direct decoder, two-bank register file)
- `cpu_decode_direct_fpga` - FPGA synthesis with direct table decoder
- `cpu_decode_rom_fpga` - FPGA synthesis with ROM-based decoder

## Build Configuration Options

In `sim/Makefile`:
- `CONFIG_RING_BUS=0|1` - include optional ring bus interconnect
- `CONFIG_PREFETCHER=0|1` - include optional instruction prefetcher
- `TOOLS_DIR` - path to shared GHDL build tool makefiles

## Testing

### Instruction Tests (testrom/tests/)
Tests for every instruction category: branch, move, ALU, shift, multiply (signed/unsigned/long/double), divide, MAC.

### Simulator Tests (sim/tests/)
- `interrupts.img` - interrupt handling verification
- `rte.img` - stack save/restore syscall behavior

### Component Unit Tests (tests/)
VHDL testbenches for individual functional units: arithmetic, logic, barrel shifter, multiplier, divider, manipulation ops, register file.

### Cache Tests (cache/tests/)
Tests for instruction cache, data cache write/eviction, TAS atomic access, single-processor and multi-processor FPGA configurations.

### Test Output
Tests print "Test Passed" on success or "Test failed. Result=N" on failure (where N identifies the failing check).

## Key Conventions

- VHDL signal types use `_t` suffix (e.g., `cpu_data_o_t`, `reg_ctrl_t`)
- Package files use `_pkg` or `_pack` suffix
- Control signal groups: `reg_ctrl_t`, `func_ctrl_t`, `mem_ctrl_t`, `mac_ctrl_t`, `pc_ctrl_t`, `buses_ctrl_t`, `sr_ctrl_t`
- Generated files in `decode/` should not be edited manually; modify the TOML files under `decode/gen-go/spec/` and run `make -C decode generate`
- The `.vhm` files are the source of truth for datapath, multiplier, and decode core; the `.vhh` files are build artifacts
- Cache size is configurable via `CACHE_INDEX_BITS` in `cache/cache_pkg.vhd` (7=4KB, 8=8KB default, 9=16KB)
