#!/usr/bin/env bash
# Build + run the PAGE_FAULT_ARCH functional guards LOCALLY on the mcode GHDL.
#
# THE GOTCHA (same as mmu_sim.sh): the Page Fault I/D microcode lives in the
# PAGE_FAULT overlay decoder. A plain `make -C decode generate` (base) leaves
# PAGE_FAULT_I/D as x"00" placeholders -> dispatching one jumps to ROM addr 0 ->
# garbage. The cosim MUST be built after `make -C decode generate-pagefault`.
# This script does that, builds CONFIG_PAGE_FAULT_ARCH=1, runs the guards, and
# RESTORES the committed base decoder on exit (committed tables stay base; the
# overlay grows the system-op ROM to 9-bit and must not be committed).
#
# Usage:
#   sim/pagefault_sim.sh                 # build + run all page-fault guards
#   sim/pagefault_sim.sh pagefault_d     # build + run one guard
#   sim/pagefault_sim.sh -n pagefault_i  # reuse the existing build (skip rebuild)
#
# Env: JCORE_SOC (default: sibling ../jcore-soc).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
export JCORE_SOC="${JCORE_SOC:-$ROOT/../jcore-soc}"
[ -d "$JCORE_SOC" ] || { echo "ERROR: JCORE_SOC not found at $JCORE_SOC" >&2; exit 1; }

BUILD=1
if [ "${1:-}" = "-n" ]; then BUILD=0; shift; fi

# Always restore the committed base decoder on exit (generate-pagefault overwrites
# the tracked decode/*.vhd with the overlay tables).
restore_base() { make -C "$ROOT/decode" generate >/dev/null 2>&1 || true; }
trap restore_base EXIT

echo "== generate-pagefault (base + Page Fault I/D overlay) =="
make -C decode generate-pagefault >/dev/null

if [ "$BUILD" = 1 ]; then
  echo "== build PAGE_FAULT-on cosim (cpu_ctb + cpu_tb) =="
  cd sim
  rm -f work-obj93.cf cpu_tb.vhh cpu_ctb
  make CONFIG_PAGE_FAULT_ARCH=1 cpu_ctb cpu_tb cpu_tb.vhh work-obj93.cf >/dev/null
  grep -q 'PAGE_FAULT_ARCH => true' cpu_tb.vhh \
    || { echo "FAIL: build is not PAGE_FAULT-on (stale cpu_tb.vhh?)" >&2; exit 1; }
  cd ..
fi
cd sim
[ -x cpu_ctb ] || { echo "ERROR: cpu_ctb not built; run without -n first" >&2; exit 1; }

fail=0
run_guard() {  # <name> [stop-time] [wall-timeout-s]
  local t="$1" stoptime="${2:-120us}" wall="${3:-120}"
  if [ ! -f "tests/$t.S" ]; then echo "  SKIP  $t (no tests/$t.S)"; return; fi
  rm -f tests/$t.img tests/$t.o tests/$t.elf
  make CONFIG_PAGE_FAULT_ARCH=1 -C tests $t.img >/dev/null 2>&1
  local out
  out="$(SIM_TOP=cpu_tb timeout "$wall" ./cpu_ctb --stop-time="$stoptime" \
         -i tests/$t.img --ieee-asserts=disable 2>&1 || true)"
  if echo "$out" | grep -qi 'Test Passed'; then
    echo "  PASS  $t"
  else
    echo "  FAIL  $t"
    echo "$out" | grep -iE 'result|fail|invalid' | tail -3
    fail=1
  fi
}

if [ $# -ge 1 ]; then
  run_guard "$1" "${2:-120us}" "${3:-120}"
else
  echo "== page-fault guards (cpu_tb) =="
  run_guard pagefault_i
  run_guard pagefault_d
fi

if [ "$fail" = 0 ]; then echo "==> all guards PASSED"; else echo "==> FAILURES above" >&2; exit 1; fi
