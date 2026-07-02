#!/usr/bin/env bash
# Dual-core T-bit delay-slot regression. Builds images, runs both, asserts.
#
# Invariant that survives the RTL fix:
#   fixed loop (smp_ok.img)  MUST see cpu1's sentinel via coherency -> LED 0x5A.
#
# Buggy shape (smp_bug.img):
#   0x7A -> cpu0's compound poll exits early: the T-bit delay-slot hazard is LIVE
#           (bug reproduced, expected pre-fix)     -> exit 2
#   0x5A -> buggy shape also sees cpu1: the RTL fix is present -> exit 0
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SIMDIR="$(cd "$HERE/../.." && pwd)"   # the sim/ dir; cpu_ctb needs it as cwd
make -C "$HERE" >/dev/null
# cpu_ctb must run from sim/ (it resolves relative simulation resources there).
run(){ ( cd "$SIMDIR" && SIM_TOP=cpu_dualcore_tb ./cpu_ctb -i "$1" --stop-time=200us 2>&1 ) \
        | grep -oiE "LED: WRITE 0x[0-9A-Fa-f]+" | tail -1; }
ok=$(run tests/dualcore/smp_ok.img);   echo "fixed loop:  $ok"
bug=$(run tests/dualcore/smp_bug.img); echo "buggy loop:  $bug"
# Fixed loop MUST always see cpu1 (0x5A). This is the invariant that survives the fix.
case "$ok" in *0x5A|*0x5a) : ;; *) echo "FAIL: fixed loop did not see CPU1 ($ok)"; exit 1;; esac
# Buggy loop: 0x5A once the RTL is fixed; 0x7A demonstrates the live bug.
case "$bug" in
  *0x5A|*0x5a) echo "PASS: buggy shape also sees CPU1 -- RTL fix present"; exit 0;;
  *0x7A|*0x7a) echo "REPRO: buggy shape exits early -- bug present (expected pre-fix)"; exit 2;;
  *) echo "UNKNOWN buggy result ($bug)"; exit 1;;
esac
