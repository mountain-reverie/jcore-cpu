#!/usr/bin/env bash
# linux_sim.sh -- SP2: build + run the REAL linux@jcore MMU TLB-miss handler
# (arch/sh/mm/tlb-jcore.c __jcore_tlb_walk(), arch/sh/kernel/cpu/jcore/{ex,
# entry}.S) against the jcore-cpu GHDL cosim, via a bare-metal harness
# (sim/tests/mmulinux.S) that links those real kbuild-produced objects.
#
# Mirrors sim/mmu_sim.sh (MMU-on cosim build/restore-base-decoder dance) plus
# the two gotchas SP2 Task 0 de-risked:
#
#  1. kbuild reaches the WIP J4 gas (binutils-gdb/build-sh2/gas/as-new) via
#     CC="sh2-elf-gcc -B<dir-with-as-symlink>" -- there is no clean AS=
#     override that survives kbuild's .S dependency generation.
#
#  2. Anything that links those linux@jcore objects (both the Task 0 trial
#     link and sim/tests/mmulinux.elf here) MUST use the J4-built ld
#     (binutils-gdb/build-sh2/ld/ld-new), NOT the system sh2-elf-ld: the
#     objects are assembled by the WIP J4 gas, which stamps a newer e_flags
#     (0x1b) the system linker's older bfd doesn't recognise
#     ("relocations in generic ELF (EM: 42)" / "file in wrong format" --
#     toolchain version skew, not a real relocation problem).
#
# Usage:
#   sim/linux_sim.sh [name]      # build linux objects + cosim + run (default: mmulinux)
#   sim/linux_sim.sh -n [name]   # reuse the existing cosim build + linux objects
#
# Env: LINUX_SRC (default: sibling ../linux), JCORE_SOC (default: sibling
# ../jcore-soc), J4GAS/J4LD (default: sibling ../binutils-gdb/build-sh2/...).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
export JCORE_SOC="${JCORE_SOC:-$ROOT/../jcore-soc}"
LINUX_SRC="${LINUX_SRC:-$ROOT/../linux}"
J4GAS="${J4GAS:-$ROOT/../binutils-gdb/build-sh2/gas/as-new}"
J4LD="${J4LD:-$ROOT/../binutils-gdb/build-sh2/ld/ld-new}"
J4BIN="${J4BIN:-/tmp/j4bin}"

[ -d "$JCORE_SOC" ] || { echo "ERROR: JCORE_SOC not found at $JCORE_SOC" >&2; exit 1; }
[ -d "$LINUX_SRC" ] || { echo "ERROR: LINUX_SRC not found at $LINUX_SRC" >&2; exit 1; }
[ -x "$J4GAS" ] || { echo "ERROR: J4 gas not found/executable at $J4GAS" >&2; exit 1; }
[ -x "$J4LD" ] || { echo "ERROR: J4 ld not found/executable at $J4LD" >&2; exit 1; }

BUILD=1
if [ "${1:-}" = "-n" ]; then BUILD=0; shift; fi

name="${1:-mmulinux}"

# Always restore the committed base decoder on exit (generate-j4 overwrites the
# tracked decode/*.vhd + sh2instr.c with the J4 overlay).
restore_base() { make -C "$ROOT/decode" generate >/dev/null 2>&1 || true; }
trap restore_base EXIT

if [ "$BUILD" = 1 ]; then
  echo "== build linux@jcore objects (kbuild via the WIP J4 gas) =="
  mkdir -p "$J4BIN"
  ln -sf "$J4GAS" "$J4BIN/as"
  (
    cd "$LINUX_SRC"
    make ARCH=sh CROSS_COMPILE=sh2-elf- CC="sh2-elf-gcc -B$J4BIN" jcore_defconfig >/dev/null
    make ARCH=sh CROSS_COMPILE=sh2-elf- CC="sh2-elf-gcc -B$J4BIN" \
         arch/sh/mm/tlb-jcore.o arch/sh/kernel/cpu/jcore/ex.o \
         arch/sh/kernel/cpu/jcore/entry.o \
         arch/sh/kernel/cpu/jcore/mmu_enable.o
  ) || { echo "ERROR: linux@jcore object build failed" >&2; exit 1; }

  echo "== generate-j4 (J4 overlay decoder: PRIV_ARCH + MMU instructions) =="
  make -C decode generate-j4 >/dev/null
  echo "== preprocess dcache/icache .vhm cores -> .vhd =="
  for f in cache/dcache_ccl cache/dcache_mcl cache/icache_ccl cache/icache_mcl; do
    LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
  done

  echo "== build MMU-on cosim (cpu_ctb + cpu_tb) =="
  cd sim
  rm -f work-obj93.cf cpu_tb.vhh cpu_ctb
  make CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1 cpu_ctb cpu_tb cpu_tb.vhh work-obj93.cf >/dev/null
  grep -q 'MMU_ARCH => true' cpu_tb.vhh \
    || { echo "FAIL: build is not MMU-on (stale cpu_tb.vhh?)" >&2; exit 1; }
  cd ..
fi

cd sim
[ -x cpu_ctb ] || { echo "ERROR: cpu_ctb not built; run without -n first" >&2; exit 1; }

echo "== build $name.img (real linux@jcore objects, J4-built ld) =="
rm -f "tests/$name.img" "tests/$name.o" "tests/$name.elf"
make -C tests LINUX_SRC="$LINUX_SRC" J4GAS="$J4GAS" J4LD="$J4LD" J4BIN="$J4BIN" \
     CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1 "$name.img"

out="$(timeout 120 ./cpu_ctb --stop-time=200us -i "tests/$name.img" --ieee-asserts=disable 2>&1 || true)"
echo "$out"
if echo "$out" | grep -qi 'Test Passed'; then
  echo "==> PASS $name"
  exit 0
else
  echo "==> FAIL $name" >&2
  exit 1
fi
