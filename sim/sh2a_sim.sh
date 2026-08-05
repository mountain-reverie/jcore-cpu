#!/usr/bin/env bash
# Build + run the SH-2A ("J2A") in-pipeline sim, mirroring sim/mmu_sim.sh.
#
# THE GOTCHA THIS SOLVES: the SH-2A instructions (e.g. the two-word
# MOV.L @(disp12,Rm),Rn seed) live in the J2A OVERLAY decoder
# (decode/gen-go/spec/sh2a/). A plain base-decoder build silently OMITS
# them -> the two-word opcode decodes as something else entirely. The cosim
# MUST be built with CPU_VARIANT=j2a, which sim/Makefile (via
# ../Makefile.inc + variants.toml) resolves to the J2A-overlay decoder
# generated OUT-OF-TREE under sim/gen/j2a-w<width>/decode -- it never
# touches the committed in-tree decode/*.vhd (which must stay base; never
# commit the J2A overlay tables).
#
# CONFIG_SH2A_ARCH is now DERIVED from CPU_VARIANT (sim/Makefile derives it
# from CPU_GENERICS' SH2A_ARCH=true, mirroring CONFIG_PRIV_ARCH's own
# derivation; sim/tests/Makefile derives it from CPU_VARIANT=j2a directly,
# mirroring its own CONFIG_PRIV_ARCH derivation), so CPU_VARIANT=j2a alone
# is now sufficient -- no raw CONFIG_SH2A_ARCH=1 flag needed below.
#
# Usage:
#   sim/sh2a_sim.sh                 # build + run sh2a_movl12
#   sim/sh2a_sim.sh sh2a_movl12 40us
#   sim/sh2a_sim.sh -n sh2a_movl12   # reuse existing build (skip rebuild)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
TOOLS_DIR="${TOOLS_DIR:-/home/cedric/work/jcore/jcore-soc/tools}"
[ -d "$TOOLS_DIR" ] || { echo "ERROR: TOOLS_DIR not found at $TOOLS_DIR" >&2; exit 1; }

BUILD=1
if [ "${1:-}" = "-n" ]; then BUILD=0; shift; fi

TEST="${1:-sh2a_movl12}"
STOP="${2:-40us}"

if [ "$BUILD" = 1 ]; then
  echo "== build SH2A-on cosim (cpu_ctb + cpu_tb) =="
  cd sim
  rm -f work-obj93.cf cpu_tb.vhh cpu_ctb
  make CPU_VARIANT=j2a cpu_ctb cpu_tb cpu_tb.vhh work-obj93.cf \
       TOOLS_DIR="$TOOLS_DIR"
  grep -q 'SH2A_ARCH => true' cpu_tb.vhh \
    || { echo "FAIL: build is not SH2A-on (stale cpu_tb.vhh?)" >&2; exit 1; }
  cd ..
fi

cd sim
[ -x cpu_ctb ] || { echo "ERROR: cpu_ctb not built; run without -n first" >&2; exit 1; }

echo "== build test image: tests/$TEST.img =="
rm -f tests/$TEST.img tests/$TEST.o tests/$TEST.elf
make CPU_VARIANT=j2a -C tests $TEST.img

echo "== run: cpu_ctb --stop-time=$STOP -i tests/$TEST.img =="
./cpu_ctb --stop-time="$STOP" -i tests/$TEST.img --ieee-asserts=disable
rc=$?

exit $rc
