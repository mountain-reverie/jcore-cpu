#!/usr/bin/env bash
# check_bench_fidelity.sh -- prove the TLB-miss benchmark measures the code
# Linux actually runs.
#
# WHY. sim/tests/mmubench.S and mmubenchi.S claim to carry a "byte-faithful"
# copy of linux@jcore's JCORE_TLB_FASTPATH, and every cycle figure in
# sim/bench_tlb_hotpath.sh rests on that claim. Nothing enforced it. The two
# live in different repositories, are edited by different changes, and the
# guards hand-assemble the J4-only instructions as .word -- so a divergence
# would not fail to build, fail a guard, or look wrong in a diff. It would just
# quietly make the benchmark measure something Linux does not run.
#
# This compares the actual OPCODE STREAM of the two, from the linked objects,
# and fails if they differ.
#
# Branch DISPLACEMENTS are masked before comparing. The guards place their slow
# path immediately after the fast path while Linux pads to the 0x20 vector
# budget first, so `bf jcore_tlb_miss_slow` legitimately encodes a different
# offset in each. The displacement does not change the instruction, its class,
# or its cost when not taken -- which is the case the benchmark times. Nothing
# else is allowed to differ.
#
# Also checked: both must sit at exactly vector_base + 0x400, since the fast
# path is inlined AT the vector in Linux and a guard that reached it by a
# branch would be timing a different thing.
#
# Usage:  sim/check_bench_fidelity.sh
# Env:    LINUX_SRC (default ../linux), OBJDUMP, NM
set -uo pipefail
cd "$(dirname "$0")/.."
LINUX_SRC="${LINUX_SRC:-../linux}"
OBJDUMP="${OBJDUMP:-../binutils-gdb/build-sh2/binutils/objdump}"
NM="${NM:-sh2-elf-nm}"
EX_O="$LINUX_SRC/arch/sh/kernel/cpu/jcore/ex.o"

[ -x "$OBJDUMP" ] || OBJDUMP=sh2-elf-objdump
[ -f "$EX_O" ] || { echo "fidelity: $EX_O missing; run sim/linux_sim.sh first" >&2; exit 2; }

# Opcode stream of a symbol range, one 16-bit word per line, with the low byte
# of BF/BT (0x89xx/0x8bxx) masked -- that byte is the displacement.
stream() {   # <file> <start-sym> <end-sym>
  "$OBJDUMP" -d "$1" 2>/dev/null |
    awk -v s="<$2>:" -v e="<$3>:" '
      index($0,s) {on=1; next}
      index($0,e) {on=0}
      on && match($0,/\t([0-9a-f]{2}) ([0-9a-f]{2})[ \t]/,m) { print m[1] m[2] }' |
    sed -E 's/^(89|8b)../\1XX/'
}

fail=0

# --- 1. opcode streams must match ---
lx=$(stream "$EX_O" jcore_tlb_miss jcore_tlb_miss_slow)
[ -n "$lx" ] || { echo "fidelity: could not read the Linux fast path from $EX_O" >&2; exit 2; }

for g in mmubench mmubenchi; do
  elf="sim/tests/$g.elf"
  [ -f "$elf" ] || { echo "fidelity: $elf missing; run sim/linux_sim.sh $g first" >&2; exit 2; }
  gs=$(stream "$elf" _h_common _h_slow)
  if [ "$lx" != "$gs" ]; then
    echo "fidelity: FAIL -- $g's fast path differs from linux@jcore's" >&2
    diff <(echo "$lx") <(echo "$gs") | sed 's/^/    /' >&2
    echo "    (left = linux ex.o jcore_tlb_miss, right = $g _h_common;" >&2
    echo "     BF/BT displacement bytes are masked as XX and are not the cause)" >&2
    fail=1
  else
    echo "fidelity: OK   -- $g matches linux@jcore ($(echo "$lx" | wc -l) instructions)"
  fi

  # --- 2. must be inlined AT the vector, not branched to ---
  vb=$("$NM" "$elf" | awk '$3=="_vbase"{print $1}')
  hc=$("$NM" "$elf" | awk '$3=="_h_common"{print $1}')
  if [ -n "$vb" ] && [ -n "$hc" ]; then
    d=$((0x$hc - 0x$vb))
    if [ "$d" -ne 1024 ]; then
      printf 'fidelity: FAIL -- %s _h_common is vbase+0x%X, must be vbase+0x400\n' "$g" "$d" >&2
      fail=1
    fi
  else
    echo "fidelity: FAIL -- $g has no _vbase/_h_common symbols" >&2
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "fidelity: benchmark measures the code Linux runs."
exit "$fail"
