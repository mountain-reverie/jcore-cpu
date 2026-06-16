#!/usr/bin/env bash
# Build + run the dcache unit scoreboard testbench in one clock-mode.
# Usage: sim/cache_sim.sh <sc|dc>
set -euo pipefail
MODE="${1:?usage: cache_sim.sh <sc|dc>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
JCORE_SOC="${JCORE_SOC:-$ROOT/jcore-soc}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# --syn-binding: the cache instantiates dcache/dcache_ram/ram_2rw as COMPONENTS;
# ghdl's plain default binding leaves them unbound (black boxes) in elaboration,
# so use synthesis default binding to bind component->entity (same as synth).
GHDLFLAGS="--std=93 -fexplicit --ieee=synopsys --syn-binding"
G="ghdl -a $GHDLFLAGS --workdir=$WORK"

case "$MODE" in
  sc) CLK=cache/cache_clkmode_sc.vhd
      # No cache_config_fpga.vhd: in simulation ghdl default-binds the cache's
      # ram_2rw/ram_1rw components to the only analysed architecture (inferred).
      RAMTECH=( "$JCORE_SOC/lib/memory_tech_lib/tech/inferred/ram_1rw_infer.vhd"
                "$JCORE_SOC/lib/memory_tech_lib/tech/inferred/ram_2rw_infer.vhd" )
      TOP=dcache_check_sc ; TBCFG=cache/dcache_check_tb_cfg_sc.vhd ;;
  dc) CLK=cache/cache_clkmode_dc.vhd
      RAMTECH=( "$JCORE_SOC/lib/memory_tech_lib/tech/sim/ram_18x2048_1rw_sim.vhd"
                "$JCORE_SOC/lib/memory_tech_lib/tech/sim/ram_2x8x256_1rw_sim.vhd"
                "$JCORE_SOC/lib/memory_tech_lib/tech/sim/ram_2x8x2048_2rw_sim.vhd"
                "$JCORE_SOC/lib/memory_tech_lib/tech/sim/rom_32x2048_1r_sim.vhd"
                "$JCORE_SOC/lib/memory_tech_lib/tech/sim/mem_sim_config.vhd" )
      TOP=dcache_check_dc ; TBCFG=cache/dcache_check_tb_cfg_dc.vhd ;;
  *) echo "ERROR: mode must be sc or dc" >&2; exit 1 ;;
esac

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
  "$TBCFG"
)
for f in "${FILES[@]}"; do echo "--- analyze $(basename "$f")"; $G "$f"; done
echo "=== run ($MODE) ==="
# mcode backend: elaborate+run via -r (no standalone binary from -e).
ghdl -r $GHDLFLAGS --workdir="$WORK" "$TOP" \
  --assert-level=error --stop-time=2ms
echo "cache_sim.sh: $MODE OK"
