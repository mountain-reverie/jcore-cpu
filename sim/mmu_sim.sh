#!/usr/bin/env bash
# Build + run the MMU / priv-arch functional guards LOCALLY, mirroring the CI
# full-regression "functional-guards" job. Works on the local mcode GHDL.
#
# THE GOTCHA THIS SOLVES: the MMU instructions (LDTLB, PTEH/PTEL/ASIDR overlays,
# LDTLB.R, ...) live in the J4 OVERLAY decoder. A plain `make -C decode generate`
# (base decoder) build silently OMITS every MMU instruction -> LDTLB decodes to
# nothing -> the TLB never installs -> every MMU guard fails or hangs (and
# coverage-style guards can "pass" vacuously). The cosim MUST be built after
# `make -C decode generate-j4`. This script does that, builds, runs, and then
# RESTORES the committed base decoder on exit (committed tables must stay base;
# committing J4-overlay tables is a known Fmax regression -- see
# jcore-base-decoder-j4-overlay-regression).
#
# Usage:
#   sim/mmu_sim.sh                       # build + run the full guard suite
#   sim/mmu_sim.sh mmuicolor             # build + run one guard (auto top/stop-time)
#   sim/mmu_sim.sh mmuxlate cpu_tb 120us # one guard, explicit top + stop-time
#   sim/mmu_sim.sh -n mmuicolor          # reuse the existing build (skip rebuild)
#
# Env: JCORE_SOC (default: sibling ../jcore-soc).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
export JCORE_SOC="${JCORE_SOC:-$ROOT/../jcore-soc}"
[ -d "$JCORE_SOC" ] || { echo "ERROR: JCORE_SOC not found at $JCORE_SOC" >&2; exit 1; }

if [ -z "${MMU_SIM_INNER:-}" ]; then
  # Re-exec the whole script body under synth/with_overlay_decoder.sh, which
  # regenerates the J4 overlay decoder (PRIV_ARCH + MMU instructions), runs
  # the build + guards below, and ALWAYS restores the committed base decoder
  # on exit (committed tables must stay base; committing J4-overlay tables is
  # a known Fmax regression -- see jcore-base-decoder-j4-overlay-regression).
  export MMU_SIM_INNER=1
  exec "$ROOT/synth/with_overlay_decoder.sh" sh4 -- "$0" "$@"
fi

BUILD=1
if [ "${1:-}" = "-n" ]; then BUILD=0; shift; fi

# ALWAYS make the cache .vhd cores present on disk: the mcode cosim
# RE-ANALYSES the VHDL sources at run time. Cheap (perl, a few seconds).
echo "== preprocess dcache/icache .vhm cores -> .vhd =="
for f in cache/dcache_ccl cache/dcache_mcl cache/icache_ccl cache/icache_mcl; do
  LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
done

if [ "$BUILD" = 1 ]; then
  echo "== build MMU-on cosim (cpu_ctb + cpu_tb + cpu_cache_tb) =="
  cd sim
  rm -f work-obj93.cf cpu_tb.vhh cpu_cache_tb.vhh cpu_ctb cpu_cache_tb
  make CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1 \
       cpu_ctb cpu_tb cpu_cache_tb cpu_tb.vhh work-obj93.cf >/dev/null
  grep -q 'MMU_ARCH => true' cpu_tb.vhh \
    || { echo "FAIL: build is not MMU-on (stale cpu_tb.vhh?)" >&2; exit 1; }
  cd ..
fi
cd sim
[ -x cpu_ctb ] || { echo "ERROR: cpu_ctb not built; run without -n first" >&2; exit 1; }

fail=0
run_guard() {  # <name> <sim_top-or-default> [stop-time] [wall-timeout-s]
  local t="$1" top="${2:-}" stoptime="${3:-80us}" wall="${4:-120}"
  if [ ! -f "tests/$t.S" ]; then echo "  SKIP  $t (no tests/$t.S on this branch)"; return; fi
  rm -f tests/$t.img tests/$t.o tests/$t.elf
  make CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1 -C tests $t.img >/dev/null 2>&1
  local out
  out="$(SIM_TOP="$top" timeout "$wall" ./cpu_ctb --stop-time="$stoptime" \
         -i tests/$t.img --ieee-asserts=disable 2>&1 || true)"
  if echo "$out" | grep -qi 'Test Passed'; then
    echo "  PASS  $t${top:+ [$top]}"
  else
    echo "  FAIL  $t${top:+ [$top]}"
    echo "$out" | grep -iE 'result|fail|invalid' | tail -3
    fail=1
  fi
}

if [ $# -ge 1 ]; then
  # Single guard. Default the top + stop-time for the known cache/long guards.
  name="$1"; top="${2:-}"; stop="${3:-}"
  case "$name" in
    mmuicolor)  top="${top:-cpu_cache_tb}"; stop="${stop:-400us}" ;;
    mmudcbit)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagereloc16k) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage4k)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage16k)  top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage64k)  top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage1m)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagemix)  top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagemix2) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagewalk) top="${top:-cpu_cache_tb}"; stop="${stop:-300us}" ;;
    mmureloc)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmurelocif) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmurelocbp) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    m8_dside)   stop="${stop:-200us}" ;;
    m8_ifetch_*) stop="${stop:-12ms}" ;;
  esac
  run_guard "$name" "$top" "${stop:-80us}" "${4:-240}"
else
  echo "== priv-arch + MMU guards (cpu_tb) =="
  for t in exctest trapatest pm3vec pm3guard privmode banktest excguard \
           rteredir mmureg mmuguard mmuxlate mmurte mmustore mmuimiss mmuimiss_illegal \
           mmusr mmufault mmudslot mmuidslot mmuldtlbr mmutsb mmuidx mmustres mmustr2 \
           mmustale mmuasid mmuglobal mmumultihit mmudblflt mmunest_trapa mmunest_slotill mmunest mmuremap mmurun mmuirun mmuainc mmuainc2 mmusmep j4_illegal_trap; do
    run_guard "$t"
  done
  echo "== cache guards (cpu_cache_tb) =="
  run_guard mmuicolor  cpu_cache_tb 400us
  run_guard mmudcbit   cpu_cache_tb 200us
  run_guard mmureloc   cpu_cache_tb 200us
  run_guard mmurelocif cpu_cache_tb 200us
  run_guard mmurelocbp cpu_cache_tb 200us
  run_guard mmupage4k       cpu_cache_tb 200us
  run_guard mmupagereloc16k cpu_cache_tb 200us
  run_guard mmupage16k  cpu_cache_tb 200us
  run_guard mmupage64k  cpu_cache_tb 200us
  run_guard mmupage1m   cpu_cache_tb 200us
  run_guard mmupagemix  cpu_cache_tb 200us
  run_guard mmupagemix2 cpu_cache_tb 200us
  run_guard mmupagewalk cpu_cache_tb 300us
  echo "== M8 fault-coverage sweep =="
  run_guard m8_dside    "" 200us
  run_guard m8_macarith
  run_guard m8_macseq
  run_guard m8_ifetch_0 "" 12ms 240
  run_guard m8_ifetch_1 "" 12ms 240
  run_guard m8_ifetch_2 "" 12ms 240
fi

if [ "$fail" = 0 ]; then echo "==> all guards PASSED"; else echo "==> FAILURES above" >&2; exit 1; fi
