# insns2asm

Generates assembler definitions from `docs/insns.json`.

Phase 1 covers the GP-integer instruction core (Data Transfer, Arithmetic,
Logic, Shift, Bit Manipulation). The DSP family is excluded.

## Usage

    go run ./cmd/insns2asm -in ../../docs/insns.json -emit check   # round-trip oracle
    go run ./cmd/insns2asm -in ../../docs/insns.json -emit gas     # minimal binutils delta
    go run ./cmd/insns2asm -in ../../docs/insns.json -emit llvm    # LLVM .td encodings

## Modes

- `check` — verifies every instruction's encoding round-trips losslessly.
- `gas`   — emits only J-core-only instructions as `sh_table` entries to splice
  into a checked-out upstream `opcodes/sh-opc.h` (parity mode: SH instructions
  are assumed already present upstream).
- `llvm`  — emits complete TableGen instruction-encoding records (bootstrap
  mode) for the LLVM SH MC layer. Register classes and MC C++ glue are written
  by hand following the RISC-V backend layout.

## Toolchain round-trip (manual integration)

The pure-Go `check` gate proves the IR matches insns.json. End-to-end validation
against built toolchains (assemble each format, disassemble, compare bytes) is a
manual integration step performed when wiring the gas delta into binutils and
the `.td` into the in-tree LLVM SH backend.
