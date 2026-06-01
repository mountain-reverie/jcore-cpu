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
# Usage: synth/cpu_synth.sh <asic|ecp5|timing>
#   asic   -> build/cpu_asic.v    (generic netlist)
#   ecp5   -> build/cpu_ecp5.json  (synth_ecp5/abc9 netlist of the bare cpu)
#   timing -> build/cpu_timing.json (synth_ecp5 of the cpu_timing_top harness;
#             the netlist the ECP5 Fmax regression gate is measured on)
set -euo pipefail

BACKEND="${1:?usage: cpu_synth.sh <asic|ecp5|timing>}"
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
  core/datapath.vhd
  core/register_file.vhd
  core/register_file_flops.vhd
  core/register_file_two_bank.vhd
  decode/decode.vhd
  decode/decode_body.vhd
  decode/decode_table.vhd
  decode/decode_table_direct.vhd
  decode/decode_table_direct_config.vhd
  decode/decode_core.vhd
  synth/cpu_synth_config.vhd
  synth/cpu_timing_top.vhd
)

GHDL_BASE="ghdl --std=93 -fexplicit --ieee=synopsys --workdir=$WORK ${FILES[*]}"

case "$BACKEND" in
  asic)
    # Strip verification cells emitted from VHDL `assert` statements so the
    # written netlist re-reads cleanly downstream: chformal -remove drops
    # $assert/$assume/$cover; `delete t:$check t:$print` drops the $check/$print
    # cells (ghdl 6 + yosys 0.44) whose verilog backend otherwise emits empty
    # `initial` blocks that OpenSTA's reader rejects.
    yosys -m ghdl -p "$GHDL_BASE -e cpu_synth_direct; synth -top cpu; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_verilog $OUT/cpu_asic.v"
    ;;
  ecp5)
    # abc9 (synth_ecp5 default) gives timing-driven LUT mapping. It works now
    # that the issue/slot false combinational loop is broken in core/datapath.vhm
    # (see synth/README.md). Strip verification cells (as above) so nextpnr-ecp5
    # can consume the JSON.
    yosys -m ghdl -p "$GHDL_BASE -e cpu_synth_direct; synth_ecp5 -top cpu; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_ecp5.json"
    ;;
  timing)
    # Representative Fmax benchmark: the cpu_timing_top harness registers the
    # core's ~348 boundary signals down to 4 IO (synth/cpu_timing_top.vhd), so
    # nextpnr places the core compactly and reports a true register->core->
    # register Fmax instead of the bare-core IO-scatter artifact. This netlist
    # is what the ECP5 timing regression gate measures.
    yosys -m ghdl -p "$GHDL_BASE -e cpu_timing_top; synth_ecp5 -top cpu_timing_top; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_timing.json"
    ;;
  *) echo "ERROR: unknown backend '$BACKEND' (want asic|ecp5|timing)" >&2; exit 1 ;;
esac
echo "cpu_synth.sh: $BACKEND OK"
