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

mkdir -p build

# .vhm -> .vhd for the CPU cores (mirrors .github/workflows/synth-cpu.yml)
for f in core/mult core/datapath decode/decode_core; do
  LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
done

rm -f build/cpu_timing.json
SYNTH_VARIANT=j4c synth/cpu_synth.sh timing > "build/synth-$LABEL.log" 2>&1

# Guard against the TLB-pruned-away failure mode in synthesis.
tlbrefs_synth=$(grep -ci tlb "build/synth-$LABEL.log" || true)
if [ "$tlbrefs_synth" -lt 1000 ]; then
  echo "ERROR: only $tlbrefs_synth tlb refs in yosys log -- the MMU is not in this netlist" >&2
  exit 1
fi

nextpnr-ecp5 --85k --package CABGA381 --json build/cpu_timing.json \
  --lpf synth/ulx3s_cpu.lpf --lpf-allow-unconstrained --timing-allow-fail \
  --textcfg build/cpu_timing.config > "build/nextpnr-$LABEL.log" 2>&1

log="build/nextpnr-$LABEL.log"

# Extract clock name and Fmax from the FINAL "Max frequency" line (post-route).
# The log contains Info (intermediate, pruned) and Warning (final, post-route) lines;
# tail -1 selects the post-route value. Extract the clock name to query the same
# clock's critical path block, preventing cross-clock confusion with multiple clocks.
fmax_line=$(grep -oE "Max frequency for clock '[^']*': [0-9.]+ MHz" "$log" | tail -1) || true
[ -n "$fmax_line" ] || { echo "ERROR: no 'Max frequency for clock' line found in nextpnr log" >&2; exit 1; }

clock_name=$(echo "$fmax_line" | grep -oE "'[^']*'" | head -1 | tr -d "'")
[ -n "$clock_name" ] || { echo "ERROR: could not extract clock name from: $fmax_line" >&2; exit 1; }

fmax=$(echo "$fmax_line" | grep -oE '[0-9.]+' | head -1)
[ -n "$fmax" ] || { echo "ERROR: could not extract Fmax value from: $fmax_line" >&2; exit 1; }

# Extract the critical path report block for this specific clock.
# Fail if zero blocks match (clock missing) or if more than one matches (e.g., setup+hold analysis).
critical_blocks=$(grep -n "^Critical path report for clock '$clock_name'" "$log" | cut -d: -f1)
block_count=$(echo "$critical_blocks" | grep -c . || echo 0)
if [ "$block_count" -ne 1 ]; then
  echo "ERROR: found $block_count critical path blocks for clock '$clock_name' (expected 1)" >&2
  exit 1
fi

block_line=$(echo "$critical_blocks" | head -1)
# Extract from this block until the cross-domain section (or end of file)
critical_section=$(sed -n "${block_line},/^Cross-domain\|^$/p" "$log" | sed '/^Cross-domain\|^$/d')
[ -n "$critical_section" ] || { echo "ERROR: critical path section for clock '$clock_name' is empty" >&2; exit 1; }

# Extract logic and routing delays from this block.
logic=$(echo "$critical_section" | grep -oE "[0-9.]+ ns logic" | head -1 | grep -oE '[0-9.]+' || true)
[ -n "$logic" ] || { echo "ERROR: could not extract logic delay for clock '$clock_name'" >&2; exit 1; }

rout=$(echo "$critical_section" | grep -oE "[0-9.]+ ns routing" | head -1 | grep -oE '[0-9.]+' || true)
[ -n "$rout" ] || { echo "ERROR: could not extract routing delay for clock '$clock_name'" >&2; exit 1; }

# Count Source lines (critical path depth) in this block only.
levels=$(echo "$critical_section" | grep -c "Source" || true)
[ "$levels" -gt 0 ] || { echo "ERROR: no critical path sources found in block for clock '$clock_name'" >&2; exit 1; }

# Guard against TLB pruning in the P&R stage. Empirical: MMU build has tlb/mmu refs
# in the log; no-MMU build has 0. Fail if zero; nonzero means TLB made it through P&R.
tlbrefs_pnr=$(grep -ci "tlb\|mmu" "$log" || true)
if [ "$tlbrefs_pnr" -eq 0 ]; then
  echo "ERROR: zero tlb/mmu refs in nextpnr log -- the MMU was pruned in P&R" >&2
  exit 1
fi

printf '%s Fmax=%s logic=%s routing=%s levels=%s\n' \
  "$LABEL" "$fmax" "$logic" "$rout" "$levels" \
  | tee "build/fmax-$LABEL.txt"
