# insns2asm

Generates assembler definitions from `docs/insns.json`.

Coverage:
- Phase 1: GP-integer core (Data Transfer, Arithmetic, Logic, Shift, Bit Manipulation).
- Phase 2a: Branch + System Control, with operand-bit binding in the LLVM output.

The DSP instruction family is excluded. Branch/System-Control instructions whose
operands reference DSP or coprocessor registers are also excluded; the excluded
count is reported on stderr.

## Usage

    go run ./cmd/insns2asm -in ../../docs/insns.json -emit check   # round-trip oracle
    go run ./cmd/insns2asm -in ../../docs/insns.json -emit gas     # minimal binutils delta
    go run ./cmd/insns2asm -in ../../docs/insns.json -emit gas-augment -shopc <path>/opcodes/sh-opc.h
                                                                    # patch existing SH entries shared with J4
    go run ./cmd/insns2asm -in ../../docs/insns.json -emit llvm    # LLVM .td encodings

## Modes

- `check` — verifies every instruction's encoding round-trips losslessly.
- `gas`   — emits only J-core-only instructions as `sh_table` entries to splice
  into a checked-out upstream `opcodes/sh-opc.h` (parity mode). Branch and System
  Control instructions all carry an SH arch flag, so none appears in the delta.
  Delta entries are grouped by mnemonic (stable, first-seen order) so a distinct
  mnemonic is never interleaved into another mnemonic's contiguous run — gas's
  matcher requires all `sh_table` entries sharing a mnemonic to be contiguous.
- `gas-augment` — patches an EXISTING upstream `opcodes/sh-opc.h` in place for
  instructions J4 shares with an SH variant (e.g. the reg-reg forms
  `ldc Rm,SSR`/`stc SSR,Rn`/`ldc Rm,Rn_BANK`/`stc Rm_BANK,Rn`): these already
  have an upstream `sh_table` line, so instead of a new delta line the tool
  OR's `arch_j4_up` into that line's existing arch mask, matched by mnemonic +
  opcode nibble tuple. Idempotent (a line already carrying `arch_j4_up` is left
  untouched) and it errors on any augmentation with no matching upstream line,
  so it never silently drifts. The `.l` memory forms and `SGR` are not J4 and
  are never touched.
- `llvm`  — emits TableGen records with operand classes, dag operand lists, and
  per-field `Inst{}` bindings (bootstrap mode). Register classes and the MC C++
  glue are written by hand following the RISC-V backend layout (Phase 2b).

## Round-trip against built toolchains

The pure-Go `check` gate proves the IR matches insns.json. Building `llvm-mc` /
`gas` from the emitted defs and round-tripping bytes is Phase 2b (LLVM MC glue)
and Phase 2c (binutils delta).
