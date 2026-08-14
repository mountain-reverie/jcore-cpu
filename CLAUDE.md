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
├── tools/                  # Repo tooling (NOT the external TOOLS_DIR makefiles)
│   └── insns2asm/          # Go generator: docs/insns.json -> binutils gas / LLVM defs
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

**`make -C decode generate-j4` writes the J4-overlay tables into the in-tree
`decode/`.** The in-tree tables must stay BASE — committing J4-overlay tables is
a known Fmax regression (see `sim/mmu_sim.sh`'s header). The J4 build path is
out-of-tree: `sim/gen/j4-w<width>/decode`, produced by `CPU_VARIANT=j4`. If you
run `generate-j4` by accident, `git diff --stat decode/` shows it immediately
(hundreds of changed lines instead of the handful your edit explains); recover
with a plain `make -C decode generate`.

### Per-variant spec attributes

Two `[[instr]]` keys express rules the microcode walk cannot infer:

- `slot_illegal = true` — forces membership in `check_illegal_delay_slot`. The
  derived rule only sees instructions asserting `wrpc_z`, which misses the
  conditional branches (they redirect via `zbus="T(PC)"`). `microcode.IsSlotIllegal`
  is the single definition of the set: it drives both the generated decoder and
  `docs/insns.json`'s `.exceptions`. Do not add a second copy of this rule.
- `patch = true` — an OVERLAY-only entry that refines the attributes of the
  same-named base instruction in place, leaving opcode and microcode alone. Use
  it for ISA rules scoped to some variants; a full override would have to
  duplicate, and then drift from, the base microcode.

**ISA rules are often variant-scoped, and the upstream docs hide it.** `MOVA` and
`MOV.{W,L} @(disp,PC),Rn` are slot-illegal on SH-3/SH-4 ONLY ("SH4\*: If this
instruction is executed in a delay slot..."); on SH-1/SH-2 they are legal there,
and `testrom/tests/testmov2.s:27` actively depends on it — trapping them on J2
hangs the test ROM (`regression.sh` Step 3 stops after 5 of 20 LED writes). They
live in `spec/sh4/mov.toml` as a patch, NOT in the base spec. Oleg Endo's
"Possible Exceptions" list (`shared-ptr.com/sh_insns.html`) is the SH-4 list and
does not carry that scoping, so it reads as unconditional.

### Regenerating Toolchain (assembler/LLVM) Definitions

**Never hand-edit binutils `opcodes/sh-opc.h` to teach the assembler about a
J-core instruction.** That table is generated from `docs/insns.json` by
`tools/insns2asm` (a second Go generator, separate from `decode/gen-go`):

```bash
cd tools/insns2asm
go run ./cmd/insns2asm -in ../../docs/insns.json -emit check   # round-trip oracle
go run ./cmd/insns2asm -in ../../docs/insns.json -emit gas     # J-core-only delta lines
go run ./cmd/insns2asm -in ../../docs/insns.json -emit gas-augment \
    -shopc <binutils>/opcodes/sh-opc.h                         # patch shared SH/J lines in place
go run ./cmd/insns2asm -in ../../docs/insns.json -emit llvm    # LLVM .td encodings
```

- `gas` emits NEW `sh_table` lines for instructions that exist only on J-core.
- `gas-augment` handles instructions that already have an upstream line shared
  with an SH variant, ORing the J-core arch flag into that line's existing mask.
  It is idempotent and errors rather than silently drifting.
- Arch-flag choice lives in `tools/insns2asm/internal/arch/arch.go`. Note the
  deliberate split: `GASMask()` is SH-first and answers "what mask does a NEW
  line get"; `JCoreAugmentFlag()` answers "which J-core flag gets OR'd into an
  EXISTING line" (`arch_j2_up` for base J1/J2 instructions, `arch_j4_up` for
  J4-only ones). Conflating the two is what once made gas reject `shad`/`shld`
  under `--isa=sh-j2`.

The assembler is selected with gas's `--isa=sh-j2` / `--isa=sh-j4` (NOT `-m2`,
which is a gcc flag). `testrom/Makefile` passes `-Wa,--isa=sh-j2`.

If an instruction is added to `decode/gen-go/spec/`, it must also be added to
`docs/insns.json` — that file feeds both the GitHub Pages instruction explorer
and `tools/insns2asm`. Sync it from the spec rather than by hand:

```bash
make -C decode insns          # regenerate docs/insns.json from the TOML spec
make -C decode insns-check    # verify it is in sync (non-zero if not)
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

### MMU / priv-arch guards (`sim/mmu_sim.sh`)

Most MMU and privileged-architecture work is verified here, not by
`regression.sh`. It builds a `CPU_VARIANT=j4` cosim (the MMU instructions live
in the J4 overlay decoder) and runs the guard set.

- **`-n` skips the build entirely** — it is not "make decides nothing changed",
  make is never invoked. Any RTL change measured under `-n` is measured against
  stale hardware. Rebuild (no `-n`) for every RTL A/B, however small.
- **DELETING a spec file does not invalidate the J4 decoder build**, even without
  `-n`. Make's prerequisites come from a wildcard over `decode/gen-go/spec/`, so
  removing a file leaves the target looking up to date; *editing* one triggers
  correctly. Measured 2026-08-14: deleting `spec/sh4/mov.toml` and re-running the
  full `sim/mmu_sim.sh` reported PASS against the OLD decoder — the tell is that
  the `emitted to .../sim/gen/j4-w72/decode` line is absent from the log. Any A/B
  performed by removing a spec file is measuring stale hardware, exactly like the
  `-n` trap above. Force it with `rm -rf sim/gen/j4-w72` before the run, and
  check for that `emitted to` line before believing the result.
- **CI keeps its OWN guard list, and the two diverge in BOTH directions.**
  `.github/workflows/full-regression.yml` defines its own `run_guard` and its
  own sequence; adding a guard to `sim/mmu_sim.sh` does not add it to CI, or the
  reverse. Measured 2026-08-08: ~34 guards ran locally but not in CI —
  including `mmudrain`, every `mmudspcprobe*`, `mmurestartpc`, `mmufaultage`,
  `mmudblflt`, the `mmunest*` set, and the guards locking this branch's own RTL
  fixes. **When you add a guard, add it to BOTH**, and diff the two lists when
  you touch either.
- The three Linux harnesses go the other way: `mmulinux`, `mmuboot` and
  `mmuhuge` drive the REAL linux@jcore TLB-miss handler and page tables, and are
  **not referenced by `sim/mmu_sim.sh` at all**. They run only in CI and via
  `sim/linux_sim.sh`, and both need linux@jcore kbuild objects under
  `$(LINUX_SRC)` that a normal checkout does not have. A fully green local run
  says nothing about the real Linux handler; expect CI to be the first thing
  that exercises it.
- `run_guard` discards a guard's output on PASS — to see anything from a passing
  run (an RTL `assert`, a trace), invoke `./cpu_ctb` directly.

### Writing a guard

A guard that passes *without exercising its scenario* is the default failure
mode in this repo, not an exotic one. Before trusting green:

- **Mutate it and confirm red.** Break the construction and check the guard
  fails **with its own result code**, not a timeout and not a neighbour's code.
  Give distinct failure IDs to distinct defects so they cannot be conflated.
- **A hand-assembled `.word` is an unchecked assertion about the hardware** —
  the assembler validates nothing. When a guard reports a defect the RTL cannot
  explain, re-derive every hand-written opcode from its encoding table *before*
  probing the RTL.
- To find out whether a scenario is reachable at all, add a temporary
  `assert ... severity warning` probe to the RTL and sweep every image in
  `sim/tests/`. Prove the probe itself is live (relax it until it fires) before
  believing a zero-hit result.

### Style gate: `scripts/vhdl-lint.sh`

`vhdl-lint` is a **separate, gating** CI workflow (vsg / VHDL-Style-Guide,
`vsg_config.yaml`). It is not part of `regression.sh` or `sim/mmu_sim.sh`, so a
green local suite says nothing about it — and it only triggers on push/PR, not
on the `workflow_dispatch` used to re-run `full-regression`.

Run it before pushing RTL:

```
scripts/vhdl-lint.sh          # whole tree, ~20 min
scripts/vhdl-lint.sh --fix    # auto-fix
vsg -c vsg_config.yaml -f core/cpu.vhd --fix   # one file, seconds
```

Two traps worth knowing:

- **Alignment rules make edits contagious.** `type_400` aligns `:` within a
  declaration group, so adding one longer field name puts its NEIGHBOURS in
  violation. `git blame` on a violating line will point at an old, innocent
  commit; that does not mean the violation is pre-existing. Check whether
  `master` is clean instead.
- Generated and `.vhm`-derived `.vhd` files are excluded (see the script's
  exclusion lists) — fix the `.vhm`, never the derived `.vhd`.

### Tracked generated files

`core/datapath.vhd` is generated from `core/datapath.vhm` by v2p **and
committed**. Editing the `.vhm` means committing the regenerated `.vhd` too.
`make verify-generated` (regression.sh Step 1b) compares the *working tree*,
which every build refreshes — so the local check passes even when the committed
copy is stale, and only CI compares the commit. `make verify-v2p` now prints a
NOTE when a tracked `.vhd` is regenerated but uncommitted.

## GitHub Pages

- `docs/insns/` is deployed to GitHub Pages via `synth-cpu.yml` as an interactive SH instruction reference (jQuery Dynatable).
- `docs/insns.json` is the data source for the instruction explorer page. When new instructions are added to the CPU (in `decode/gen-go/spec/`), regenerate it with `make -C decode insns` to keep the explorer page in sync.
- The deployed instruction explorer lives at `/insns/` on the jcore-cpu GitHub Pages site.
- Each row carries a per-variant `<VARIANT>.exceptions` list (e.g. `J4.exceptions`), derived from the TOML spec — see `internal/insns.exceptionsFor`. It covers only what the spec *determines* (slot-illegal, general-illegal from `privileged`, TRAPA's trap), NOT the data-side TLB/address-error family. Absent means "not on this variant"; the variant split is meaningful, e.g. `MOVA` lists slot-illegal on J4 only.
- The explorer declares its columns explicitly via `data-dynatable-column`, so adding a key to `insns.json` does not surface it automatically — render it in the detail rows (see how `collides` and `exceptions` are built).

## Key Conventions

- VHDL signal types use `_t` suffix (e.g., `cpu_data_o_t`, `reg_ctrl_t`)
- Package files use `_pkg` or `_pack` suffix
- Control signal groups: `reg_ctrl_t`, `func_ctrl_t`, `mem_ctrl_t`, `mac_ctrl_t`, `pc_ctrl_t`, `buses_ctrl_t`, `sr_ctrl_t`
- Generated files in `decode/` should not be edited manually; modify the TOML files under `decode/gen-go/spec/` and run `make -C decode generate`
- The `.vhm` files are the source of truth for datapath, multiplier, and decode core; the `.vhh` files are build artifacts
- Cache size is configurable via `CACHE_INDEX_BITS` in `cache/cache_pkg.vhd` (7=4KB, 8=8KB default, 9=16KB)
