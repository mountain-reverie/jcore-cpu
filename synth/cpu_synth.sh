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
# Usage: synth/cpu_synth.sh <asic|ecp5|timing|ice40>
#   asic   -> build/cpu_asic.v    (generic netlist)
#   ecp5   -> build/cpu_ecp5.json  (synth_ecp5/abc9 netlist of the bare cpu)
#   timing -> build/cpu_timing.json (synth_ecp5 of the cpu_timing_top harness;
#             the netlist the ECP5 Fmax regression gate is measured on)
#   ice40  -> build/cpu_ice40.json (synth_ice40 of the cpu_timing_top harness;
#             the netlist nextpnr-ice40 P&Rs on the up5k for the fit gauge)
#
# Variant selection (env var SYNTH_VARIANT, default j2):
#   j2 -> elaborate cpu_synth_direct (the default; J2 hardware multiplier).
#   j1 -> elaborate cpu_synth_j1 (sequential mult(seq) + shifter(seq), no hw
#         multiplier/barrel); adds core/mult_seq.vhd + core/shifter_seq.vhd +
#         synth/cpu_synth_j1_config.vhd to the file list.
#   j4 -> elaborate cpu_synth_j4 (== J2 today);
#         adds synth/cpu_synth_j4_config.vhd to the file list.
# When SYNTH_VARIANT is unset or j2 the synth commands are byte-identical to the
# original J2-only script (so the existing J2 dashboard series is unbroken).
set -euo pipefail

BACKEND="${1:?usage: cpu_synth.sh <asic|ecp5|timing|ice40>}"
SYNTH_VARIANT="${SYNTH_VARIANT:-j2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# jcore-soc checkout (provides the cache's lib/ + components/ deps for j2c/j4c).
# CI checks it out to $ROOT/jcore-soc; override JCORE_SOC for local runs.
JCORE_SOC="${JCORE_SOC:-$ROOT/jcore-soc}"

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
  core/shifter.vhd
  core/datapath.vhd
  core/register_file.vhd
  core/register_file_flops.vhd
  core/register_file_two_bank.vhd
  core/register_file_ebr.vhd
  decode/decode.vhd
  decode/decode_body.vhd
  decode/decode_table.vhd
  decode/decode_table_direct.vhd
  decode/decode_table_direct_config.vhd
  decode/decode_core.vhd
  synth/cpu_synth_config.vhd
)

# Map variant -> (cpu top config, timing-harness config, synth -top cell). The
# cpu_timing_* harness is bare-cpu only; j2c/j4c use cpu_cache_timing_*. CACHE=1
# marks the cpu+cache variants.
CPUTOP="cpu"; TIMINGCELL="cpu_timing_top"; CACHE=0
# AREA_TOP/AREA_CPUTOP: the elaboration top and synth -top cell for the
# asic/ecp5 area backends.  Defaults to TOP/CPUTOP; overridden for j4/j4c
# where cpu_synth_j4_priv (PRIV_ARCH=true) replaces cpu_synth_j4 (=false).
AREA_TOP=""; AREA_CPUTOP=""
# The cache adapters instantiate icache/dcache as VHDL *components* (bound via
# cache_pack), so ghdl needs --syn-binding to bind them to their entities and
# synthesize their bodies -- without it ghdl emits empty blackbox modules that
# nextpnr rejects (and generic asic synth silently drops, hiding the cache). The
# bare cpu has no unbound components, so this flag is added ONLY for j2c/j4c to
# keep the bare-variant synth byte-identical to the established dashboard series.
SYN_BINDING=""
case "$SYNTH_VARIANT" in
  j2)
    TOP="cpu_synth_direct"; TIMING_TOP="cpu_timing_j2"
    FILES+=(synth/cpu_timing_top.vhd synth/cpu_timing_config.vhd)
    ;;
  j1)
    # J1 binds the ROM decoder (cpu_synth_j1_config.vhd -> cpu_decode_rom), so the
    # rom microcode table + its config must be in the file list (like the j4-rom
    # case below). The direct table files are already in the base FILES list; both
    # decoder configs may coexist in the library since only cpu_decode_rom is bound.
    TOP="cpu_synth_j1"; TIMING_TOP="cpu_timing_j1"
    FILES+=(core/mult_seq.vhd core/shifter_seq.vhd \
            decode/decode_table_rom.vhd decode/decode_table_rom_config.vhd \
            synth/cpu_synth_j1_config.vhd \
            synth/cpu_timing_top.vhd synth/cpu_timing_config.vhd)
    ;;
  j4)
    if [ "${DECODER:-direct}" = "rom" ]; then
      TOP="cpu_synth_j4_rom"; TIMING_TOP="cpu_timing_j4"
      FILES+=(synth/cpu_synth_j4_rom_config.vhd decode/decode_table_rom.vhd decode/decode_table_rom_config.vhd)
    else
      TOP="cpu_synth_j4"; TIMING_TOP="cpu_timing_j4"
      FILES+=(synth/cpu_synth_j4_config.vhd)
    fi
    # M0: for the asic/ecp5 area backends, elaborate via cpu_synth_j4_priv
    # (a pass-through top that binds cpu with PRIV_ARCH=true via configuration
    # generic map). The yosys ghdl plugin does not support the -g elaboration
    # flag, so the generic must be set in VHDL. cpu_synth_j4_priv is defined in
    # cpu_synth_j4_config.vhd. The timing/ice40 backends use cpu_timing_j4
    # (which already has PRIV_ARCH=>true via its own configuration binding) and
    # are unaffected.
    AREA_TOP="cpu_synth_j4_priv"; AREA_CPUTOP="cpu_j4_priv_top"
    FILES+=(synth/cpu_timing_top.vhd synth/cpu_timing_config.vhd)
    ;;
  j2c|j4c)
    CACHE=1; CPUTOP="cpu_cache_timing_top"; TIMINGCELL="cpu_cache_timing_top"
    SYN_BINDING="--syn-binding"
    if [ "$SYNTH_VARIANT" = j4c ]; then
      TOP="cpu_cache_timing_j4"
      # M0: for j4c asic/ecp5, use the PRIV_ARCH=true variant of the cache
      # timing top (cpu_cache_timing_j4_priv in cpu_cache_timing_config.vhd).
      AREA_TOP="cpu_cache_timing_j4_priv"
    else
      TOP="cpu_cache_timing_j2"
    fi
    TIMING_TOP="$TOP"
    # Cache CDC form = the cache_clkmode package constant (no generic, so ghdl
    # bakes it and yosys sees no parametric cache module). We use the SINGLE-CLOCK
    # (negedge-FF) form (_sc) on BOTH backends. The dual-clock (_dc) form uses a
    # level-sensitive transparent latch ("if clk='0' then q<=d") for the half-
    # cycle CDC element; ghdl synthesis rejects it ("latch infered ... use
    # --latches") and forcing --latches pushes unmapped $dlatch cells into the
    # OpenSTA flow. That is the very reason jcore-soc rewrites these latches to
    # negedge FFs for FPGA synthesis -- the latch form is a sim/ASIC-backend
    # artifact, not a ghdl-yosys synth target. So the asic-vs-fpga metric compares
    # the same synthesizable cpu+cache on Nangate45 vs ECP5. (_dc is retained for
    # jcore-soc's dual-clock simulation / native-ASIC flow.)
    CLKMODE=cache/cache_clkmode_sc.vhd
    # cache cores are vhm; preprocess like the cpu cores (uses jcore-soc's v2p).
    for f in cache/dcache_ccl cache/dcache_mcl cache/icache_ccl cache/icache_mcl; do
      LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
    done
    # cache dependency chain (proven order). jcore-soc provides lib/ + components/
    # + targets/data_bus_pkg; jcore-cpu provides cache/ + the harness. cpu+cache
    # also needs cpu_synth_j4 (the config file references it).
    FILES+=(
      "$CLKMODE"
      synth/cpu_cache_config.vhd
      "$JCORE_SOC/targets/data_bus_pkg.vhd"
      "$JCORE_SOC/components/ddr2/ddrc_cnt_pkg.vhd"
      cache/cache_pkg.vhd
      "$JCORE_SOC/lib/reg_file_struct/bist_pkg.vhd"
      "$JCORE_SOC/components/dma/dma_pkg.vhd"
      "$JCORE_SOC/lib/memory_tech_lib/memory_pkg.vhd"
      "$JCORE_SOC/lib/memory_tech_lib/ram_1rw.vhd"
      "$JCORE_SOC/lib/memory_tech_lib/ram_2rw.vhd"
      "$JCORE_SOC/lib/memory_tech_lib/tech/inferred/ram_1rw_infer.vhd"
      "$JCORE_SOC/lib/memory_tech_lib/tech/inferred/ram_2rw_infer.vhd"
      cache/dcache_adapter.vhd
      cache/icache_adapter.vhd
      cache/dcache_ram.vhd
      cache/icache_ram.vhd
      cache/dcache_ccl.vhd
      cache/dcache_mcl.vhd
      cache/icache_ccl.vhd
      cache/icache_mcl.vhd
      cache/dcache.vhd
      cache/icache.vhd
      cache/cache_config_fpga.vhd
      synth/cpu_cache_timing_top.vhd
      synth/cpu_synth_j4_config.vhd
      synth/cpu_cache_timing_config.vhd
    )
    ;;
  *) echo "ERROR: unknown SYNTH_VARIANT '$SYNTH_VARIANT' (want j1|j2|j4|j2c|j4c)" >&2; exit 1 ;;
esac

# Resolve asic/ecp5 area elaboration top: use AREA_TOP if set (j4/j4c with
# PRIV_ARCH=true wrapper), fall back to TOP for all other variants.
[ -z "$AREA_TOP" ] && AREA_TOP="$TOP"
[ -z "$AREA_CPUTOP" ] && AREA_CPUTOP="$CPUTOP"

GHDL_BASE="ghdl --std=93 -fexplicit --ieee=synopsys $SYN_BINDING --workdir=$WORK ${FILES[*]}"

case "$BACKEND" in
  asic)
    # Strip verification cells emitted from VHDL `assert` statements so the
    # written netlist re-reads cleanly downstream: chformal -remove drops
    # $assert/$assume/$cover; `delete t:$check t:$print` drops the $check/$print
    # cells (ghdl 6 + yosys 0.44) whose verilog backend otherwise emits empty
    # `initial` blocks that OpenSTA's reader rejects.
    yosys -m ghdl -p "$GHDL_BASE -e $AREA_TOP; synth -top $AREA_CPUTOP; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_verilog $OUT/cpu_asic.v"
    ;;
  ecp5)
    # abc9 (synth_ecp5 default) gives timing-driven LUT mapping. It works now
    # that the issue/slot false combinational loop is broken in core/datapath.vhm
    # (see synth/README.md). Strip verification cells (as above) so nextpnr-ecp5
    # can consume the JSON.
    #
    # Bare-core fit gate exposes every cpu port as a pad, and the LFE5U-85F
    # CABGA381 has only 365 IO BELs (the core already uses ~348). The SH-4
    # priv_o export (EXPEVT/INTEVT/TRA, 34 bits) is observability with no
    # in-core consumer, so drop its ports before P&R to keep the fit gate
    # logic-bound, not IO-bound. For j4/j4c, AREA_CPUTOP=cpu_j4_priv_top,
    # so the priv_o path uses the wrapper top name. j2c/j4c wrap cpu in
    # cpu_cache_timing_top (priv_o left open), so no drop is needed there.
    PRIV_DROP=""
    [ "$CACHE" = 0 ] && PRIV_DROP="delete ${AREA_CPUTOP}/priv_o[expevt] ${AREA_CPUTOP}/priv_o[intevt] ${AREA_CPUTOP}/priv_o[tra]; opt_clean;"
    yosys -m ghdl -p "$GHDL_BASE -e $AREA_TOP; synth_ecp5 -top $AREA_CPUTOP; check -assert; chformal -remove; delete t:\$check t:\$print; $PRIV_DROP stat; write_json $OUT/cpu_ecp5.json"
    ;;
  timing)
    # Representative Fmax benchmark: the cpu_timing_top harness registers the
    # core's ~348 boundary signals down to 4 IO (synth/cpu_timing_top.vhd), so
    # nextpnr places the core compactly and reports a true register->core->
    # register Fmax instead of the bare-core IO-scatter artifact. This netlist
    # is what the ECP5 timing regression gate measures. Elaborates the
    # per-variant harness config so J1/J4 measure their own core, not J2.
    yosys -m ghdl -p "$GHDL_BASE -e $TIMING_TOP; synth_ecp5 -top $TIMINGCELL; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_timing.json"
    ;;
  ice40)
    # iCE40 up5k fit gauge. The bare cpu cannot P&R on up5k (too many
    # unconstrained boundary IO), so synthesize the cpu_timing_top harness — the
    # same one the ECP5 representative-Fmax path uses (boundary registered to 4
    # IO). nextpnr-ice40 (run by the caller) then places & routes it on the up5k
    # and reports ICESTORM_LC/RAM/DSP utilisation + Fmax. Elaborates the
    # per-variant harness config so J1 measures its own core.
    # J1 gets two extra Yosys passes (from jcore-j1-ghdl): opt+opt_mem before
    # synth_ice40 to eliminate dead logic, and -abc2 for a second ABC pass.
    # (-retime is incompatible with synth_ice40's default -abc9.) J2/J4 unchanged.
    if [ "$SYNTH_VARIANT" = j1 ]; then
      yosys -m ghdl -p "$GHDL_BASE -e $TIMING_TOP; opt; opt_mem; synth_ice40 -dsp -abc2 -top $TIMINGCELL; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_ice40.json"
    else
      yosys -m ghdl -p "$GHDL_BASE -e $TIMING_TOP; synth_ice40 -dsp -top $TIMINGCELL; check -assert; chformal -remove; delete t:\$check t:\$print; stat; write_json $OUT/cpu_ice40.json"
    fi
    ;;
  *) echo "ERROR: unknown backend '$BACKEND' (want asic|ecp5|timing|ice40)" >&2; exit 1 ;;
esac
echo "cpu_synth.sh: $BACKEND OK"
