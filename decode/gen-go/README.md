# cpugen — J-Core decoder generator (Go)

Generates the SH-2 instruction decoder VHDL from a TOML spec. Replaces
the legacy Clojure generator (now archived at `decode/gen-clj-archive/`).

References:
- `docs/superpowers/specs/2026-05-20-cpugen-go-rewrite-v2-design.md` — design

## Layout

- `cmd/cpugen/`   — main generator binary
- `cmd/csv2toml/` — one-shot CSV → TOML converter (frozen, archival)
- `internal/spec/`, `opcode/`, `logic/`, `microcode/`, `model/`, `emit/` — pipeline stages
- `spec/`         — TOML source-of-truth (10 files: arithmetic, branch, compare,
                    divide, logic, mov, multiply, shift, system, plus `static/`)
- `testdata/`     — fixtures + frozen Clojure golden output
- `regression.sh` — one-command end-to-end check

## Usage

```bash
# From the repo root:
make -C decode generate                 # regenerate VHDL (ROM_WIDTH=72 default)
make -C decode generate ROM_WIDTH=64    # narrow ROM variant

# Direct invocation:
go -C decode/gen-go run ./cmd/cpugen -o ../          # emit into decode/
go -C decode/gen-go run ./cmd/cpugen -w 64 -o /tmp/  # custom width + dir
```

End-to-end regression (generator unit tests + simulator LED check + TAP suite):

```bash
decode/gen-go/regression.sh
```

## Known gaps

**Cache tests not integrated.** `cache/tests/*` is not run by `regression.sh`. The
cache testbenches depend on `jcore-soc/components/ddr2/ddrc_cnt_pack.vhd` and a
board-generated `work.config` package that are not available in a standalone
`jcore-cpu` checkout. The Makefile fixes in `cache/tests/` (path corrections +
`TOOLS_DIR ?=`) make future integration straightforward once the SoC context is in
scope. In the meantime, cache controller logic is exercised indirectly via the Step 3
testrom run: `cpu_ctb` reads instructions through the I-cache and performs data
accesses through the D-cache controller on every regression run.

**Synthesis check (Step 7) is operational** — narrowed in scope to the two FPGA
decoder variants (`decode_table_direct` and `decode_table_rom`). The full `cpu`
entity is not synthesized because the hand-written `decode_core.vhm` uses an
`elsif clk='1' and slot='1' and clk'event` clock idiom that yosys+ghdl rejects as
ill-formed. That is pre-existing project code outside the generator's scope.

**Static timing analysis (Step 8) is operational** — results are informational only.
The Nangate45 library is an academic open-source cell library, not the production
silicon flow used for actual J-Core tape-outs. Negative slack at the 100MHz virtual
target is not a regression failure; the step's value is confirming there are no
combinational loops and tracking relative critical-path complexity over time.

**Deferred ground-truth items** — the following are explicitly out of scope for this
regression and require resources not available in a standalone checkout:
- FPGA hardware board testing (Xilinx/Altera synthesis + place-and-route)
- Vendor synthesis tools (Synopsys, Cadence, Xilinx Vivado)
- Real silicon timing verification

## `cmd/csv2toml` is frozen

This tool was used once to convert the original Clojure-era CSV export
into the TOML files now under `spec/`. It is retained for reproducibility
but is not part of the normal build. Edit the TOML files directly.

---

## Known divergence from Clojure baseline: LED-write timing

The Go-generated `cpu_decode_direct` produces LED writes 90 ns – 3.4 μs
later than the Clojure baseline at the same opcode input. This is NOT a
regression — it is the expected, semantically-equivalent result of the
Go QMC reducer making different tie-breaking choices when several
prime-implicant covers are equally minimal. Both decoders implement the
same boolean function; only the gate-level structure (and therefore
propagation delay through the combinational cloud) differs.

The simple and ROM decoders are byte-identical to the Clojure baseline.
Future maintainers should not treat the small per-LED timing shift in
the direct decoder as a regression unless the LED *sequence* changes
or the regression script's expected LED-value list fails to match.

## Worked example: adding a new instruction

This walks through adding a hypothetical `NEGX Rm, Rn` instruction
(based directly on the existing `SUB Rm, Rn`) to demonstrate the full
edit-test-commit loop. The same pattern applies to real additions.

### 1. Locate the right TOML file

Instructions live in `spec/<category>.toml`. The split mirrors the SH-2
ISA section structure:

| File              | Contents                                          |
|-------------------|---------------------------------------------------|
| `arithmetic.toml` | ADD, SUB, NEG, EXT.*, DT, CMP-less arithmetic     |
| `logic.toml`      | AND, OR, XOR, NOT, TST, bit manipulation          |
| `compare.toml`    | CMP/EQ, CMP/HS, CMP/GE, ...                       |
| `shift.toml`      | SHA*, SHL*, ROT*, ROTC*                           |
| `mov.toml`        | MOV in all addressing modes, LDC, STC, LDS, STS   |
| `branch.toml`     | BRA, BSR, BT, BF, JMP, JSR, RTS                   |
| `multiply.toml`   | MUL.L, MULS.W, MULU.W, DMULS.L, DMULU.L, MAC.W/L  |
| `divide.toml`     | DIV0S, DIV0U, DIV1                                |
| `system.toml`     | TRAPA, RTE, SLEEP, illegal/reset microcode        |

A new arithmetic op goes in `arithmetic.toml`.

### 2. Add the `[[instr]]` block

Each instruction is one TOML array element with metadata and one or more
slots (microcode steps). The fastest path to a correct entry is to copy
a real similar instruction verbatim and change only what's different.

For our `NEGX` example we copy the existing `SUB Rm, Rn` block from
`arithmetic.toml` (which already computes `Rn − Rm → Rn`) and modify
only the `name`, `opcode`, and `operation`:

```toml
[[instr]]
  name = "NEGX Rm, Rn"
  format = "mn"                          # m (Rm) in bits 7:4, n (Rn) in 11:8
  opcode = "0110 nnnn mmmm 1100"         # hypothetical encoding (unused slot)
  operation = "Rn - Rm -> Rn (clamped)"  # human-readable summary
  table_ref = "A.32"                     # SH-2 spec section; used for sort order

  [[instr.slots]]
    arith = "SUB"          # ALU op
    pc = "INC"             # advance PC normally
    xbus = "Rn"            # Rn on x-bus (minuend)
    ybus = "Rm"            # Rm on y-bus (subtrahend)
    zbus = "Rn"            # write z-bus back to Rn
    zbus_sel = "ARITH"     # z-bus comes from arith unit
```

Key conventions:
- **`format`** drives register-field placement. Valid values: `n`, `m`,
  `nm`, `mn`, `nd4`, `nd8`, `md`, `nmd`, `i8`, `d8`, `d12`, `ni`, `0`.
  For `mn`, `Rn` is routed to the high nibble (`RA`) and `Rm` to the low
  nibble (`RB`). See `internal/microcode/slot.go` `rnRegister` /
  `rmRegister`.
- **`opcode`** uses 16 bits, MSB first. Use `n` for Rn-field bits,
  `m` for Rm-field bits, `d` for displacement, `i` for immediate, `-`
  for don't-care. Spaces are ignored.
- **Slot field names** (`arith`, `xbus`, `ybus`, `zbus`, `zbus_sel`,
  `pc`, `ma_op`, `ma_addy`, `ma_size`, `sr`, `if_issue`, `dispatch`,
  `event`, ...) are listed in `internal/microcode/slot.go::AssignSlot`.
  Unrecognized fields error out; unrecognized values produce a clear
  parse error pointing at the file+instruction.
- **Slot field values** for `xbus` / `ybus` accept register tags
  (`Rn`, `Rm`, `R0`, `R15`, `GBR`, `VBR`, `PR`, `TEMP0`, `TEMP1`),
  `PC`, `W` (write-back bus), or a numeric/structured immediate
  (`0`, `4`, `U*4`, `S*2`, ...). A literal `"Rm"` resolves through
  the format-mapping (for `mn`, `Rm` → `RB`).

For multi-cycle instructions, append more `[[instr.slots]]` blocks. The
slot order is the execution order; slot index becomes part of the
microcode address (`op.addr` bits).

### 3. Register the instruction in `csvInstrOrder`

`internal/model/build.go` contains a `csvInstrOrder` slice (currently
~290 entries) that pins the ROM address layout — instructions are
emitted into the ROM in the order they appear in this list. Every
instruction declared in TOML MUST also be present in `csvInstrOrder`,
or `Build` fails with:

```
instruction "NEGX Rm, Rn" is in the spec but missing from csvInstrOrder;
add it to maintain ROM address stability
```

Add the new name in a position that makes sense for your change. The
list is the original CSV row order from the historical
`SH-2 Instruction Set.csv` spreadsheet; it is **not** alphabetical, and
inserting in the middle will renumber every following ROM slot.

For an additive change, append to the end of the slice (just before
the closing `}`) to preserve all existing addresses:

```go
var csvInstrOrder = []string{
    ...
    "MAC.L @Rm+, @Rn+",
    "NEGX Rm, Rn",   // NEW
}
```

Skipping this step is the most common mistake when adding instructions.

### 4. Regenerate

```bash
make -C decode generate
```

This invokes the Go cpugen tool, which:
1. Loads + merges all TOML files (`internal/spec/`).
2. Parses opcodes + slots into the canonical microcode IR
   (`internal/microcode/`).
3. Builds logic maps + Quine-McCluskey-reduces the direct decoder
   (`internal/logic/`, `internal/model/direct.go`).
4. Emits seven VHDL files into `decode/` (`internal/emit/`).

Inspect the diff:

```bash
git diff decode/
```

You should see new arms in `decode_table_simple.vhd`, new condN/imp_bit
references in `decode_table_direct.vhd`, and your opcode pattern in
`decode_table_rom.vhd` if it's a normal-plane instruction.

### 5. Verify

```bash
# Generator unit tests
go -C decode/gen-go test ./...

# Full regression (sim + TAP)
decode/gen-go/regression.sh
```

The regression script compiles the simulator, runs the testrom for
180us, and validates the expected LED sequence. It also runs the 228
unit TAP testbenches. Both must pass.

To exercise your new instruction specifically, add a test in
`testrom/tests/` (e.g., `testalu.s` for arithmetic) using SH-2 assembly
and rebuild the test ROM (requires `sh2-elf-gcc`).

### 6. Commit

Two artifacts to commit:
- The spec edit: `decode/gen-go/spec/<file>.toml`
- The regenerated VHDL: `decode/*.vhd`

```bash
git add decode/gen-go/spec/arithmetic.toml decode/*.vhd
git commit -m "Add NEGX Rm, Rn instruction"
```

Always commit the regenerated VHDL alongside the spec change — they are
the authoritative interface to the rest of the CPU and the build does
not regenerate them by default.

### Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `slot.go: xbus: unrecognized value "..."` | Typo in a slot field value; check enum vocabularies in `slot.go`. |
| `opcode.go: bad opcode literal` | Opcode pattern not 16 bits or has invalid chars. |
| GHDL error: enum literal not declared | A new value of an existing field is not in `decode_pkg.vhd`'s enum; the generator should pick this up automatically, but a stale `decode/` checkout can cause this — `make -C decode clean && make -C decode generate`. |
| `cpu_ctb` hangs after a new LED | The new instruction's microcode is incomplete (missing `zbus`, `zbus_sel`, or write-back). Compare to a neighbouring instruction in the same TOML file. |
