#!/usr/bin/env bash
# bench_tlb_hotpath.sh -- measure the J4 software-managed TLB-miss hot-path
# latency (cycles per miss) from a cosim VCD PC trace.
#
# WHY. TLB refill runs on EVERY TLB miss, so its cycle cost is the MMU's
# dominant steady-state overhead. This benchmark makes that cost observable and
# regression-checkable: it runs the mmubench guard (4 cold misses, then 4
# steady-state TSB hits) under the J4 overlay with a VCD dump and reports, per
# phase, the cycles between two FIXED PROGRAM ADDRESSES enclosing a known number
# of misses -- plus the walk-FSM windows, so a hardware walker hit can be told
# from a failed probe.
#
# SCOPE. This script measures the hardware TSB walker's cycle cost. It once
# doubled as a fidelity check that the guard was a byte-faithful copy of
# linux@jcore's JCORE_TLB_FASTPATH; that software fast path no longer exists
# (the walker replaced it), so that framing and its gate are gone. What is
# measured here is the hardware, not a mirror of any kernel source.
#
# ------------------------------------------------------------------------------
# MEASURED BASELINE (2026-07-23; cosim clock 100 MHz / 10 ns period).
#
#   HISTORICAL. Everything in this block predates the hardware TSB walker and
#   describes the SOFTWARE TLB-miss fast path that the walker replaced. It is
#   kept as the anchor the walker deltas below are quoted against, and because
#   the A/B lessons in it still apply. It is NOT what this script measures now.
#
#   MEASURED, 9-insn fast path (cosim 100 MHz / 10 ns period), fault ->
#   back-executing-the-faulting-instruction. Run sim/profile_tlb_hotpath.py for
#   the per-instruction attribution these totals come from.
#
#                              | I-side (IMISS) | D-side (DMISS_R/W)
#     -------------------------+----------------+-------------------
#     HW exception entry       |      4 cyc     |       5 cyc
#     handler body (9 insns)   |     15 cyc     |      15 cyc
#     LDTLB.RN install+redirect|      3 cyc     |       3 cyc
#     -------------------------+----------------+-------------------
#     TSB hit, TOTAL           |     22 cyc     |      23 cyc
#     cold (-> C walker)       |     74 cyc     |      75 cyc
#
#   The COLD path keeps the 4-cycle redirect: it uses the parameterless
#   LDTLB.RN, which still stages through the PTEL CSR because the C walker
#   writes the TTE there. Only LDTLB.RN Rm takes the shortcut.
#
#   The handler body is IDENTICAL on both sides. The whole I-vs-D difference is
#   ONE cycle of hardware exception entry -- the D-side fault resolves a cycle
#   later in the pipe. Nothing else differs.
#
#   Where the 15-cycle body goes (D-side; I-side is the same):
#       1  stc tsbptr,r0        1  mov.l @r0+,r1 (tag_lo)
#       1  mov.l @r0+,r1        2  mov.l @r0,r3  (TTE; load-use)
#       2  cmp/eq pteh,r1       1  cmp/eq asidr,r1
#       3  bf (not taken)       2  bf (not taken)
#       1  ldtlb.rn r3
#   => the two NOT-TAKEN bf's cost 5 of the 15 cycles (33%). That is the
#   single largest software-visible bucket and is why static not-taken branch
#   prediction is item 1 below.
#
#   HISTORY, newest first.
#
#   24/23 -> 23/22: LDTLB.RN Rm lost a slot. It used to
#   spend one staging `PTEL := Rm` before it could assert tlb_wr, because the
#   TLB's ptel port was wired to the PTEL CSR flop -- even though the hot path
#   already held the TTE in a GPR. `tlb_wr = "XBUS"` sources the install data
#   from XBUS in the same slot as the TLB write; the register file has two read
#   ports and that slot only used one (ybus <- SSR), so Rm rides the free xbus
#   port. Measured on SYNTH_VARIANT=j4c (NOT j4 -- see synth/cpu_synth.sh):
#   41.23 -> 41.50 MHz, 7802 -> 7747 LUT, FF unchanged. The removed microcode
#   slot pays for the mux and a little over.
#
#   25/24 -> 24/23: exception ENTRY lost a cycle. Its six microcode slots wrote
#   SPC, then SSR+SR-bits, then EXPEVT, then PC -- four independent register
#   writes serialized only because sr_sel is a single-selector case. SR-bits and
#   EXPEVT touch different registers (this.sr vs this.priv) and never contended
#   for anything, so a combined SEL_EXCEPTION_EXPEVT arm merges them: sr_sel_t
#   goes 12 -> 13 literals, still 4 bits, no new control signal, no new datapath.
#   The cause code rides the slot immediate on xbus, which the SSR slot left
#   free. All TEN exception entries benefit, not just the TLB ones.
#
#   27/26 -> 25/24 came from splitting TLB protection faults off the
#   miss vector onto VBR+0x100, which is what SH-4 itself does (SH7750 manual
#   Rev 2.0 02/99: misses H'400, protection H'100). J4 had merged all six
#   causes onto H'400, which forced the hot path to run
#   `stc expevt / add / cmp/pl` -- later fused into a purpose-built CMP/MISS
#   EXPEVT instruction -- on EVERY TSB hit just to tell miss from protection.
#   The split removed the caller, so CMP/MISS was withdrawn and its encoding
#   returned to the free pool. Guard: mmuvecsplit (each vector writes a
#   distinct marker; corrupt the split and sub-test D fails with Result=4).
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
#       separate protection vector      ( 9 insns):  25 cyc fault->resume
#   Both software approaches are now HISTORY: the vector split beat the fused
#   instruction by another 2 cycles AND removed the livelock hazard by
#   construction rather than by a software check. Recorded because the
#   intermediate step is the more tempting one and was in fact taken first.
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
# WHY THE BRACKET IS A PROGRAM-ADDRESS PAIR AND NOT A HANDLER PC RANGE
#
# This script once bracketed on the HANDLER PC range [_h_common,_h_slow) and
# split the visits it found into halves, calling the first half cold and the
# second half TSB-hit. With the walker on, a TSB hit is resolved as a PIPELINE
# STALL: there is no exception, no vector fetch and NO HANDLER PC IN THE TRACE
# AT ALL. mmubench's 8 misses then produced only its 4 COLD handler visits, the
# halving split those 4 into "2 cold, 2 hit", and the script reported the cold
# path twice -- once labelled TSB-HIT (measured: 81 cyc "TSB-HIT", i.e. 3.5x the
# real 23-cycle software number). It did not fail; it lied. Nor can that bracket
# be rescued by keying on "faulting PC seen -> seen again": on a hit the PC never
# changes, so there is no second edge. That mode has been REMOVED.
#
# What survives, and is now the only mode: a bracket between two FIXED PROGRAM
# ADDRESSES enclosing a known number of misses. Whatever the assembler puts
# inside the bracket is byte-identical run to run -- which is what makes this
# immune to the alignment-pad failure recorded under HISTORICAL CORRECTION
# above. It also prints the walk-FSM windows (walk_busy / walk_install) so a
# hit can be told from a failed probe.
#
# The walker is now architecturally mandatory (design decision D1: no
# MMUCR.HW bit, no software TSB probe) -- there is no walker-OFF build to
# compare against any more. The numbers below are a HISTORICAL walker-ON vs.
# walker-OFF delta from when the `mmu_walker` generic still existed; they are
# kept as the anchor this script's own walker-mode numbers are quoted
# against, not as a reproducible A/B.
#
#   MEASURED (2026-08-10, mmu/tsb-hw-walker, walker-ON vs. then-still-extant
#   walker-OFF build):
#     guard      phase  misses  walker-OFF  walker-ON   delta
#     mmubench   cold      4       254         272      +18  (+4.5/miss)
#     mmubench   warm      4       130          66      -64  (-16/miss)
#     mmubenchi  cold      1       106         111       +5
#     mmubenchi  warm      1        53          39      -14
#
#   Anchored on the software baseline this same script reproduced on that
#   walker-OFF build (DMISS 23 / IMISS 22 warm, 75 / 74 cold):
#     DMISS warm  23 -> 7    IMISS warm  22 -> 8
#     DMISS cold  75 -> 79.5 IMISS cold  74 -> 79
#   A warm walk is 8 busy cycles (3 TSB reads + install); a FAILED probe is 4
#   (it aborts after the first tag word), which is the whole cold regression.
#   Caveat: every TSB read here acks in one cycle because the C walker just
#   wrote those lines. A cold D-cache TSB read would add fill latency.
#
# sim/profile_tlb_hotpath.py cannot attribute a walker hit -- it shares the
# handler bracket -- so use the walk-window dump here.
#
# ------------------------------------------------------------------------------
# Usage:  sim/bench_tlb_hotpath.sh
#         BENCH_GUARD=mmubenchi sim/bench_tlb_hotpath.sh
# Env:    JCORE_SOC (default: sibling ../jcore-soc), NM (default: sh2-elf-nm).
set -uo pipefail
cd "$(dirname "$0")/.."                       # jcore-cpu root
NM="${NM:-sh2-elf-nm}"
VCD="${TMPDIR:-/tmp}/tlb_hotpath_bench.vcd"
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
# Delete first: mmu_sim.sh's failures are swallowed by `|| true`, so without this
# a STALE VCD from a previous run passes the -s check and the whole bench
# "succeeds" in a second against hardware that was never built. Observed.
rm -f "$VCD"
echo "bench: running $GUARD under the J4 overlay (VCD -> $VCD) ..."
MMU_VCD="$VCD" sim/mmu_sim.sh "$GUARD" >/dev/null 2>&1 || true
[ -s "$VCD" ] || { echo "bench: no VCD produced" >&2; exit 1; }

# --- phase brackets + walk-FSM windows (see header) --------------------------
GUARD="$GUARD" VCD="$VCD" NM="$NM" python3 - <<'PY'
import os, re, subprocess, sys
P1 = 0x80000000
guard, vcd, NM = os.environ['GUARD'], os.environ['VCD'], os.environ['NM']
elf = os.path.join('sim', 'tests', guard + '.elf')
syms = {}
for line in subprocess.run([NM, elf], capture_output=True, text=True).stdout.splitlines():
    f = line.split()
    if len(f) == 3:
        syms[f[2]] = int(f[0], 16)
want = {'pc[31:0]': 'pc', 'walk_busy': 'busy', 'walk_side_i': 'side_i',
        'walk_install': 'inst'}
ids, ev, t = {}, [], 0
for line in open(vcd):
    line = line.rstrip('\n')
    if not line:
        continue
    m = re.match(r'\$var \w+ \d+ (\S+) (\S+) \$end', line)
    if m and m.group(2) in want:
        ids[m.group(1)] = want[m.group(2)]
        continue
    if line[0] == '#':
        t = int(line[1:]); continue
    if line[0] == 'b':
        p = line.split()
        if len(p) == 2 and p[1] in ids:
            try: ev.append((t, ids[p[1]], int(p[0][1:], 2)))
            except ValueError: pass
    elif line[0] in '01' and line[1:] in ids:
        ev.append((t, ids[line[1:]], int(line[0])))
pc = [(t, v) for t, n, v in ev if n == 'pc']
stamps = sorted({t for t, _ in pc if t > 0})
if len(stamps) < 2:
    sys.exit('bench: no pc transitions in VCD')
PER = stamps[1] - stamps[0]
print(f'bench: walker mode, clock period {PER/1e6:.1f} ns')

def first_at(addr, after=0):
    for t, v in pc:
        if t >= after and v == addr:
            return t
    return None

# Phase brackets. mmubench delimits both phases with its own labels; mmubenchi's
# legs end where execution resumes in the translated page, which its pre-existing
# _after_ifetch/_after_ifetch2 entry points already mark.
ends = {'mmubench': ('_bench_cold_end', '_bench_warm_end')}.get(
    guard, ('_after_ifetch', '_after_ifetch2'))
for label, a, b in (('cold', '_bench_cold_start', ends[0]),
                    ('warm', '_bench_warm_start', ends[1])):
    if a not in syms or b not in syms:
        print(f'bench:   {label}: {a}/{b} not in {elf} -- guard has no phase labels')
        continue
    ta = first_at(P1 + syms[a])
    tb = first_at(P1 + syms[b], ta + PER) if ta is not None else None
    if ta is None or tb is None:
        print(f'bench:   {label}: bracket [{a}..{b}) never completed')
        continue
    print(f'bench:   {label} [{a} .. {b}) = {(tb-ta)//PER} cyc')

busy = [(t, v) for t, n, v in ev if n == 'busy']
side = [(t, v) for t, n, v in ev if n == 'side_i']
inst = [(t, v) for t, n, v in ev if n == 'inst']
wins, st = [], None
for t, v in busy:
    if v and st is None: st = t
    elif not v and st is not None: wins.append((st, t)); st = None
if not wins:
    print('bench:   no walk_busy windows -- the walker is architecturally '
          'mandatory now, so this means it never armed; investigate before '
          'trusting the bracket numbers')
else:
    def sig_at(lst, tt):
        v = 0
        for a, b in lst:
            if a <= tt: v = b
            else: break
        return v
    print(f'bench:   {len(wins)} walk windows')
    for i, (a, b) in enumerate(wins):
        hit = any(v and a <= tt <= b for tt, v in inst)
        print(f'bench:     walk{i}: side={"I" if sig_at(side,a) else "D"} '
              f'busy={(b-a)//PER} cyc  {"INSTALL (TSB hit)" if hit else "FAIL (-> sw handler)"}')
PY
echo "bench: done. See the script header for the historical walker-ON/OFF baseline."

