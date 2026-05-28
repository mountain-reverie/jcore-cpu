#!/bin/bash
# synth-check.sh — synthesis-coverage gate for the J-Core CPU.
#
# Elaborates the `cpu` entity through both FPGA configurations with
# `ghdl --synth`. This catches synthesis-only defects that simulation
# misses: ill-formed clock expressions, inferred latches from incomplete
# assignments, non-synthesizable idioms. The configurations are required —
# they force full elaboration of decode_core into the netlist (a bare
# `-e cpu` leaves the sub-units as unbound black boxes and misses the
# defect).
#
# Scope: the synthesizable CPU core hierarchy (cpu -> decode, datapath,
# mult, register files). The sim-only `decode_table_simple` (cpu_decode_simple)
# and all testbenches are excluded.
#
# Environment:
#   TOOLS_DIR — path to jcore-soc/tools (provides the v2p preprocessor).
#               Default: ../jcore-soc/tools relative to repo root.
#
# Exit status: 0 if every configuration synthesizes cleanly, non-zero
# otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/../jcore-soc/tools}"

if [ ! -x "$TOOLS_DIR/v2p" ]; then
    echo "synth-check: v2p not found/executable at $TOOLS_DIR/v2p" >&2
    echo "             set TOOLS_DIR to your jcore-soc/tools checkout" >&2
    exit 2
fi

cd "$REPO_ROOT"

# 1. Convert the three v2p sources to VHDL (build artifacts, regenerated each run).
for vhm in core/mult.vhm core/datapath.vhm decode/decode_core.vhm; do
    out="${vhm%.vhm}.vhd"
    echo "    convert $vhm -> $out"
    LD_LIBRARY_PATH='' perl "$TOOLS_DIR/v2p" < "$vhm" > "$out"
done

# 2. Analysis file set, in dependency order. Excludes decode_table_simple
#    (sim-only, non-ASCII comments) and all testbenches.
FILES=(
    cpu2j0_pkg.vhd
    core/components_pkg.vhd
    core/mult_pkg.vhd
    decode/decode_pkg.vhd
    core/datapath_pkg.vhd
    core/mult.vhd
    core/datapath.vhd
    core/register_file.vhd
    decode/decode.vhd
    decode/decode_body.vhd
    decode/decode_table.vhd
    decode/decode_core.vhd
    decode/decode_table_direct.vhd
    decode/decode_table_direct_config.vhd
    decode/decode_table_rom.vhd
    decode/decode_table_rom_config.vhd
    core/register_file_flops.vhd
    core/register_file_two_bank.vhd
    core/cpu.vhd
    core/cpu_config.vhd
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# -C (--mb-comments) tolerates non-ASCII chars in generated VHDL comments.
GHDL_FLAGS=(--std=93 -fexplicit -C --ieee=synopsys "--workdir=$WORK")

echo "==> analyze"
ghdl -a "${GHDL_FLAGS[@]}" "${FILES[@]}"

# 3. Synthesize each FPGA configuration. ill-formed clock / latch / other
#    legality errors surface here as a non-zero exit and/or "error:" lines.
synth_one() {
    local cfg="$1"
    local log
    log="$WORK/$cfg.synth.log"
    echo "==> ghdl --synth $cfg"
    if ! ghdl --synth "${GHDL_FLAGS[@]}" "$cfg" >"$log" 2>&1; then
        echo "    FAIL [$cfg]: ghdl --synth exited non-zero" >&2
        grep -iE 'error|ill-formed' "$log" | head -20 | sed 's/^/         /' >&2
        return 1
    fi
    if grep -qiE '^[^ ]*:[0-9]+:[0-9]+: ?error:' "$log"; then
        echo "    FAIL [$cfg]: synthesis reported errors" >&2
        grep -iE 'error|ill-formed' "$log" | head -20 | sed 's/^/         /' >&2
        return 1
    fi
    echo "    PASS [$cfg]"
}

rc=0
synth_one cpu_decode_direct_fpga || rc=1
synth_one cpu_decode_rom_fpga    || rc=1

if [ $rc -ne 0 ]; then
    echo "synth-check: FAILED" >&2
    exit 1
fi
echo "synth-check: all configurations synthesize cleanly"
