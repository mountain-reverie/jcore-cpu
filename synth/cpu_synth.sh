#!/usr/bin/env bash
# Thin synthesis kernel for the full jcore cpu. ONE job: produce a netlist for
# the requested backend. Downstream tooling (Nangate45 map, OpenSTA, nextpnr,
# ecppack, stat parsing, gating) is the caller's responsibility.
#
# Preconditions (the caller MUST satisfy these first):
#   1. `make -C decode generate`   (decode*.vhd + sh2instr.c present)
#   2. vhm->vhd preprocessing via v2p has produced:
#        core/mult.vhd  core/datapath.vhd  decode/decode_core.vhd
#
# Usage: synth/cpu_synth.sh <asic|ecp5|timing|ice40>
#   asic   -> build/cpu_asic.v    (generic netlist)
#   ecp5   -> build/cpu_ecp5.json  (synth_ecp5/abc9 netlist of the bare cpu)
#   timing -> build/cpu_timing.json (synth_ecp5 of the cpu_timing_top harness;
#             the netlist the ECP5 Fmax regression gate is measured on)
#   ice40  -> build/cpu_ice40.json (synth_ice40 of the cpu_timing_top harness;
#             the netlist nextpnr-ice40 P&Rs on the up5k for the fit gauge)
#
# Variant selection (env var SYNTH_VARIANT, default j2):
#   j2 -> elaborate cpu_synth_direct (the default; J2 hardware multiplier).
#   j1 -> elaborate cpu_synth_j1 (sequential mult(seq) + shifter(seq), no hw
#         multiplier/barrel); adds core/mult_seq.vhd + core/shifter_seq.vhd +
#         synth/cpu_synth_j1_config.vhd to the file list.
#   j4 -> elaborate cpu_synth_j4 (== J2 today);
#         adds synth/cpu_synth_j4_config.vhd to the file list.
# When SYNTH_VARIANT is unset or j2 the synth commands are byte-identical to the
# original J2-only script (so the existing J2 dashboard series is unbroken).
set -euo pipefail

BACKEND="${1:?usage: cpu_synth.sh <asic|ecp5|timing|ice40>}"
SYNTH_VARIANT="${SYNTH_VARIANT:-j2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/build"; mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Fail early with a helpful message if preconditions are unmet.
for f in core/mult.vhd core/datapath.vhd decode/decode_core.vhd \
         decode/decode.vhd decode/decode_body.vhd; do
  [ -f "$f" ] || { echo "ERROR: $f missing — run 'make -C decode generate' and v2p preprocessing first (see synth/README.md)" >&2; exit 1; }
done

FILES=(
  cpu2j0_pkg.vhd
  core/components_pkg.vhd
  core/mult_pkg.vhd
  core/datapath_pkg.vhd
  decode/decode_pkg.vhd
  core/cpu.vhd
  core/mult.vhd
  core/shifter.vhd
  core/datapath.vhd
  core/register_file.vhd
  core/register_file_flops.vhd
  core/register_file_two_bank.vhd
  core/register_file_ebr.vhd
  decode/decode.vhd
  decode/decode_body.vhd
  decode/decode_table.vhd
  decode/decode_table_direct.vhd
  decode/decode_table_direct_config.vhd
  decode/decode_core.vhd
  synth/cpu_synth_config.vhd
  synth/cpu_timing_top.vhd
  synth/cpu_timing_config.vhd
)

# Map variant -> (cpu top configuration, timing-harness configuration, extra
# files). TIMING_TOP binds the harness's core instance to the variant's cpu
# config so the representative Fmax measures the selected variant, not always J2.
case "$SYNTH_VARIANT" in
  j2)
    TOP="cpu_synth_direct"; TIMING_TOP="cpu_timing_j2"
    ;;
  j1)
    TOP="cpu_synth_j1"; TIMING_TOP="cpu_timing_j1"
    FILES+=(core/mult_seq.vhd core/shifter_seq.vhd synth/cpu_synth_j1_config.vhd)
    ;;
  j4)
    if [ "${DECODER:-direct}" = "rom" ]; then
      TOP="cpu_synth_j4_rom"; TIMING_TOP="cpu_timing_j4"
      FILES+=(synth/cpu_synth_j4_rom_config.vhd decode/decode_table_rom.vhd decode/decode_table_rom_config.vhd)
    else
      TOP="cpu_synth_j4"; TIMING_TOP="cpu_timing_j4"
      FILES+=(synth/cpu_synth_j4_config.vhd)
    fi
    ;;
  *) echo "ERROR: unknown SYNTH_VARIANT '$SYNTH_VARIANT' (want j1|j2|j4)" >&2; exit 1 ;;
esac

GHDL_BASE="ghdl --std=93 -fexplicit --ieee=synopsys --workdir=$WORK ${FILES[*]}"

case "$BACKEND" in
  asic)
    # Strip verification cells emitted from VHDL `assert` statements so the
    # written netlist re-reads cleanly downstream: chformal -remove drops
    # $assert/$assume/$cover; `delete t:$check t:$print` drops the $check/$print
    # cells (ghdl 6 + yosys 0.44) whose verilog backend otherwise emits empty
    # `initial` blocks that OpenSTA's reader rejects.
    yosys -m ghdl -p "$GHDL_BASE -e $TOP; synth -top cpu; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_verilog $OUT/cpu_asic.v"
    ;;
  ecp5)
    # abc9 (synth_ecp5 default) gives timing-driven LUT mapping. It works now
    # that the issue/slot false combinational loop is broken in core/datapath.vhm
    # (see synth/README.md). Strip verification cells (as above) so nextpnr-ecp5
    # can consume the JSON.
    yosys -m ghdl -p "$GHDL_BASE -e $TOP; synth_ecp5 -top cpu; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_ecp5.json"
    ;;
  timing)
    # Representative Fmax benchmark: the cpu_timing_top harness registers the
    # core's ~348 boundary signals down to 4 IO (synth/cpu_timing_top.vhd), so
    # nextpnr places the core compactly and reports a true register->core->
    # register Fmax instead of the bare-core IO-scatter artifact. This netlist
    # is what the ECP5 timing regression gate measures. Elaborates the
    # per-variant harness config so J1/J4 measure their own core, not J2.
    yosys -m ghdl -p "$GHDL_BASE -e $TIMING_TOP; synth_ecp5 -top cpu_timing_top; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_timing.json"
    ;;
  ice40)
    # iCE40 up5k fit gauge. The bare cpu cannot P&R on up5k (too many
    # unconstrained boundary IO), so synthesize the cpu_timing_top harness — the
    # same one the ECP5 representative-Fmax path uses (boundary registered to 4
    # IO). nextpnr-ice40 (run by the caller) then places & routes it on the up5k
    # and reports ICESTORM_LC/RAM/DSP utilisation + Fmax. Elaborates the
    # per-variant harness config so J1 measures its own core.
    yosys -m ghdl -p "$GHDL_BASE -e $TIMING_TOP; synth_ice40 -dsp -top cpu_timing_top; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_ice40.json"
    ;;
  *) echo "ERROR: unknown backend '$BACKEND' (want asic|ecp5|timing|ice40)" >&2; exit 1 ;;
esac
echo "cpu_synth.sh: $BACKEND OK"
