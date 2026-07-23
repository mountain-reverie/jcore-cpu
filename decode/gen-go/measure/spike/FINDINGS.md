# Task 1 Spike — Findings

Measurement mechanism **proven working** on the J2 cosim (`sim/cpu_ctb`, default
`cpu_sim` build). Raw run (`latspike.S` → `latspike.img`, `--log-ops`):

```
LED 0x11 @160   0x12 @1180   ! calA 100 nop  Δ=1020ns
LED 0x13 @1200  0x14 @3220   ! calB 200 nop  Δ=2020ns
LED 0x21 @3240  0x22 @4220   ! indep add x96 Δ=980ns
LED 0x31 @4240  0x32 @5260   ! dep   add x100 Δ=1020ns
LED 0x41 @5280  0x42 @9270   ! indep mul.l x100 Δ=3990ns
```

## Resolved constants (feed all later tasks)

- **Marker address:** `0xABCD0000`, **byte** write (`mov.b rX,@r14`), `PIO_ADDR`
  in `sim/cpu_ctb.c`. Emits `LED: WRITE 0xNN at <ns> ns`.
- **Trace line format:** `LED: WRITE 0x%02X at %d ns` — regex confirmed.
- **ns/cycle = 10** (100 MHz). Derived by the **difference method**
  (calB−calA = 1000ns / 100 nops), which cancels marker overhead. Use this, not a
  single bracket.
- **Marker overhead = 2 cycles**, constant. Subtract 2 cycles from every bracket's
  cycle count before dividing by op count.
- **Build:** `%.elf` rule needs an explicit `.o` prereq (empty `$^` → empty elf);
  build steps manually: `sh2-elf-gcc -m2 -Os -Iinclude -c x.S -o x.o` →
  `sh2-elf-ld -T sh32.x x.o $(libgcc) -o x.elf` → `objcopy -S -O binary … x.img`.
  Header/vect/`SIM_INSTR_MAGIC` block copied from `sim/tests/sh2a_movml0.S`;
  `_done` writes 0, `_fail` writes 1 to `TEST_RESULT_ADDRESS`.

## Measured values (J2 `cpu_sim` build)

| bench | cycles | per-op | verdict |
|-------|--------|--------|---------|
| add issue (96 indep) | 98−2=96 | **1.00** | ✓ matches expectation |
| add latency (100 dep) | 102−2=100 | **1.00** | ✓ |
| mul.l issue (100 indep) | 399−2=397 | **~3.97 ≈ 4** | ✗ **hand table says 2** |

## Finding A — hand values are wrong (validates the project)

`timing/j2.toml` hand-claims the `mult` unit issue=**2**; the J2 sim measures
**~4**. This is exactly the class of error the audit exists to fix. **Consequence
for the plan:** the calibration self-check must NOT anchor on suspect hand values
(`mul.l≈2`, `tas≈4`). Trustworthy anchors only: **`add`/`nop` issue=latency=1**
(fundamental, confirmed) and **ns/cycle self-consistency** (calA/calB agree).
Multi-cycle costs (mul.l, divs) are *outputs to be measured*, not assumed inputs —
so the gate becomes "add=1 and calA/calB agree", and known multi-cycle ops are
sanity-*reported*, not hard-gated on their old hand numbers.

## Finding B — J1 is NOT measurable without a new cosim config (scope decision)

Every sim configuration in `core/cpu_config.vhd` binds `u_shifter →
shifter(comb)` and `u_datapath → datapath(stru)` (with `mult(stru)`). The J1
iterative units — `shifter(seq)` (`core/shifter_seq.vhd`) and `mult(seq)`
(`core/mult_seq.vhd`) — **exist** but are bound **only in the J1 synthesis path**,
never in a cosim config. Therefore:

- **J2 / J2A / J4 share one sim datapath** (barrel shifter, array mult) and differ
  only in decode/microcode/priv/SH2A-gated units. Those differences (SH-2A ops,
  movml loops, two-word, the `divs` divider, etc.) **ARE measurable** per variant.
- **J1's datapath-driven timing** (multi-cycle iterative shifts; `mult(seq)`
  multi-cycle mul, with slot-stretch stalls) is **NOT measurable** as-is. Options:
  1. **Descope J1 to hand values** (`source="hand"`), measure J2/J2A/J4. Smaller.
  2. **Add a prerequisite task:** a new `cpu_sim_j1` cosim config binding
     `shifter(seq)` + `mult(seq)` (+ the DSP-ALU datapath), then measure J1 too.
     `mult(seq)` slot-stretch is already validated in sim, so the wiring exists;
     this is a bounded but real addition.

## Recommendation

Proceed with the harness for **J2 / J2A / J4** (measurable now). For **J1**, add a
`cpu_sim_j1` config task if we want measured J1 numbers; otherwise J1 stays
hand-valued. Revise the calibration gate per Finding A (anchor on add=1 +
calA/calB agreement, not on hand multi-cycle values).
