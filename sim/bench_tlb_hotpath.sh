#!/usr/bin/env bash
# bench_tlb_hotpath.sh -- measure the J4 software-managed TLB-miss hot-path
# latency (cycles per miss) from a cosim VCD PC trace.
#
# WHY. The TLB-refill hot path (linux arch/sh/kernel/cpu/jcore/ex.S
# JCORE_TLB_FASTPATH, mirrored by the mmurun guard's _h_common) runs on EVERY
# TLB miss, so its cycle cost is the MMU's dominant steady-state overhead. This
# benchmark makes that cost observable and regression-checkable: it runs the
# mmurun guard (4 cold-miss walker installs, then 4 steady-state TSB hits) under
# the J4 overlay with a VCD dump, traces the architectural pc[31:0] signal, and
# reports the fast-path dwell for the cold misses and the TSB hits, plus one
# full fault->resume latency.
#
# ------------------------------------------------------------------------------
# MEASURED BASELINE (2026-07-23; cosim clock 100 MHz / 10 ns period).
#
#   Steady-state TSB hit. This bench measures the fast-path dwell (pc in
#   [_h_common, _h_slow)) = ~24 cycles on the mmurun guard, and one full
#   fault->resume = ~38 cycles. The guard carries ~7 cycles of tsb_hits++ counter
#   (2 loads + add + store) that the REAL inlined linux handler does not, and its
#   `bra _h_common` stub adds ~3 (linux inlines the fast path at the vector, no
#   taken branch). Netting those out, the production per-miss latency is:
#       - HW exception entry   ~7 cyc  (FIXED: fault in MA stage -> PC=VBR+0x400;
#                                       HW saves SPC/SSR, loads PTEH/ASIDR/TSBPTR)
#       - fast-path body      ~17 cyc  (STC TSBPTR + 3 TSB loads + 2 cmp/eq +
#                                       2 bf + ldtlb.rn; = 24 dwell - ~7 counter)
#       - return / resume      ~5 cyc  (FIXED: ldtlb.rn install -> redirect to
#                                       SPC -> re-fetch the faulting instruction)
#       => ~29 cycles per TLB-hit miss; ~12 (~40%) is FIXED HW entry+return.
#
#   Cold miss (TSB empty): ~10 cyc fast-path probe (STC + load tag + cmp/eq + bf),
#   then diverts to the C page-table walker (jcore_tlb_miss_slow) -- much larger.
#
#   Instruction-count history (all merged): 12 -> 9 insns on the fast path:
#     cmp/eq.pteh/asid  12->10 (PR#135), ldtlb.rn Rm 10->9 (PR#138),
#     3-TLB-vectors-merged-to-1 I-cache footprint (PR#140).
#
# ------------------------------------------------------------------------------
# FUTURE IMPROVEMENTS in this area (ranked by value/realism):
#
#   1. STATIC NOT-TAKEN BRANCH PREDICTION (top pick). The trace shows each
#      not-taken `bf` costs ~2-3 cycles -- there is no prediction, so fetch
#      stalls until the branch resolves. The two hot-path bf's (both not-taken
#      on a hit) burn ~5 cycles for nothing. A simple predict-fall-through would
#      nearly eliminate that AND benefit all code, not just the MMU path. HW
#      change to the fetch stage; widest benefit for the cost.
#
#   2. DEDICATED FAST TLB-MISS ENTRY/EXIT. The fixed HW exception entry+return
#      (~12 cyc, ~40% of the miss) is the single largest bucket. A trimmed
#      exception path for the TLB vectors (skipping general-exception machinery
#      it does not need) is the biggest lever, but it touches the precise-
#      exception model -- a real HW change.
#
#   3. SINGLE-WORD TSB TAG (VPN+ASID -> one load + one cmp/eq + one bf, ~6 cyc).
#      Blocked as-is: the generation-tagged ASID is 16-bit and the 4K-page VPN is
#      20-bit (36 bits > 32), so packing needs hashing -> tag-aliasing risk
#      (false hit -> wrong translation). Not clean; would need a wider tag word
#      or a collision-safe hash.
#
#   x. DISPLACEMENT-LOAD RESCHEDULE (loads-first, @(disp,r0), 2 tag regs).
#      MEASURED marginal: ~1 cycle/hit, and it speculatively loads all 3 TSB
#      words so it PENALIZES misses. Rejected -- do not re-attempt without a
#      hit-rate argument. (Lesson: the static issue/latency scoreboard
#      overestimated this by ~3x; measure hot-path changes, don't model them.)
#
# ------------------------------------------------------------------------------
# Usage:  sim/bench_tlb_hotpath.sh
# Env:    JCORE_SOC (default: sibling ../jcore-soc), NM (default: sh2-elf-nm).
set -uo pipefail
cd "$(dirname "$0")/.."                       # jcore-cpu root
NM="${NM:-sh2-elf-nm}"
VCD="${TMPDIR:-/tmp}/tlb_hotpath_bench.vcd"
P1=0x80000000                                 # mmurun runs code from the P1 alias

# --- symbol addresses from the guard ELF (fast-path start _h_common, end _h_slow) ---
make CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1 -C sim/tests mmurun.elf >/dev/null 2>&1 \
  || { echo "bench: failed to build sim/tests/mmurun.elf" >&2; exit 1; }
syms=$("$NM" sim/tests/mmurun.elf 2>/dev/null) \
  || { echo "bench: $NM not found (set NM=<sh toolchain nm>)" >&2; exit 1; }
hc=$(awk '$3=="_h_common"{print $1}' <<<"$syms")
hs=$(awk '$3=="_h_slow"{print $1}'   <<<"$syms")
vb=$(awk '$3=="_vbase"{print $1}'    <<<"$syms")
[ -n "$hc" ] && [ -n "$hs" ] && [ -n "$vb" ] || { echo "bench: _h_common/_h_slow/_vbase not in ELF" >&2; exit 1; }
HC=$((P1 + 0x$hc)); HS=$((P1 + 0x$hs)); VB=$((P1 + 0x$vb))
printf 'bench: fast-path range [_h_common 0x%08x .. _h_slow 0x%08x); user code below _vbase 0x%08x\n' "$HC" "$HS" "$VB"

# --- run the guard under the J4 overlay with a VCD dump ---
echo "bench: running mmurun under the J4 overlay (VCD -> $VCD) ..."
MMU_VCD="$VCD" sim/mmu_sim.sh mmurun >/dev/null 2>&1 || true
[ -s "$VCD" ] || { echo "bench: no VCD produced" >&2; exit 1; }

# --- trace pc[31:0]; report cold-probe / TSB-hit dwell + one fault->resume ---
HC=$HC HS=$HS VB=$VB VCD="$VCD" python3 - <<'PY'
import os, re
HC=int(os.environ['HC']); HS=int(os.environ['HS']); VB=int(os.environ['VB']); VCD=os.environ['VCD']
PER=None; pcid=None; ev=[]; cur=0
for l in open(VCD):
    l=l.rstrip('\n')
    if not l: continue
    if pcid is None:
        m=re.match(r'\$var reg 32 (\S+) pc\[31:0\] \$end', l)
        if m: pcid=m.group(1)
    if l[0]=='#': cur=int(l[1:]); continue
    if l[0]=='b':
        p=l.split()
        if len(p)==2 and p[1]==pcid:
            try: ev.append((cur, int(p[0][1:],2)))
            except ValueError: pass
# clock period: first two distinct pc-change timestamps after 0
tstamps=sorted({t for t,_ in ev if t>0})
PER=(tstamps[1]-tstamps[0]) if len(tstamps)>1 else 10_000_000
# handler-region visits (fast path)
inh=False; ent=None; wins=[]
for t,v in ev:
    h = HC <= v < HS
    if h and not inh: inh=True; ent=t
    elif inh and not h: wins.append((ent,t)); inh=False
dw=[(b-a)//PER for a,b in wins]
cold=[d for d in dw[:len(dw)//2]]; hit=[d for d in dw[len(dw)//2:]]
def med(x): return sorted(x)[len(x)//2] if x else 0
print(f"bench: clock period {PER/1e6:.1f} ns, {len(wins)} fast-path visits")
print(f"bench:   cold-miss probe dwell (cyc): {cold}  median {med(cold)}")
print(f"bench:   TSB-hit fast-path dwell (cyc, incl guard tsb_hits++): {hit}  median {med(hit)}")
# one full fault->resume around the first TSB hit (user code = pc below _vbase,
# so the vector stub / handler region is excluded)
if len(wins) > len(dw)//2:
    ent,ext = wins[len(dw)//2]
    pre =[t for t,v in ev if t< ent and v < VB][-1:]   # faulting user instr before entry
    post=[t for t,v in ev if t> ext and v < VB][:1]    # resumed user instr after exit
    if pre and post:
        print(f"bench:   one TSB-hit fault->resume: {(post[0]-pre[0])//PER} cycles"
              f" (guard, incl tsb_hits++ counter + bra stub; real linux is a few cyc less)")
PY
echo "bench: done. See the header of this script for the baseline + future-work notes."
