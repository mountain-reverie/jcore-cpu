#!/usr/bin/env bash
# Dual-core same-ASID isolation guard for cpu_dualcore_tb (J4/PRIV_ARCH only).
#
# Runs BOTH flavours and asserts BOTH verdicts:
#   mmusmpasid_ok  (per-core TSBs)          must PASS
#   mmusmpasid_bug (both cores share a TSB) must FAIL
#
# The second run is not redundant. A guard that only ever passes proves
# nothing about what it would do if the property broke -- and this suite has
# been fooled by exactly that before. If the bug flavour passes, the guard is
# reported as BROKEN, not as a pass.
#
# Requires a CPU_VARIANT=j4 build of cpu_ctb + cpu_dualcore_tb; with PRIV_ARCH
# off the guard body is preprocessed away and would pass vacuously, so the
# elaborated TB is checked for the MMU generic before anything is run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SIMDIR="$(cd "$HERE/../.." && pwd)"

if [ "$(grep -c 'PRIV_ARCH => true' "$SIMDIR/cpu_dualcore_tb.vhh" 2>/dev/null || echo 0)" -lt 2 ]; then
  echo "FAIL: cpu_dualcore_tb was not built with PRIV_ARCH on both cores" >&2
  echo "      (rebuild with: make CPU_VARIANT=j4 after rm -f cpu_dualcore_tb.vhh)" >&2
  exit 1
fi

if command -v sh2-elf-gcc >/dev/null 2>&1; then
  make -C "$HERE" mmusmpasid_ok.img mmusmpasid_bug.img >/dev/null
fi

run_one() {   # $1 = img basename; echoes "PASS" or "FAIL"
  local raw
  raw="$( (cd "$SIMDIR" && SIM_TOP=cpu_dualcore_tb ./cpu_ctb \
            -i "tests/dualcore/$1.img" --stop-time=400us) 2>&1 || true )"
  printf '%s' "$raw" > "/tmp/$1.log"
  if grep -qi 'Test Passed' <<<"$raw"; then echo PASS; else echo FAIL; fi
}

ok="$(run_one mmusmpasid_ok)"
bug="$(run_one mmusmpasid_bug)"

rc=0
if [ "$ok" != PASS ]; then
  echo "FAIL: mmusmpasid_ok did not pass (per-core TSBs must isolate)" >&2
  grep -ivE "metavalue detected|EN UNKNOWN|EN0 UNKNOWN|EN1 UNKNOWN|Read invalid cmd" \
    /tmp/mmusmpasid_ok.log | tail -40 >&2
  rc=1
fi
if [ "$bug" != FAIL ]; then
  echo "BROKEN GUARD: mmusmpasid_bug passed. Both cores share one TSB in that" >&2
  echo "              flavour, so it MUST fail. The guard is not measuring" >&2
  echo "              cross-core ASID isolation." >&2
  rc=1
fi
[ $rc -eq 0 ] && echo "PASS: mmusmpasid (per-core TSB isolates same-ASID cores; shared TSB fails)"
exit $rc
