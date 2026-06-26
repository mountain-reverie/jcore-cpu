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
| **J2** | Baseline SH-2 core; 2–3 cycle Karatsuba multiplier (`mult(stru)`) | `cpu_j2` | `cpu_synth_direct` (`SYNTH_VARIANT=j2`) | `make -C decode generate` | Unchanged baseline |
| **J1** | Smaller variant; sequential shift-add multiplier (`mult(seq)`, ~34 cycles/32-bit) replaces the hardware array. Same ISA; multiply stalls longer; ~9% fewer cells (≈17 059 → ≈15 542 on ECP5) | `cpu_j1` | `cpu_synth_j1` | `make -C decode generate` (same as J2) | Working; area reduction verified |
| **J4** | SH-4 **user-space** target (perf/watt, perf/area; not kernel-space compatible). Privileged core: MMU + 32-entry TLB, banked R0–R7, register-model exceptions. Gated by `PRIV_ARCH`/`MMU_ARCH` generics; bare `cpu_j4` (both false) == J2 | `cpu_j4` / `cpu_sim` | `cpu_synth_j4` · `cpu_synth_j4_priv` · `cpu_cache_timing_j4_priv_mmu` (j4c) | `make -C decode generate-j4` (base SH-2 + populated `sh4/` overlay) | Implemented & tested; MMU synthesizable (j4c ASIC, +9k cells) |

### Per-variant architecture documents

Each variant has a dedicated architecture document with a block diagram, unit
descriptions, and its design goal:

- **[J1 — Area-Optimised SH-2 Core](j1.md)** — sequential multiplier, iterative
  shifter, EBR register file and ROM decoder to fit small FPGAs (iCE40 up5k).
- **[J2 — Baseline SH-2 Core](j2.md)** — the reference implementation; the
  performance and correctness yardstick every other variant is measured against.
- **[J4 — SH-4 Privileged Core](j4.md)** — targets the SH-4 **user-space** ABI for
  best performance-per-watt / per-area (kernel-space SH-4 compat is a non-goal).
  Adds privilege (`SR.MD/RB/BL`), an MMU with a 32-entry hardware TLB, banked
  registers, and SH-4 register-model exceptions (`SPC`/`SSR`, replacing J2's SH-2
  stack model — see [j4.md](j4.md) → *Exception model*), gated by the `PRIV_ARCH`/`MMU_ARCH`
  generics (bare `cpu_j4` is byte-identical to J2).

This document covers the cross-cutting concerns shared by all three (configuration
mechanism, build/sim/synth flows, the L1-cache CDC, and the J2 invariant).

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

# J4 uses the base spec + the populated sh4/ overlay (LDTLB, banked moves, etc.):
make -C decode generate-j4
```

`generate-j4` expands to:
```
go -C decode/gen-go run ./cmd/cpugen -w 72 -overlay spec/sh4 -o ..
```

The `-overlay` flag causes the generator to call `spec.LoadProfile(base, overlay)`,
which merges the SH-4 overlay additively on top of the SH-2 base.  The overlay
under `decode/gen-go/spec/sh4/` (`mmu.toml`, `bank.toml`, `exceptions.toml`) adds
the SH-4 control/TLB/exception opcodes — see [j4.md](j4.md) for the instruction
list.

`generate-j4` is a **transient** synth/test step: it never edits the committed
base decode tables (the ones J1/J2 use). CI re-runs a plain `make -C decode
generate` and asserts the base tables are byte-unchanged, so the overlay cannot
leak into J1/J2. The merge logic itself is covered by the generator unit test:
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

`cpu_synth.sh` takes a backend (`asic|ecp5|timing`) and selects the variant via
the `SYNTH_VARIANT` env var (default `j2`):

```bash
# J2 (baseline), ASIC generic netlist:
SYNTH_VARIANT=j2 synth/cpu_synth.sh asic     # == default; byte-identical to before

# J1 (smaller; sequential multiplier), ECP5:
SYNTH_VARIANT=j1 synth/cpu_synth.sh ecp5

# J4 baseline (generics off == J2), representative-Fmax harness:
SYNTH_VARIANT=j4 synth/cpu_synth.sh timing

# Full J4 + privilege + MMU + cache (check -assert gated):
SYNTH_VARIANT=j4c synth/cpu_synth.sh asic
```

CI runs a `{j1,j2,j4}` variant matrix over the synth + metrics jobs.  The
dashboard overlays the three variants as colored series: J1 = yellow, J2 = blue,
J4 = green.

---

## J4 extension seams

Every SH-4 feature attaches at a defined seam WITHOUT touching J2 sources — either
inside a `PRIV_ARCH`/`MMU_ARCH` generate guard or in an additive file (overlay
`.toml`, new architecture, new entity). The table below records the seam *and* its
current realization. Full detail is in [j4.md](j4.md).

| SH-4 feature | Seam | Status |
|---|---|---|
| **Privilege / `SR.MD/RB/BL`, exceptions** | `spec/sh4/{mmu,exceptions}.toml` overlay + `if PRIV_ARCH` logic in `core/datapath.vhm` / `decode/decode_core.vhm` | **Implemented & tested** (SH-4 register-model exceptions overriding the SH-2 stack model, `EXPEVT/INTEVT/TRA` on `priv_o`). Gated by `PRIV_ARCH`; J2 unchanged. |
| **Banked registers (R0–R7)** | `register_file(two_bank)` with `BANKED ⇐ PRIV_ARCH`; `bank_remap` in datapath; `bank.toml` moves | **Implemented & tested** (`banktest`, `STC Rm_BANK`). `.L` multi-slot variants deferred (microcode-ROM budget). |
| **MMU / TLB** | `core/tlb.vhd` instantiated under `core/cpu.vhd` `g_mmu : if MMU_ARCH generate`; MMU CSRs + `mmu_o` PA tags | **Implemented, tested & synthesizable** (32-entry CAM, j4c ASIC `+9k` cells). Gated by `MMU_ARCH`. |
| **L2 cache** | new hierarchy entity composed around the existing `cache/` I/D caches; bound in the J4 SoC config | **Future** — not yet implemented; new files only when added. |

The J2 `datapath(stru)`, the base decode tables, and the L1 cache entities all
remain byte-stable: the SH-4 hardware appears only when the generics are turned on
or the overlay is generated.

---

## L1 cache: single-clock CDC and Fmax

The `cache/` I/D caches (`icache`, `dcache`) carry a small bidirectional
clock-domain-crossing (CDC) between a CPU-side domain (`clk125`) and a memory-side
domain (`clk200`) — an XOR-toggle level handshake with "phase element" registers
(`bcen_value_halfcb0`, `bmen_value_halfcb2`). The CDC form is selected at analysis
time by `cache/cache_clkmode_{sc,dc}.vhd` (the `CACHE_SAME_CLOCK` constant), the
same sim/ecp5-arch-split idiom used elsewhere:

- **`_dc` (dual-clock, ASIC):** phase elements are transparent latches that sample
  the other domain mid-cycle (metastability hardening). This is the form the
  dual-clock testbench / native-ASIC flow uses.
- **`_sc` (single-clock, every FPGA — `clk125`=`clk200`):** the metastability
  hardening is vestigial (one clock net), so the phase elements are clocked on the
  **posedge (full cycle)**. This removes the **T/2 half-cycle timing path** that was
  the cache Fmax limiter on the ULX3S.

**Latency characteristic (single-clock):** the posedge form costs **+1 cycle per
phase-element path**. A cache **hit is unaffected**; a cache **miss is +2 cycles**
(the miss round-trip crosses both `dcache` phase elements — cpu→mem request and
mem→cpu critical word). This is a deliberate trade: misses are dominated by SDRAM
fill latency, so +2 CPU-side cycles is negligible, while the higher Fmax benefits
every cycle. Verified by the dcache scoreboard (`sim/cache_sim.sh sc`): hit = 2
cycles, cold-miss 10 → 12. A CI guard asserts the single-clock cpu+cache netlist
contains no negedge flip-flops, so the T/2 path cannot silently regress.

## The J2 invariant — J2 must elaborate byte-identically

The invariant J4 work preserves is **byte-identical J2 elaboration**, not literal
no-edit. The real rule has two parts:

1. **Additive by default** — SH-4 work prefers new files: the `spec/sh4/` overlay,
   `core/tlb.vhd`, new configurations.
2. **Guarded when shared sources must change** — where a shared file *is* touched
   (`core/cpu.vhd`, `core/datapath.vhm`, `decode/decode_core.vhm` all carry SH-4
   logic today), every addition sits inside an `if PRIV_ARCH`/`if MMU_ARCH`
   generate or generic guard that is **inert when the generic is `false`**. With
   the generics off, the netlist is byte-identical to the pre-J4 baseline, and CI
   asserts this (j1/j2/j4 byte-identical synth; base decode tables unchanged after
   `generate-j4`).

The following J2 sources must therefore remain byte-stable *in their off-path*
(unguarded logic untouched; any J4 addition strictly behind a generic guard):

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

Any J4 logic added to one of these shared files must be confined to a
generic-guarded block (`if PRIV_ARCH` / `if MMU_ARCH`) so that with the generics
off J2's build and benchmark series remain byte-stable. Anything that cannot be so
guarded must instead become a new file (new architecture, new overlay `.toml`, new
configuration).
