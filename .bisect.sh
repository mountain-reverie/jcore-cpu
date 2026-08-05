#!/bin/bash
# Bisect: does the illegal-instruction logic cause j2ac's mult/LUT4 652 -> 909?
# Runs the ecp5-block synth twice on the SAME branch, differing only in whether
# check_illegal_instruction contains logic (ILLEGAL=full) or is constant-0
# (ILLEGAL=none). mult RTL is identical in both.
set -uo pipefail
export JCORE_SOC=/work/jcore-soc
cd /work/jcore-cpu

report() {  # $1 = label
  local m d c
  m=$(awk '/^=== mult_Bstru/{f=1;next} /^=== /{f=0} f&&/LUT4 /{print $2; exit}' build/ecp5_block_stat.txt 2>/dev/null)
  d=$(awk '/^=== datapath_Bstru/{f=1;next} /^=== /{f=0} f&&/LUT4 /{print $2; exit}' build/ecp5_block_stat.txt 2>/dev/null)
  c=$(awk '/^=== cpu_/{f=1;next} /^=== /{f=0} f&&/LUT4 /{print $2; exit}' build/ecp5_block_stat.txt 2>/dev/null)
  echo "RESULT[$1] mult/LUT4=$m datapath/LUT4=$d cpu_top/LUT4=$c"
}

echo "########## PASS 1: ILLEGAL=full (as committed)"
make -C decode generate >/dev/null 2>&1
SYNTH_VARIANT=j2ac synth/cpu_synth.sh ecp5-block > /tmp/p1.log 2>&1
echo "  exit=$? (tail below)"; tail -3 /tmp/p1.log
report full

echo "########## PASS 2: ILLEGAL=none (same branch, detection compiled out)"
make -C decode generate ILLEGAL=none >/dev/null 2>&1
grep -c "return '0';" decode/decode_body.vhd >/dev/null
SYNTH_VARIANT=j2ac synth/cpu_synth.sh ecp5-block > /tmp/p2.log 2>&1
echo "  exit=$? (tail below)"; tail -3 /tmp/p2.log
report none

echo "########## restoring tree"
make -C decode generate >/dev/null 2>&1
echo "done"
