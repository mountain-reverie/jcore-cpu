#!/bin/bash
# synth-check.sh — synthesis-coverage gate for the J-Core CPU.
#
# Two independent gates, selectable so CI can run them as parallel jobs on
# different (lightweight, cached) toolchains:
#
#   --legality  Elaborate the `cpu` entity through both FPGA configurations
#               with `ghdl --synth`. Catches synthesis-only legality defects
#               that simulation misses: ill-formed clock expressions, inferred
#               latches, non-synthesizable idioms. Needs only GHDL (e.g.
#               ghdl/setup-ghdl). The configurations are required — they force
#               full elaboration of decode_core into the netlist (a bare
#               `-e cpu` leaves sub-units as unbound black boxes).
#
#   --ecp5      Map both configurations to real ECP5 primitives with yosys
#               `synth_ecp5`. Catches technology-mapping issues a legality
#               check cannot. Needs yosys + ghdl-yosys-plugin (e.g. the
#               oss-cad-suite).
#
#   --all       Both (default). The ECP5 step is skipped if yosys/plugin are
#               absent, so a bare local GHDL install still runs the legality
#               gate.
#
# Scope: the synthesizable CPU core hierarchy (cpu -> decode, datapath,
# mult, register files). The sim-only `decode_table_simple` (cpu_decode_simple)
# and all testbenches are excluded.
#
# Environment:
#   TOOLS_DIR — path to jcore-soc/tools (provides the v2p preprocessor).
#               Default: ../jcore-soc/tools relative to repo root.
#
# Exit status: 0 if every selected gate passes, non-zero otherwise.

set -euo pipefail

MODE="${1:-all}"
case "$MODE" in
    --legality)        DO_LEGALITY=1; DO_ECP5=0; ECP5_REQUIRED=0 ;;
    --ecp5)            DO_LEGALITY=0; DO_ECP5=1; ECP5_REQUIRED=1 ;;
    all|--all|"")      DO_LEGALITY=1; DO_ECP5=1; ECP5_REQUIRED=0 ;;
    *)
        echo "usage: synth-check.sh [--legality|--ecp5|--all]" >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/../jcore-soc/tools}"
# Absolutize so a relative TOOLS_DIR works regardless of the caller's CWD.
TOOLS_DIR="$(cd "$TOOLS_DIR" 2>/dev/null && pwd || echo "$TOOLS_DIR")"

if [ ! -x "$TOOLS_DIR/v2p" ]; then
    echo "synth-check: v2p not found/executable at $TOOLS_DIR/v2p" >&2
    echo "             set TOOLS_DIR to your jcore-soc/tools checkout" >&2
    exit 2
fi

cd "$REPO_ROOT"

# Convert the three v2p sources to VHDL (build artifacts, regenerated each run).
for vhm in core/mult.vhm core/datapath.vhm decode/decode_core.vhm; do
    out="${vhm%.vhm}.vhd"
    echo "    convert $vhm -> $out"
    LD_LIBRARY_PATH='' perl "$TOOLS_DIR/v2p" < "$vhm" > "$out"
done

# Analysis file set, in dependency order. Excludes decode_table_simple
# (sim-only, non-ASCII comments) and all testbenches.
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

# --- legality gate: ghdl --synth -------------------------------------------
synth_one() {
    local cfg="$1"
    local log="$WORK/$cfg.synth.log"
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

# --- ECP5 mapping gate: yosys synth_ecp5 -----------------------------------
# Uses -abc2 rather than the default abc9: abc9 hard-asserts on a pre-existing
# combinational loop (a slot-gated path through the two-bank register file)
# that classic abc, generic yosys synth, and the Xilinx flow all tolerate.
# -abc2 still performs full ECP5 mapping.
ecp5_supported() {
    command -v yosys >/dev/null 2>&1 && yosys -m ghdl -p 'help synth_ecp5' >/dev/null 2>&1
}

ecp5_one() {
    local cfg="$1"
    local ework="$WORK/ecp5_$cfg"
    local log="$WORK/$cfg.ecp5.log"
    mkdir -p "$ework"
    echo "==> synth_ecp5 $cfg"
    if ! yosys -m ghdl -p "ghdl ${GHDL_FLAGS[*]} --workdir=$ework ${FILES[*]} -e $cfg; synth_ecp5 -abc2 -top cpu; stat" >"$log" 2>&1; then
        echo "    FAIL [$cfg]: synth_ecp5 failed" >&2
        grep -iE 'error|loop|assert' "$log" | head -20 | sed 's/^/         /' >&2
        return 1
    fi
    local cells
    cells=$(grep -E 'Number of cells:' "$log" | tail -1 | awk '{print $NF}')
    echo "    PASS [$cfg] (ECP5 cells: ${cells:-?})"
}

rc=0

if [ "$DO_LEGALITY" -eq 1 ]; then
    echo "==> analyze"
    ghdl -a "${GHDL_FLAGS[@]}" "${FILES[@]}"
    synth_one cpu_decode_direct_fpga || rc=1
    synth_one cpu_decode_rom_fpga    || rc=1
fi

if [ "$DO_ECP5" -eq 1 ]; then
    if ecp5_supported; then
        ecp5_one cpu_decode_direct_fpga || rc=1
        ecp5_one cpu_decode_rom_fpga    || rc=1
    elif [ "$ECP5_REQUIRED" -eq 1 ]; then
        echo "    FAIL: --ecp5 requires yosys + ghdl plugin, not found" >&2
        rc=1
    else
        echo "==> synth_ecp5: SKIP (yosys + ghdl plugin not available)"
    fi
fi

if [ $rc -ne 0 ]; then
    echo "synth-check: FAILED" >&2
    exit 1
fi
echo "synth-check: OK"
