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
# Usage: synth/cpu_synth.sh <asic|ecp5>
#   asic -> build/cpu_asic.v   (generic netlist)
#   ecp5 -> build/cpu_ecp5.json (synth_ecp5 -noabc9 netlist)
set -euo pipefail

BACKEND="${1:?usage: cpu_synth.sh <asic|ecp5>}"
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
)

GHDL_ANALYZE="ghdl --std=93 -fexplicit --ieee=synopsys --workdir=$WORK ${FILES[*]} -e cpu_synth_direct"

case "$BACKEND" in
  asic)
    yosys -m ghdl -p "$GHDL_ANALYZE; synth -top cpu; check -assert; stat; write_verilog $OUT/cpu_asic.v"
    ;;
  ecp5)
    # -noabc9: the cpu has a documented false combinational SCC (datapath+decode
    # forwarding) that abc9 rejects with 'Assert no_loops failed'. Generic abc and
    # production Xilinx/Altera tolerate it. See synth/README.md.
    yosys -m ghdl -p "$GHDL_ANALYZE; synth_ecp5 -noabc9 -top cpu; check -assert; stat; write_json $OUT/cpu_ecp5.json"
    ;;
  *) echo "ERROR: unknown backend '$BACKEND' (want asic|ecp5)" >&2; exit 1 ;;
esac
echo "cpu_synth.sh: $BACKEND OK"
