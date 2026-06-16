#!/usr/bin/env bash
# Full-CPU Nangate45 tech-map + OpenSTA. Extends regression.sh Step 8 (which
# times the decoder unit) to the whole cpu. Best-effort and NON-GATING: if the
# Liberty file or `sta` is unavailable, warn and exit 0 so callers (metrics.py)
# simply emit no ASIC timing metrics.
#
# Precondition: synth/cpu_synth.sh asic has written build/cpu_asic.v.
# Outputs: build/cpu_asic_mapped.v, build/cpu_asic_sta.rpt
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build"; mkdir -p "$OUT"

NANGATE_LIB="${NANGATE_LIB:-/opt/nangate45/nangate45.lib}"
TARGET_MHZ="${ECP5_TARGET_MHZ:-50}"
PERIOD_NS="$(awk -v m="$TARGET_MHZ" 'BEGIN{printf "%.4f", 1000.0/m}')"

# cpu+cache variants (j2c/j4c) have a different top (cpu_cache_timing_top) with
# two clocks (clk125 cpu-side, clk200 mem-side); the bare cpu has one `clk`.
SYNTH_VARIANT="${SYNTH_VARIANT:-j2}"
case "$SYNTH_VARIANT" in
  j2c|j4c) STA_TOP="cpu_cache_timing_top" ;;
  *)       STA_TOP="cpu" ;;
esac

if [ ! -f "$OUT/cpu_asic.v" ]; then
  echo "WARN: $OUT/cpu_asic.v missing — run synth/cpu_synth.sh asic first; skipping STA" >&2
  exit 0
fi
if ! command -v sta >/dev/null 2>&1; then
  echo "WARN: opensta (sta) not installed — skipping ASIC STA" >&2
  exit 0
fi
if [ ! -f "$NANGATE_LIB" ]; then
  echo "WARN: Nangate45 Liberty not at $NANGATE_LIB — skipping ASIC STA" >&2
  exit 0
fi

# 1) Tech-map to Nangate45. cpu_synth.sh writes cpu_asic.v as HIERARCHICAL
# behavioral Verilog (cpu instantiates datapath/decode/mult submodules), so a
# bare `abc` would only map the top module's own logic and leave the submodule
# logic as generic cells with unknown area — breaking both `stat -liberty` and
# OpenSTA. `synth -flatten` re-synthesizes it to a single flat gate-level module
# first; then dfflibmap + abc map to Nangate45. splitnets -ports + clean -purge
# + -noattr mirror regression.sh Step 7 to avoid escaped-identifier
# concatenations that OpenSTA's Verilog reader cannot parse.
# (Flattening loses per-module area; per-block ASIC area is a future refinement.)
if ! yosys -p "read_verilog $OUT/cpu_asic.v; synth -top $STA_TOP -flatten; dfflibmap -liberty $NANGATE_LIB; abc -liberty $NANGATE_LIB; splitnets -ports; clean -purge; stat -liberty $NANGATE_LIB; write_verilog -noattr $OUT/cpu_asic_mapped.v" \
     | tee "$OUT/cpu_asic_mapped_stat.txt"; then
  echo "WARN: yosys tech-map failed — ASIC timing absent" >&2
  exit 0
fi

# 2) Static timing. Virtual clock + the design clock(s) at PERIOD_NS. cpu+cache
# is dual-clock (clk125 cpu-side / clk200 mem-side, asynchronous CDC so the
# half-cycle/CDC paths are not timed across domains); the bare cpu has one clk.
if [ "$STA_TOP" = "cpu_cache_timing_top" ]; then
  CLOCKS_TCL="create_clock -name clk125 -period $PERIOD_NS [get_ports clk125]
create_clock -name clk200 -period $PERIOD_NS [get_ports clk200]
set_clock_groups -asynchronous -group {clk125} -group {clk200}"
else
  CLOCKS_TCL="create_clock -name clk -period $PERIOD_NS [get_ports clk]"
fi
TCL="$(mktemp)"; trap 'rm -f "$TCL"' EXIT
cat > "$TCL" <<TCL
read_liberty $NANGATE_LIB
read_verilog $OUT/cpu_asic_mapped.v
link_design $STA_TOP
create_clock -name virt_clk -period $PERIOD_NS
$CLOCKS_TCL
set_input_delay  -clock virt_clk 0 [all_inputs]
set_output_delay -clock virt_clk 0 [all_outputs]
report_checks -path_delay max -format short
report_wns
report_tns
report_power
exit
TCL

if ! timeout 120 sta -no_init -no_splash "$TCL" > "$OUT/cpu_asic_sta.rpt" 2>&1; then
  echo "WARN: OpenSTA did not complete (timeout/fatal) — ASIC timing absent. See $OUT/cpu_asic_sta.rpt" >&2
  tail -20 "$OUT/cpu_asic_sta.rpt" | sed 's/^/    /' >&2
  exit 0
fi
echo "cpu_sta.sh: OK (period ${PERIOD_NS}ns / ${TARGET_MHZ}MHz). Report: $OUT/cpu_asic_sta.rpt"
