#!/usr/bin/env bash
# Dual-core cache-coherency + T-bit delay-slot guard for cpu_dualcore_tb.
#
# What this exercises: two J2 cores with snoop-cross-wired write-back D-caches
# sharing one memory. cpu1 computes a value and stores a sentinel; cpu0 has that
# sentinel line cached and polls it. The FIXED image polls with a hazard-free
# loop; the BUGGY image polls with the exact gcc -Os codegen that folds a
# T-setting instruction (tst) into a bt.s delay slot feeding the next branch.
#
# Invariant (must always hold): cpu0 observes cpu1's write via cache coherency
#   -> LED 0x5A. A break here means snoop coherency regressed.
#
# T-bit delay-slot hazard status: this hazard was observed only on real ULX3S
# FPGA hardware and does NOT reproduce in functional GHDL simulation (verified
# across single-core, this dual-core coherent tb, and the real jcore-soc SDRAM
# dual-core sim). So in simulation BOTH loops are expected to report 0x5A.
#   0x5A on the buggy shape -> healthy (expected)            -> exit 0
#   0x7A on the buggy shape -> cpu0 exited early: a functional-sim reproduction
#           of the hazard would be a genuine surprise worth investigating -> exit 2
#
# Images (smp_ok.img / smp_bug.img) are committed fixtures so this runs in CI
# without an SH-2 cross-compiler; they are rebuilt here only when sh2-elf-gcc is
# available (to stay in sync with smp_repro.s during local development).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SIMDIR="$(cd "$HERE/../.." && pwd)"   # the sim/ dir; cpu_ctb needs it as cwd

if command -v sh2-elf-gcc >/dev/null 2>&1; then
  make -C "$HERE" >/dev/null
fi
for img in smp_ok.img smp_bug.img; do
  if [ ! -f "$HERE/$img" ]; then
    echo "FAIL: missing $img and no sh2-elf-gcc to build it" >&2; exit 1
  fi
done

# cpu_ctb must run from sim/ (it resolves relative simulation resources there).
run(){ ( cd "$SIMDIR" && SIM_TOP=cpu_dualcore_tb ./cpu_ctb -i "$1" --stop-time=200us 2>&1 ) \
        | grep -oiE "LED: WRITE 0x[0-9A-Fa-f]+" | tail -1; }
ok=$(run tests/dualcore/smp_ok.img);   echo "fixed loop:  $ok"
bug=$(run tests/dualcore/smp_bug.img); echo "buggy loop:  $bug"

# Coherency invariant: the fixed loop MUST see cpu1 (0x5A).
case "$ok" in *0x5A|*0x5a) : ;; *) echo "FAIL: fixed loop did not see CPU1 ($ok) -- snoop coherency regressed"; exit 1;; esac
# Buggy shape: 0x5A is the healthy/expected sim result; 0x7A would be an
# unexpected functional-sim reproduction of the hardware-only hazard.
case "$bug" in
  *0x5A|*0x5a) echo "PASS: both loops see CPU1 via coherency (hazard does not repro in sim -- expected)"; exit 0;;
  *0x7A|*0x7a) echo "SURPRISE: buggy shape exited early -- functional-sim repro of the T-bit hazard; investigate"; exit 2;;
  *) echo "UNKNOWN buggy result ($bug)"; exit 1;;
esac
