#!/usr/bin/env bash
# fmax_ab.sh <label> -- full-rebuild ECP5 Fmax measurement for j4c (CPU+MMU+cache).
#
# Reports a SEED SWEEP (mean/median/range over FMAX_AB_SEEDS place-and-route
# runs, default 6), NOT a single number. Placement variance on this design is
# ~1.5-3 MHz; single-seed A/Bs have produced sign errors. See the sweep block
# below before trusting or changing this.
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


check_synth_log() {
  local synth_log="$1"
  [ -f "$synth_log" ] || { echo "ERROR: synth log not found: $synth_log" >&2; return 1; }
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

  # NOTE: there used to be a second MMU-presence guard here that grepped the
  # nextpnr LOG for "tlb|mmu" hit count. That check was anti-correlated with
  # success: those names only appeared in the log because nextpnr prints the
  # critical-path report, and the names showed up in it only when the TLB sat
  # on the critical path. Once the TLB is no longer the bottleneck (e.g. after
  # this branch's tree-balancing work moved it off the critical path), the
  # hit count legitimately collapses toward zero even though the MMU is fully
  # present in the design -- observed: baseline 49 hits, b2-iside-v2 52 hits,
  # b2-both 1 hit, despite b2-both's synthesized netlist (build/cpu_timing.json,
  # the JSON actually handed to nextpnr) containing ~5205 tlb-named cells and
  # its yosys log (checked by check_synth_log above, threshold 1000) containing
  # 5217. nextpnr places and routes whatever is in that JSON; it does not prune
  # logic. check_synth_log's >=1000-tlb-refs-in-yosys-log check already proves
  # the MMU survived synthesis into the exact netlist P&R consumes, which is a
  # more direct and reliable proof of presence than counting name occurrences
  # in a nextpnr log whose content depends on where the critical path happens
  # to run. So this second guard is deleted rather than "fixed" against a
  # source (the nextpnr log) that cannot distinguish "pruned" from "no longer
  # the bottleneck".

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

# ---------------------------------------------------------------------------
# SEED SWEEP. Synthesis is deterministic; PLACEMENT is not, and on this design
# the seed-to-seed Fmax band is ~1.5-3 MHz -- WIDER than any effect this project
# has ever tried to measure. A single-seed A/B therefore resolves nothing.
#
# This is not hypothetical. On 2026-08-12 a single-seed measurement reported a
# change as +1.31 MHz and that number justified an entire multi-task
# optimisation program; a 6-seed sweep showed the true effect was -1.26 MHz --
# the OPPOSITE SIGN. 27.86 had been a bad draw and 29.17 a good one.
#
# So: synthesize ONCE, place-and-route N times, report the distribution.
# Compare arms by MEAN, and treat any difference smaller than the observed
# range as UNRESOLVED rather than real.
# ---------------------------------------------------------------------------
SEEDS="${FMAX_AB_SEEDS:-6}"
mkdir -p build/pnr-$LABEL
fmax_vals=()

for seed in $(seq 1 "$SEEDS"); do
  seed_log="build/pnr-$LABEL/nextpnr_seed$seed.log"
  nextpnr-ecp5 --85k --package CABGA381 --json build/cpu_timing.json \
    --lpf synth/ulx3s_cpu.lpf --lpf-allow-unconstrained --timing-allow-fail \
    --seed "$seed" \
    --textcfg "build/pnr-$LABEL/cpu_timing_seed$seed.config" > "$seed_log" 2>&1
  v=$(grep -oE "Max frequency for clock '[^']*': [0-9.]+ MHz" "$seed_log" \
        | tail -1 | grep -oE '[0-9.]+' | head -1)
  if [ -n "$v" ]; then
    fmax_vals+=("$v")
    echo "  seed $seed: $v MHz"
  else
    echo "  seed $seed: PARSE FAILED (see $seed_log)" >&2
  fi
done

[ "${#fmax_vals[@]}" -gt 0 ] || { echo "ERROR: no seed produced an Fmax" >&2; exit 1; }

# Keep the single-seed artefacts the old interface promised, so callers and the
# FMAX_AB_PARSE_ONLY hook still find build/nextpnr-<label>.log.
cp "build/pnr-$LABEL/nextpnr_seed1.log" "build/nextpnr-$LABEL.log"

printf '%s\n' "${fmax_vals[@]}" | sort -g | awk -v label="$LABEL" -v n="${#fmax_vals[@]}" '
  { v[NR]=$1; sum+=$1 }
  END {
    mean = sum/NR
    median = (NR%2) ? v[(NR+1)/2] : (v[NR/2]+v[NR/2+1])/2
    for (i=1;i<=NR;i++) { d=v[i]-mean; ss+=d*d }
    sd = (NR>1) ? sqrt(ss/(NR-1)) : 0
    printf "%s  n=%d  mean=%.2f  median=%.2f  min=%.2f  max=%.2f  range=%.2f  sd=%.2f MHz\n", \
           label, NR, mean, median, v[1], v[NR], v[NR]-v[1], sd
    printf "NOTE: compare arms by MEAN. A difference smaller than range (%.2f MHz)\n", v[NR]-v[1]
    printf "      is NOT resolved by this sample -- increase FMAX_AB_SEEDS.\n"
  }' | tee "build/fmax-$LABEL.txt"
