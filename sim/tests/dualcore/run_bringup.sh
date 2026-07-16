#!/usr/bin/env bash
# SMP-bringup guard for cpu_dualcore_tb: proves spin-table secondary release
# (cpu0-supplied entry PC via 0x8000 mailbox + 0xabcd0640 enable) and IPI
# delivery through the real work.icache_modereg entity's int0/int1 pulse
# (bit 28 @ 0xABCD00C4), including its auto-clear (single-shot ISR entry).
#
# See sim/tests/dualcore/smp_bringup.s for the full stimulus and proof
# structure; result is reported via the standard TEST_RESULT_ADDRESS /
# "Test Passed" convention (sim/tests/sim_instr.h CMD_ENABLE_TEST_RESULT).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SIMDIR="$(cd "$HERE/../.." && pwd)"   # sim/ dir; cpu_ctb needs it as cwd

if command -v sh2-elf-gcc >/dev/null 2>&1; then
  make -C "$HERE" smp_bringup.img >/dev/null
fi
[ -f "$HERE/smp_bringup.img" ] || { echo "FAIL: smp_bringup.img missing and sh2-elf-gcc not available" >&2; exit 1; }

RAW="$(mktemp)"; trap 'rm -f "$RAW"' EXIT

(cd "$SIMDIR" && SIM_TOP=cpu_dualcore_tb ./cpu_ctb -i "tests/dualcore/smp_bringup.img" --stop-time=300us) >"$RAW" 2>&1 || true

if grep -qi 'Test Passed' "$RAW"; then
  echo "PASS: smp_bringup (spin-table release + IPI bit-28 auto-clear via icache_modereg)"
  exit 0
else
  echo "FAIL: smp_bringup" >&2
  grep -ivE "metavalue detected|EN UNKNOWN|EN0 UNKNOWN|EN1 UNKNOWN|Read invalid cmd" "$RAW" | tail -40 >&2
  exit 1
fi
