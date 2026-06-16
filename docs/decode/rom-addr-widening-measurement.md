# ECP5 direct-vs-rom decoder measurement (J4)

**Tool:** `yosys` `synth_ecp5 -top cpu` via `synth/cpu_synth.sh ecp5`, J4 decoder
(`make -C decode generate-j4`), commit on branch `decode/rom-addr-widen`.
**Build inputs:** `.vhm` sources preprocessed with `jcore-soc/tools/v2p` (mult,
datapath, decode_core). Both variants elaborate cleanly (exit 0).

Reproduce:

```bash
JS=/path/to/jcore-soc
make -C decode generate-j4
for f in core/mult core/datapath decode/decode_core; do
  LD_LIBRARY_PATH='' perl "$JS/tools/v2p" < "$f.vhm" > "$f.vhd"; done
SYNTH_VARIANT=j4 DECODER=direct bash synth/cpu_synth.sh ecp5   # build/cpu_ecp5.json
SYNTH_VARIANT=j4 DECODER=rom    bash synth/cpu_synth.sh ecp5
```

## Result (bare `cpu`, ECP5 / abc9)

| metric        | direct | rom  | delta |
|---------------|--------|------|-------|
| LUT4          | 4504   | 4544 | **+40** |
| TRELLIS_FF    | 966    | 967  | +1    |
| DP16KD (EBR)  | 0      | 3    | **+3** |
| MULT18X18D    | 2      | 2    | 0     |

## Decision: keep `direct` (do NOT adopt `rom`)

The hypothesis — that the BRAM-backed `rom` decoder would collapse the J4 decode
LUT4 onto block RAM — **did not hold**. Switching direct→rom *adds* ~40 LUT4 and
consumes 3 DP16KD block-RAMs, the opposite of a win.

Why: the microcode-*storage* logic that `rom` relocates into BRAM is not the LUT4
driver — abc9 minimizes the direct microcode-line generation effectively. The
real decode cost is the shared downstream control-signal derivation (the logic
that turns the ~75-bit microcode line into datapath control) plus
`predecode_rom_addr`, and **both decoder variants keep that logic identically**.
So `rom` pays BRAM + addressing overhead for no LUT4 relief, while also
introducing a clocked falling-edge half-cycle read (not measured for Fmax here,
but a known downside) and a dependency on EBR availability.

Per the design's decision rule ("adopt `rom` for the FPGA target only on a clear
LUT4 win with no Fmax regression"), the LUT4 result alone settles it: **not
adopted**. `direct` remains the default for sim, ASIC, and FPGA.

### Consequence for the PM2 `synth-size` alert

The J4 ECP5 area growth that triggered the alert is **inherent to the decode
logic of the added SH-4 instructions**, and is not relievable by the decoder
implementation swap. It is the genuine cost of the larger J4 instruction set;
there is no cheap structural win available on the decoder side.

The `DECODER=rom` knob (`synth/cpu_synth.sh` + `synth/cpu_synth_j4_rom_config.vhd`)
is retained as the reproducer for this measurement and for re-evaluation if the
microcode word width or instruction count changes materially.
