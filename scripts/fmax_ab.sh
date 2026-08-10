#!/usr/bin/env bash
# fmax_ab.sh <label> -- full-rebuild ECP5 Fmax measurement for j4c (CPU+MMU+cache).
#
# ALWAYS a full rebuild. Do not add a skip-build flag: a stale build silently
# measures the previous RTL, which is the dominant failure mode for this kind
# of A/B (see CLAUDE.md on sim/mmu_sim.sh -n).
#
# Internal test hook: FMAX_AB_PARSE_ONLY=1 skips the build/synth/pnr steps and
# runs parse_logs() directly against build/synth-<label>.log and
# build/nextpnr-<label>.log that already exist. Used only for validating the
# parser against saved logs / doctored failure-path fixtures; the normal path
# (this var unset) always does a full rebuild.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <label>" >&2; exit 1; }
LABEL="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

mkdir -p build

# Minimum tlb/mmu-name occurrences required in the nextpnr log for the MMU to
# be considered present post-P&R. Calibrated against the actual j4c-mmu
# baseline log in this tree: 49 tlb/mmu hits (grep -ci "tlb|mmu" over the
# console critical-path + slack-histogram output). The broken no-MMU build
# had 0. 49 is the full observed signal in this log format, so require at
# least half of it (25) rather than bare non-zero, which is indistinguishable
# from a single stray comment surviving pruning.
TLB_PNR_MIN=25

check_synth_log() {
  local synth_log="$1"
  # Guard against the TLB-pruned-away failure mode in synthesis.
  local tlbrefs_synth
  tlbrefs_synth=$(grep -ci tlb "$synth_log" || true)
  if [ "$tlbrefs_synth" -lt 1000 ]; then
    echo "ERROR: only $tlbrefs_synth tlb refs in yosys log -- the MMU is not in this netlist" >&2
    return 1
  fi
}

parse_logs() {
  local label="$1" synth_log="$2" log="$3"

  check_synth_log "$synth_log" || return 1

  # Extract clock name and Fmax from the FINAL "Max frequency" line (post-route).
  # The log contains Info (intermediate, pruned) and Warning (final, post-route) lines;
  # tail -1 selects the post-route value. Extract the clock name to query the same
  # clock's critical path block, preventing cross-clock confusion with multiple clocks.
  local fmax_line
  fmax_line=$(grep -oE "Max frequency for clock '[^']*': [0-9.]+ MHz" "$log" | tail -1) || true
  [ -n "$fmax_line" ] || { echo "ERROR: no 'Max frequency for clock' line found in nextpnr log" >&2; return 1; }

  local distinct_clocks
  distinct_clocks=$(grep -oE "Max frequency for clock '[^']*'" "$log" | sort -u | wc -l)
  if [ "$distinct_clocks" -ne 1 ]; then
    echo "ERROR: found $distinct_clocks distinct clocks reported in nextpnr log (expected 1); refusing to guess which one" >&2
    return 1
  fi

  local clock_name
  clock_name=$(echo "$fmax_line" | grep -oE "'[^']*'" | head -1 | tr -d "'")
  [ -n "$clock_name" ] || { echo "ERROR: could not extract clock name from: $fmax_line" >&2; return 1; }

  local fmax
  fmax=$(echo "$fmax_line" | grep -oE '[0-9.]+' | head -1)
  [ -n "$fmax" ] || { echo "ERROR: could not extract Fmax value from: $fmax_line" >&2; return 1; }

  # Extract the critical path report block for this specific clock. nextpnr
  # prefixes every line with "Info: " or "Warning: "; anchor on that, not on
  # the bare message text. Fail if zero blocks match (clock missing) or if
  # more than one matches (e.g., setup+hold analysis) -- never guess which
  # one is "the" critical path.
  local critical_blocks block_count
  critical_blocks=$(grep -n "^Info: Critical path report for clock '$clock_name' " "$log" | cut -d: -f1)
  block_count=$(echo "$critical_blocks" | grep -c . || echo 0)
  if [ "$block_count" -ne 1 ]; then
    echo "ERROR: found $block_count critical path blocks for clock '$clock_name' (expected 1)" >&2
    return 1
  fi

  local block_line critical_section
  block_line=$(echo "$critical_blocks" | head -1)
  # The block runs from its header line to the next blank line (nextpnr
  # separates each critical-path / cross-domain report with a bare blank
  # line, not an "Info:"-prefixed one).
  critical_section=$(sed -n "${block_line},/^\$/p" "$log")
  [ -n "$critical_section" ] || { echo "ERROR: critical path section for clock '$clock_name' is empty" >&2; return 1; }

  # Extract logic and routing delays from this block (line: "Info: X ns logic, Y ns routing").
  local logic rout
  logic=$(echo "$critical_section" | grep -oE "[0-9.]+ ns logic" | head -1 | grep -oE '[0-9.]+' || true)
  [ -n "$logic" ] || { echo "ERROR: could not extract logic delay for clock '$clock_name'" >&2; return 1; }

  rout=$(echo "$critical_section" | grep -oE "[0-9.]+ ns routing" | head -1 | grep -oE '[0-9.]+' || true)
  [ -n "$rout" ] || { echo "ERROR: could not extract routing delay for clock '$clock_name'" >&2; return 1; }

  # Count Source lines (critical path depth) in this block only.
  local levels
  levels=$(echo "$critical_section" | grep -c "Source" || true)
  [ "$levels" -gt 0 ] || { echo "ERROR: no critical path sources found in block for clock '$clock_name'" >&2; return 1; }

  # Guard against TLB pruning in the P&R stage. Empirical (this baseline log):
  # MMU build has 49 tlb/mmu hits; no-MMU build has 0. Require a real margin
  # above zero, not bare presence -- see TLB_PNR_MIN comment above.
  local tlbrefs_pnr
  tlbrefs_pnr=$(grep -ci "tlb\|mmu" "$log" || true)
  if [ "$tlbrefs_pnr" -lt "$TLB_PNR_MIN" ]; then
    echo "ERROR: only $tlbrefs_pnr tlb/mmu refs in nextpnr log (need >= $TLB_PNR_MIN) -- the MMU was pruned in P&R" >&2
    return 1
  fi

  printf '%s Fmax=%s logic=%s routing=%s levels=%s\n' \
    "$label" "$fmax" "$logic" "$rout" "$levels" \
    | tee "build/fmax-$label.txt"
}

if [ "${FMAX_AB_PARSE_ONLY:-0}" = "1" ]; then
  parse_logs "$LABEL" "build/synth-$LABEL.log" "build/nextpnr-$LABEL.log"
  exit $?
fi

export JCORE_SOC="${JCORE_SOC:-$ROOT/../jcore-soc}"
[ -d "$JCORE_SOC" ] || { echo "ERROR: JCORE_SOC not found at $JCORE_SOC" >&2; exit 1; }

# .vhm -> .vhd for the CPU cores (mirrors .github/workflows/synth-cpu.yml)
for f in core/mult core/datapath decode/decode_core; do
  LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
done

rm -f build/cpu_timing.json
SYNTH_VARIANT=j4c synth/cpu_synth.sh timing > "build/synth-$LABEL.log" 2>&1

check_synth_log "build/synth-$LABEL.log"

nextpnr-ecp5 --85k --package CABGA381 --json build/cpu_timing.json \
  --lpf synth/ulx3s_cpu.lpf --lpf-allow-unconstrained --timing-allow-fail \
  --textcfg build/cpu_timing.config > "build/nextpnr-$LABEL.log" 2>&1

parse_logs "$LABEL" "build/synth-$LABEL.log" "build/nextpnr-$LABEL.log"
