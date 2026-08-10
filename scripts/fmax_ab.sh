#!/usr/bin/env bash
# fmax_ab.sh <label> -- full-rebuild ECP5 Fmax measurement for j4c (CPU+MMU+cache).
#
# ALWAYS a full rebuild. Do not add a skip-build flag: a stale build silently
# measures the previous RTL, which is the dominant failure mode for this kind
# of A/B (see CLAUDE.md on sim/mmu_sim.sh -n).
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <label>" >&2; exit 1; }
LABEL="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
export JCORE_SOC="${JCORE_SOC:-$ROOT/../jcore-soc}"
[ -d "$JCORE_SOC" ] || { echo "ERROR: JCORE_SOC not found at $JCORE_SOC" >&2; exit 1; }

# .vhm -> .vhd for the CPU cores (mirrors .github/workflows/synth-cpu.yml)
for f in core/mult core/datapath decode/decode_core; do
  LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
done

rm -f build/cpu_timing.json
SYNTH_VARIANT=j4c synth/cpu_synth.sh timing > "build/synth-$LABEL.log" 2>&1

# Guard against the TLB-pruned-away failure mode this whole effort exists to fix.
tlbrefs=$(grep -ci tlb "build/synth-$LABEL.log" || true)
if [ "$tlbrefs" -lt 1000 ]; then
  echo "ERROR: only $tlbrefs tlb refs in the yosys log -- the MMU is not in this netlist" >&2
  exit 1
fi

nextpnr-ecp5 --85k --package CABGA381 --json build/cpu_timing.json \
  --lpf synth/ulx3s_cpu.lpf --lpf-allow-unconstrained --timing-allow-fail \
  --textcfg build/cpu_timing.config > "build/nextpnr-$LABEL.log" 2>&1

log="build/nextpnr-$LABEL.log"
fmax=$(grep -oE "Max frequency for clock '[^']*': [0-9.]+ MHz" "$log" | tail -1 | grep -oE '[0-9.]+' | head -1)
logic=$(grep -oE "[0-9.]+ ns logic" "$log" | head -1 | grep -oE '[0-9.]+')
rout=$(grep -oE "[0-9.]+ ns routing" "$log" | head -1 | grep -oE '[0-9.]+')
levels=$(awk '/Critical path report for clock/{f=1} /cross-domain/{exit} f' "$log" | grep -c "Source" || true)

printf '%s Fmax=%s logic=%s routing=%s levels=%s\n' \
  "$LABEL" "${fmax:-UNKNOWN}" "${logic:-?}" "${rout:-?}" "${levels:-?}" \
  | tee "build/fmax-$LABEL.txt"
