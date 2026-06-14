# CPU Variants: J1 / J2 / J4

## Overview

The J-Core CPU is built as a single VHDL entity (`cpu` in `core/cpu.vhd`) with
multiple variants selected via **VHDL `configuration`** blocks.  Two orthogonal
axes control what a variant looks like:

| Axis | Mechanism | J1 | J2 | J4 |
|---|---|---|---|---|
| **Hardware units** | VHDL `configuration` binding sub-unit architectures | `mult(seq)` replaces array multiplier | baseline `mult(stru)` | `mult(stru)` today; SH-4 units attach here later |
| **Decoder / ISA** | Go generator: base spec + per-variant overlay | unchanged (base only) | baseline (base only) | base + `decode/gen-go/spec/sh4/` overlay |

Both axes are additive: J1 and J4 only add files and configurations — they
never edit J2 sources.

---

## Variants at a glance

| Variant | What it is | Sim config | Synth config | Decoder | Status |
|---|---|---|---|---|---|
| **J2** | Baseline SH-2 core; 2–3 cycle Karatsuba multiplier (`mult(stru)`) | `cpu_j2` | `cpu_synth_j1` (alias of `cpu_synth_direct`) | `make -C decode generate` | Unchanged baseline |
| **J1** | Smaller variant; sequential shift-add multiplier (`mult(seq)`, ~34 cycles/32-bit) replaces the hardware array. Same ISA; multiply stalls longer; ~9% fewer cells (≈17 059 → ≈15 542 on ECP5) | `cpu_j1` | `cpu_synth_j1` | `make -C decode generate` (same as J2) | Working; area reduction verified |
| **J4** | SH-4 placeholder == J2 today. Separate config exists so SH-4 units attach here without touching J2 | `cpu_j4` | `cpu_synth_j4` | `make -C decode generate-j4` (byte-identical to J2 while `sh4/` overlay is empty) | Placeholder; parity with J2 verified |

### Configuration file locations

Simulation configurations — `core/cpu_config.vhd`:
- `cpu_j2` — binds `mult(stru)`, direct decoder, two-bank register file.
- `cpu_j1` — identical to `cpu_j2` except binds `mult(seq)`.
- `cpu_j4` — identical to `cpu_j2` today; SH-4 units will bind here.

Synthesis configurations — `synth/`:
- `synth/cpu_synth_config.vhd` — original J2 synth config (`cpu_synth_direct`).
- `synth/cpu_synth_j1_config.vhd` — `cpu_synth_j1`; binds `mult(seq)`.
- `synth/cpu_synth_j4_config.vhd` — `cpu_synth_j4`; today == J2 synth.

---

## Building and simulating each variant

### Decoder generation

```bash
# J2 and J1 share the same generated decoder (base spec only):
make -C decode generate

# J4 uses the base spec + the sh4/ overlay (byte-identical while overlay is empty):
make -C decode generate-j4
```

`generate-j4` expands to:
```
go -C decode/gen-go run ./cmd/cpugen -w 72 -overlay spec/sh4 -o ..
```

The `-overlay` flag causes the generator to call `spec.LoadProfile(base, overlay)`,
which merges the SH-4 overlay additively on top of the SH-2 base.  While
`decode/gen-go/spec/sh4/` contains only `.gitkeep`, the merged spec is identical
to the base, so the J4 decoder output is byte-for-byte identical to J2's.

Verify parity with the generator unit test:
```bash
go -C decode/gen-go test ./internal/spec -run LoadProfile
# TestLoadProfile_EmptyOverlayIsNoop --- PASS
# TestLoadProfile_OverlayAddsInstr   --- PASS
```

### GHDL simulation

Elaborate the desired variant by naming its configuration.  Example for J1:
```bash
ghdl -e --std=08 -fsynopsys cpu_j1
ghdl -r --std=08 -fsynopsys cpu_j1 ...
```

The `tests/mult_seq_tap.vhd` testbench verifies J1's sequential multiplier
directly (12 cases including saturating cross-checks against `mult(stru)`).  It
uses a direct entity instantiation of `work.mult(seq)` so the binding is
unambiguous.  The testbench is listed in `tests/TESTS` and picked up by the
standard TAP runner.

To run the J1 multiplier testbench through the sim Makefile:
```bash
cd sim
make TAP=mult_seq_tap
```

### Synthesis

```bash
# J2 (baseline):
cd synth && ./cpu_synth.sh cpu_synth_direct

# J1 (smaller; no hardware multiplier):
cd synth && ./cpu_synth.sh cpu_synth_j1

# J4 (placeholder == J2 today):
cd synth && ./cpu_synth.sh cpu_synth_j4
```

CI runs a `{j1,j2,j4}` variant matrix over the synth + metrics jobs.  The
dashboard overlays the three variants as colored series: J1 = yellow, J2 = blue,
J4 = green.

---

## J4 extension seams

Each future SH-4 feature attaches at a defined seam WITHOUT touching J2 sources.

### Privileged instructions / SR.MD

- Add instruction definitions to `decode/gen-go/spec/sh4/` (new `.toml` files).
- Run `make -C decode generate-j4`; this produces a distinct `decode_j4_*`
  decoder package once the overlay is non-empty.
- Bind the J4-specific decoder in `cpu_j4` (`core/cpu_config.vhd`), while
  `cpu_j2` continues to bind the original `decode` entity.
- Add SR.MD datapath logic in a new J4-specific datapath architecture
  (`core/datapath_j4.vhm`).  The J2 `datapath(stru)` is untouched.

### Banked registers (R0–R7 bank switch)

- Add a new architecture of `register_file` (e.g. `register_file_banked.vhd`),
  following the existing pattern of `register_file_flops.vhd` vs
  `register_file_two_bank.vhd`.
- Bind it in `cpu_j4` via the `u_regfile` for-use clause.  J2's binding
  (`two_bank`) is unchanged.

### MMU / TLB

- Add a new address-translation unit (a new entity, e.g. `tlb.vhd`) inserted
  in the instruction and data memory paths.
- In J4 SoC integration, wrap `cpu`'s bus ports through the TLB.  J2 SoC
  integration is pass-through and untouched.

### L2 cache

- Add a new cache-hierarchy entity composed around the existing `cache/` I/D
  caches (`icache`, `dcache`).  New files only; existing cache entities unchanged.
- Bind the L2 unit in the J4 SoC configuration.

---

## The J2 invariant — files that must not be edited for J4 work

SH-4 work ONLY adds files (under `spec/sh4/`, new architectures, new
configurations).  The following J2 sources must stay untouched:

| File | Role |
|---|---|
| `core/cpu.vhd` | Top-level CPU entity (shared by all variants) |
| `core/datapath.vhm` | 32-bit execution datapath |
| `core/mult.vhm` | J2 Karatsuba multiplier (`mult(stru)`) |
| `core/mult_pkg.vhd` | Multiplier port types and microcode constants |
| `decode/decode_core.vhm` | Pipeline orchestration and control |
| `decode/decode_pkg.vhd` | Generated decoder control types |
| `decode/decode.vhd` | Generated decoder entity |
| `decode/decode_body.vhd` | Generated decode logic |
| `decode/decode_table_simple.vhd` | Simple decoder table |
| `decode/decode_table_direct.vhd` | QMC-reduced direct decoder |
| `decode/decode_table_rom.vhd` | ROM-based decoder |
| `decode/gen-go/spec/*.toml` | SH-2 instruction set specification |

Any change needed for J4 that would otherwise touch one of these files must
instead be expressed as a new file (new architecture, new overlay `.toml`, new
configuration) so that J2's build and benchmark series remain byte-stable.
