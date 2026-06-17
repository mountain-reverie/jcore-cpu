#!/usr/bin/env bash
# Build + run the dcache unit scoreboard testbench in one clock-mode.
# Usage: sim/cache_sim.sh <sc|dc>
set -euo pipefail
MODE="${1:?usage: cache_sim.sh <sc|dc>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
JCORE_SOC="${JCORE_SOC:-$ROOT/jcore-soc}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# The dcache CCL/MCL cores are .vhm templates; preprocess to .vhd via jcore-soc's
# v2p (same as synth/cpu_synth.sh) so a clean checkout (CI) has them.
for f in cache/dcache_ccl cache/dcache_mcl; do
  LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
done
# --syn-binding: the cache instantiates dcache/dcache_ram/ram_2rw as COMPONENTS;
# ghdl's plain default binding leaves them unbound (black boxes) in elaboration,
# so use synthesis default binding to bind component->entity (same as synth).
GHDLFLAGS="--std=93 -fexplicit --ieee=synopsys --syn-binding"
G="ghdl -a $GHDLFLAGS --workdir=$WORK"

MTL="$JCORE_SOC/lib/memory_tech_lib"
case "$MODE" in
  sc) CLK=cache/cache_clkmode_sc.vhd ; GEN=""
      # single-clock: inferred (1R+1W BRAM) RAM. ghdl --syn-binding binds the
      # cache's ram_2rw/ram_1rw components to the only analysed arch (inferred).
      RAMTECH=( "$MTL/tech/inferred/ram_1rw_infer.vhd"
                "$MTL/tech/inferred/ram_2rw_infer.vhd" ) ;;
  dc) CLK=cache/cache_clkmode_dc.vhd ; GEN=""
      # ASIC RAM form: cache_clkmode_dc selects the 2-write-port dcache_ram
      # generate (the dual-port dual-clock structure a real ASIC SRAM macro maps
      # to). We drive it on a TIED single clock (DUAL_CLOCK=false) with the
      # inferred RAM, so this exercises the 2-write-port structure CI-portably.
      # (A *true* dual-clock run -- clk125!=clk200 -- needs the tech/sim VITAL
      # macro, which the CI ghdl's IEEE has no vital_timing for; deferred. The
      # 2-write-port form's CDC timing is unchanged by the 1R+1W work and is
      # covered by jcore-soc's own dual-clock flows.)
      RAMTECH=( "$MTL/tech/inferred/ram_1rw_infer.vhd"
                "$MTL/tech/inferred/ram_2rw_infer.vhd" ) ;;
  *) echo "ERROR: mode must be sc or dc" >&2; exit 1 ;;
esac
TOP=dcache_check_tb

FILES=(
  cpu2j0_pkg.vhd
  synth/cpu_cache_config.vhd
  "$JCORE_SOC/lib/reg_file_struct/bist_pkg.vhd"
  "$JCORE_SOC/targets/data_bus_pkg.vhd"
  "$JCORE_SOC/components/ddr2/ddrc_cnt_pkg.vhd"
  "$JCORE_SOC/components/dma/dma_pkg.vhd"
  "$JCORE_SOC/lib/memory_tech_lib/memory_pkg.vhd"
  "$CLK"
  cache/cache_pkg.vhd
  "$JCORE_SOC/lib/memory_tech_lib/ram_1rw.vhd"
  "$JCORE_SOC/lib/memory_tech_lib/ram_2rw.vhd"
  "${RAMTECH[@]}"
  cache/dcache_ccl.vhd
  cache/dcache_mcl.vhd
  cache/dcache_ram.vhd
  cache/dcache.vhd
  cache/dcache_adapter.vhd
  cache/dcache_check_tb.vhd
)
for f in "${FILES[@]}"; do echo "--- analyze $(basename "$f")"; $G "$f"; done
echo "=== run ($MODE) ==="
# mcode backend: elaborate+run via -r (no standalone binary from -e).
RUNLOG="$WORK/run.log"
ghdl -r $GHDLFLAGS --workdir="$WORK" "$TOP" $GEN \
  --assert-level=error --stop-time=2ms 2>&1 | tee "$RUNLOG"
# A hung load would run to stop-time and exit 0; require the explicit pass line.
grep -q "ALL TESTS PASSED" "$RUNLOG" || { echo "ERROR: '$MODE' did not reach ALL TESTS PASSED" >&2; exit 1; }
echo "cache_sim.sh: $MODE OK"
