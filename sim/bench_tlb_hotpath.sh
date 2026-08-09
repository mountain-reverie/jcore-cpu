#!/usr/bin/env bash
# bench_tlb_hotpath.sh -- measure the J4 software-managed TLB-miss hot-path
# latency (cycles per miss) from a cosim VCD PC trace.
#
# WHY. The TLB-refill hot path (linux arch/sh/kernel/cpu/jcore/ex.S
# JCORE_TLB_FASTPATH, mirrored byte-for-byte by the mmubench guard) runs on EVERY
# TLB miss, so its cycle cost is the MMU's dominant steady-state overhead. This
# benchmark makes that cost observable and regression-checkable: it runs the
# mmubench guard (4 cold-miss walker installs, then 4 steady-state TSB hits) under
# the J4 overlay with a VCD dump, traces the architectural pc[31:0] signal, and
# reports the fast-path dwell for the cold misses and the TSB hits, plus one
# full fault->resume latency.
#
# ------------------------------------------------------------------------------
# MEASURED BASELINE (2026-07-23; cosim clock 100 MHz / 10 ns period).
#
#   NOTE (2026-08-08): this bench now runs the `mmubench` guard, whose handler
#   is a byte-faithful copy of linux@jcore's JCORE_TLB_FASTPATH -- no tsb_hits++
#   counter, no `bra` stub, inlined at the vector. Everything below is therefore
#   MEASURED production cost. The previous baseline came from the `mmurun`
#   correctness guard and had to be corrected by a hand-estimated "net out ~7
#   cycles of counter and ~3 of branch"; that estimate is retired. Set
#   BENCH_GUARD=mmurun to reproduce the old, scaffolding-inflated figures.
#
#   MEASURED, 11-insn fast path (cosim 100 MHz / 10 ns period), fault ->
#   back-executing-the-faulting-instruction. Run sim/profile_tlb_hotpath.py for
#   the per-instruction attribution these totals come from.
#
#                              | I-side (IMISS) | D-side (DMISS_R/W)
#     -------------------------+----------------+-------------------
#     HW exception entry       |      5 cyc     |       6 cyc
#     handler body (11 insns)  |     17 cyc     |      17 cyc
#     LDTLB.RN install+redirect|      4 cyc     |       4 cyc
#     -------------------------+----------------+-------------------
#     TSB hit, TOTAL           |     26 cyc     |      27 cyc
#     cold (-> C walker)       |     75 cyc     |      76 cyc
#
#   The handler body is IDENTICAL on both sides. The whole I-vs-D difference is
#   ONE cycle of hardware exception entry -- the D-side fault resolves a cycle
#   later in the pipe. Nothing else differs.
#
#   Where the 17-cycle body goes (D-side; I-side is the same):
#       1  stc tsbptr,r0        1  mov.l @r0+,r1 (tag_lo)
#       1  mov.l @r0+,r1        2  mov.l @r0,r3  (TTE; load-use)
#       2  cmp/eq pteh,r1       1  cmp/eq asidr,r1
#       3  bf (not taken)       2  bf (not taken)
#       2  cmp/miss expevt      1  bf (not taken)
#       1  ldtlb.rn r3
#   => the three NOT-TAKEN bf's cost 6 of the 17 cycles (35%). That is the
#   single largest software-visible bucket and is why static not-taken branch
#   prediction is item 1 below.
#
#   HISTORICAL CORRECTION. This header once reported 21 cyc dwell / 28 cyc total
#   for the D-side and wrote the 21-vs-17 gap up as an unexplained I-vs-D
#   microarchitectural difference. It was neither unexplained nor
#   microarchitectural: mmubench.S had a `.balign 4` before _h_slow, and since
#   LDTLB.RN has no delay slot the PC parks on the following word for the 4
#   redirect cycles -- so the pad word pulled those 4 cycles inside the measured
#   [_h_common,_h_slow) window, and also pushed the window exit out by one,
#   inflating the total by 1. Removing the pad gives 17/27, matching mmubenchi
#   term for term. Lesson: a bracket defined by symbol addresses silently
#   measures whatever the assembler puts between them.
#
#   CMP/MISS EXPEVT A/B (same harness, same workload, only the fault-class
#   test differs -- this is a measurement, not a model):
#       stc expevt + add #-128 + cmp/pl (13 insns):  29 cyc fault->resume
#       cmp/miss expevt                 (11 insns):  27 cyc fault->resume
#       => 2 cycles saved per TLB miss (~7%), and r2 freed on the fast path.
#   (Both legs were measured with the old padded bracket, at 30 and 28; the pad
#   added a constant 1 to each, so the 2-cycle DELTA is unaffected. The absolute
#   figures above are the corrected, unpadded ones.)
#   Note the marginal cost here is ~1 cycle per removed instruction, NOT the
#   ~2 that dividing total dwell by instruction count suggests. Do not size
#   future hot-path changes with that ratio -- A/B them here instead.
#
#   Rough attribution of the 28 cycles:
#       - HW exception entry   ~7 cyc  (FIXED: fault in MA stage -> PC=VBR+0x400;
#                                       HW saves SPC/SSR, loads PTEH/ASIDR/TSBPTR)
#       - fast-path body       21 cyc dwell, overlapping entry/exit
#       - return / resume      ~5 cyc  (FIXED: ldtlb.rn install -> redirect to
#                                       SPC -> re-fetch the faulting instruction)
#     ~12 cyc (~40%) is FIXED hardware entry+return that no software change reaches.
#
#   Cold miss (TSB empty): ~10 cyc fast-path probe (STC + load tag + cmp/eq + bf),
#   then diverts to the C page-table walker (jcore_tlb_miss_slow) -- much larger.
#
#   Instruction-count history on the fast path:
#     12 -> 10  cmp/eq.pteh/asid fused tag compares (PR#135)
#     10 ->  9  ldtlb.rn Rm (PR#138)
#      9 -> 13  protection-fault livelock fix: stc expevt + add + cmp/pl + bt
#               had to run on every TSB hit (single-vector consequence)
#     13 -> 11  cmp/miss expevt folds those three into one and frees r2
#   Also: 3 TLB vectors merged to 1, shrinking the I-cache footprint (PR#140).
#
# ------------------------------------------------------------------------------
# FUTURE IMPROVEMENTS in this area (ranked by value/realism):
#
#   1. STATIC NOT-TAKEN BRANCH PREDICTION (top pick). The trace shows each
#      not-taken `bf` costs ~2-3 cycles -- there is no prediction, so fetch
#      stalls until the branch resolves. There are now THREE not-taken bf's on
#      a hit (two tag compares + the cmp/miss fault-class test), so this is
#      worth ~7 cycles. A simple predict-fall-through would
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
# mmubench mirrors the real linux handler exactly (no counter, no bra stub).
# BENCH_GUARD=mmurun reproduces the older, scaffolding-inflated numbers.
GUARD="${BENCH_GUARD:-mmubench}"
P1=0x80000000                                 # the guard runs code from the P1 alias

# --- symbol addresses from the guard ELF (fast-path start _h_common, end _h_slow) ---
make CONFIG_PRIV_ARCH=1 -C sim/tests "$GUARD".elf >/dev/null 2>&1 \
  || { echo "bench: failed to build sim/tests/$GUARD.elf" >&2; exit 1; }
syms=$("$NM" sim/tests/"$GUARD".elf 2>/dev/null) \
  || { echo "bench: $NM not found (set NM=<sh toolchain nm>)" >&2; exit 1; }
hc=$(awk '$3=="_h_common"{print $1}' <<<"$syms")
hs=$(awk '$3=="_h_slow"{print $1}'   <<<"$syms")
vb=$(awk '$3=="_vbase"{print $1}'    <<<"$syms")
[ -n "$hc" ] && [ -n "$hs" ] && [ -n "$vb" ] || { echo "bench: _h_common/_h_slow/_vbase not in ELF" >&2; exit 1; }
HC=$((P1 + 0x$hc)); HS=$((P1 + 0x$hs)); VB=$((P1 + 0x$vb))
printf 'bench: fast-path range [_h_common 0x%08x .. _h_slow 0x%08x); user code below _vbase 0x%08x\n' "$HC" "$HS" "$VB"

# --- run the guard under the J4 overlay with a VCD dump ---
echo "bench: running $GUARD under the J4 overlay (VCD -> $VCD) ..."
MMU_VCD="$VCD" sim/mmu_sim.sh "$GUARD" >/dev/null 2>&1 || true
[ -s "$VCD" ] || { echo "bench: no VCD produced" >&2; exit 1; }

# --- trace pc[31:0]; report cold-probe / TSB-hit dwell + one fault->resume ---
HC=$HC HS=$HS VB=$VB VCD="$VCD" GUARD="$GUARD" python3 - <<'PY'
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
print(f"bench:   TSB-hit fast-path dwell (cyc): {hit}  median {med(hit)}")
# one full fault->resume around the first TSB hit (user code = pc below _vbase,
# so the vector stub / handler region is excluded)
def faultresume(windows):
    out = []
    for ent, ext in windows:
        pre  = [t for t, v in ev if t < ent and v < VB][-1:]   # faulting user instr before entry
        post = [t for t, v in ev if t > ext and v < VB][:1]    # resumed user instr after exit
        if pre and post:
            out.append((post[0] - pre[0]) // PER)
    return out

# NOTE on the cold numbers: the walker (___jcore_tlb_walk) links ABOVE _vbase,
# so it is not counted as "user" code and a cold window's resume is genuinely
# the re-executed faulting instruction, not the walker's first insn. If the
# link order ever changes so the walker falls below _vbase, the cold
# fault->resume figures silently collapse to near the probe dwell -- sanity
# check them against the probe dwell before trusting a sudden improvement.
coldff = faultresume(wins[:len(dw)//2])
hitff  = faultresume(wins[len(dw)//2:])
if coldff:
    print(f"bench:   COLD (TSB miss -> C walker) fault->resume (cyc): {coldff}  median {med(coldff)}")
if hitff:
    print(f"bench:   TSB-HIT fault->resume (cyc, one per hit): {hitff}  median {med(hitff)}")
PY
echo "bench: done. See the header of this script for the baseline + future-work notes."
