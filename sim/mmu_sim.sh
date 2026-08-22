#!/usr/bin/env bash
# Build + run the MMU / priv-arch functional guards LOCALLY, mirroring the CI
# full-regression "functional-guards" job. Works on the local mcode GHDL.
#
# THE GOTCHA THIS SOLVES: the MMU instructions (LDTLB, PTEH/PTEL/ASIDR overlays,
# LDTLB.R, ...) live in the J4 OVERLAY decoder. A plain base-decoder build
# silently OMITS every MMU instruction -> LDTLB decodes to nothing -> the TLB
# never installs -> every MMU guard fails or hangs (and coverage-style guards
# can "pass" vacuously). The cosim MUST be built with CPU_VARIANT=j4, which
# sim/Makefile (via ../Makefile.inc + variants.toml) resolves to the J4-overlay
# decoder generated OUT-OF-TREE under sim/gen/j4-w<width>/decode -- it never
# touches the committed in-tree decode/*.vhd (which must stay base; committing
# J4-overlay tables is a known Fmax regression -- see
# jcore-base-decoder-j4-overlay-regression). CONFIG_PRIV_ARCH is itself derived
# from CPU_VARIANT by sim/Makefile and sim/tests/Makefile, so it is not passed
# here directly.
#
# Usage:
#   sim/mmu_sim.sh                       # build + run the full guard suite
#   sim/mmu_sim.sh mmuicolor             # build + run one guard (auto top/stop-time)
#   sim/mmu_sim.sh mmuxlate cpu_tb 120us # one guard, explicit top + stop-time
#   sim/mmu_sim.sh -n mmuicolor          # reuse the existing build (skip rebuild)
#
# Env: JCORE_SOC (default: sibling ../jcore-soc).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
export JCORE_SOC="${JCORE_SOC:-$ROOT/../jcore-soc}"
[ -d "$JCORE_SOC" ] || { echo "ERROR: JCORE_SOC not found at $JCORE_SOC" >&2; exit 1; }

BUILD=1
if [ "${1:-}" = "-n" ]; then BUILD=0; shift; fi

# ALWAYS make the cache .vhd cores present on disk: the mcode cosim
# RE-ANALYSES the VHDL sources at run time. Cheap (perl, a few seconds).
echo "== preprocess dcache/icache .vhm cores -> .vhd =="
for f in cache/dcache_ccl cache/dcache_mcl cache/icache_ccl cache/icache_mcl; do
  LD_LIBRARY_PATH='' perl "$JCORE_SOC/tools/v2p" < "$f.vhm" > "$f.vhd"
done

if [ "$BUILD" = 1 ]; then
  echo "== build MMU-on cosim (cpu_ctb + cpu_tb + cpu_cache_tb) =="
  cd sim
  # This rm and the PRIV_ARCH grep below were WORKAROUNDS for sim/Makefile not
  # tracking CPU_VARIANT: `make CPU_VARIANT=j4` over a j2 tree used to report
  # "up to date" and leave a PRIV_ARCH=false build in place. sim/Makefile now
  # carries a .cpu-variant stamp that every .vhh depends on, so the switch is
  # handled correctly without either. Both are KEPT as belt-and-braces -- the
  # grep in particular still catches failure modes the stamp cannot (a partial
  # build, a hand-edited .vhh) -- but they are no longer load-bearing.
  rm -f work-obj93.cf cpu_tb.vhh cpu_cache_tb.vhh cpu_ctb cpu_cache_tb
  make CPU_VARIANT=j4 \
       cpu_ctb cpu_tb cpu_cache_tb cpu_tb.vhh work-obj93.cf >/dev/null
  grep -q 'PRIV_ARCH => true' cpu_tb.vhh \
    || { echo "FAIL: build is not MMU-on (stale cpu_tb.vhh?)" >&2; exit 1; }
  cd ..
fi
cd sim
[ -x cpu_ctb ] || { echo "ERROR: cpu_ctb not built; run without -n first" >&2; exit 1; }

fail=0
run_guard() {  # <name> <sim_top-or-default> [stop-time] [wall-timeout-s]
  local t="$1" top="${2:-}" stoptime="${3:-80us}" wall="${4:-120}"
  if [ ! -f "tests/$t.S" ]; then echo "  SKIP  $t (no tests/$t.S on this branch)"; return; fi
  rm -f tests/$t.img tests/$t.o tests/$t.elf
  # Capture the build rather than discarding it: a failing make otherwise
  # produces no diagnostic and the guard just looks like it vanished.
  local build
  if ! build="$(make CPU_VARIANT=j4 -C tests $t.img 2>&1)"; then
    echo "  FAIL  $t${top:+ [$top]} (build)"
    echo "$build" | tail -20
    fail=1
    return 0
  fi
  local out
  # MMU_VCD=<path> dumps a VCD of the run (used by sim/bench_tlb_hotpath.sh to
  # trace the PC through the TLB-miss hot path). The sim exits at "Test Passed",
  # so the VCD's final timestamp is the pass-time.
  out="$(SIM_TOP="$top" timeout "$wall" ./cpu_ctb --stop-time="$stoptime" \
         ${MMU_VCD:+--vcd="$MMU_VCD"} -i tests/$t.img --ieee-asserts=disable 2>&1 || true)"
  if echo "$out" | grep -qi 'Test Passed'; then
    echo "  PASS  $t${top:+ [$top]}"
  else
    echo "  FAIL  $t${top:+ [$top]}"
    # MMU_TAIL=<n> widens this for debugging; 3 keeps normal output readable.
    echo "$out" | grep -iE 'result|fail|invalid' | tail -${MMU_TAIL:-3}
    fail=1
  fi
}

if [ $# -ge 1 ]; then
  # Single guard. Default the top + stop-time for the known cache/long guards.
  # A positional arg wins, then the documented `stop=<t> ./mmu_sim.sh <name>`
  # env override, then the per-guard default in the case below. The env fallback
  # is NOT redundant: this used to read `stop="${3:-}"`, which unconditionally
  # clobbered an exported `stop` with the empty string, so `stop=300us` silently
  # ran at the 80us default. That turns a stop-time overrun into what looks like
  # a hang that "reproduces identically at a longer stop-time" -- the single most
  # misleading failure mode this script has. Same reasoning for `top`.
  name="$1"; top="${2:-${top:-}}"; stop="${3:-${stop:-}}"
  case "$name" in
    mmuicolor)  top="${top:-cpu_cache_tb}"; stop="${stop:-400us}" ;;
    mmudcbit)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagereloc16k) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage4k)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage16k)  top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage64k)  top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupage1m)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagemix)  top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagemix2) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupagewalk) top="${top:-cpu_cache_tb}"; stop="${stop:-300us}" ;;
    mmureloc)   top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmurelocif) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmurelocbp) top="${top:-cpu_cache_tb}"; stop="${stop:-200us}" ;;
    mmupcprobe|mmudspcprobe) stop="${stop:-200us}" ;;
    m8_dside)   stop="${stop:-420us}" ;;
    # Keep in step with the budget on the `run_guard m8_dsdslot_0` line below.
    # Without this arm a single-guard invocation fell back to the 80us default
    # and died mid-sweep, which looks exactly like a wedge (the bus monitor's
    # "Rd did not see ACK" warnings are benign and present in passing runs too,
    # so the tail of the log is actively misleading). It is just the axis
    # needing ~613us to finish.
    m8_dsdslot_0) stop="${stop:-1100us}" ;;
    m8_ifetch_*) stop="${stop:-12ms}" ;;
  esac
  run_guard "$name" "$top" "${stop:-80us}" "${4:-240}"
else
  echo "== priv-arch + MMU guards (cpu_tb) =="
  for t in exctest trapatest pm3vec pm3guard privmode banktest excguard \
           rteredir mmureg mmuguard mmuxlate mmurte mmustore mmuimiss mmuimiss_illegal \
           mmusr mmufault mmufsr mmudslot mmuidslot mmutsb mmuwalkhit mmuwalkmiss mmuwalkstale mmuwalktorn mmuwalkdside mmuwalkiside mmusplit mmuishadow mmudshadow mmuwalkorder mmutsbslot mmuwalkasid mmutsbvictim mmuwalkway1 mmup4alias mmup4priv mmuidx mmustres mmustr2 mmuimissrest mmushadowld mmushadowst mmurestartpc \
           mmustale mmuasid mmuasidsh mmuglobal mmumultihit mmudblflt mmunest_trapa mmunest_slotill mmunest mmuremap mmucmpcsr mmuvecsplit mmurun mmubench mmubenchi mmuirun mmuainc mmuainc2 mmusmep j4_illegal_trap slotillset; do
    run_guard "$t"
  done
  run_guard mmufaultage "" 60us
  # mmudrain gets an explicit stop-time for MARGIN, not because 80us is too
  # short. Measured: the guard completes at 31.62us (final timestamp of a
  # MMU_VCD dump, which ends at the "Test Passed" exit; leg D itself runs
  # 18.9-27.9us). At the 80us loop default a mutated build still reports its
  # failure, at 79.93us -- but that is a 0.09% margin, coincidentally rather
  # than safely sufficient, and any added leg or a slower memory config would
  # push it over. 120us is ~3.8x the measured completion time.
  # (An earlier revision of this comment claimed the result landed at ~400us
  # and that suite mode was blind. That was wrong: it read the
  # end-of-simulation error timestamp as the result-write time.)
  run_guard mmudrain "" 120us

  # Restart-PC EXACTNESS probes. Run explicitly (200us) rather than from the
  # loop above: they are the only guards that measure HOW FAR the D-side
  # TLB-fault restart PC lands from the faulting instruction, in units of
  # instructions, instead of merely checking that control flow survived.
  #   mmupcprobe    pins the NORMAL arm  (plain load, tlb_exc_pc = ex_if_pc+4)
  #   mmudspcprobe  pins the DELAY-SLOT arm (branch delay slot, ex_if_pc+2)
  # Other guards (mmufault, mmustale) do fault on plain loads through
  # the same restart path, but only coarsely -- they check that control flow
  # survived, not WHERE the restart landed. mmupcprobe is the only EXACT check
  # of the plain-load arm, so leaving it unwired meant an off-by-N regression
  # there would keep the suite fully green.
  run_guard mmupcprobe   "" 200us
  run_guard mmudspcprobe "" 200us
  echo "== cache guards (cpu_cache_tb) =="
  # mmuwalkdside under the CACHED top as well as cpu_tb. It is the only guard
  # that resolves a faulting D-store entirely via the HARDWARE WALKER (no LDTLB)
  # through a non-identity mapping (VA 0x42000 -> PA 0x44000) with a
  # walker-installed code page, so it is the one that covers
  # "walker install + cache + store". Verified passing 2026-08-12.
  run_guard mmuwalkdside cpu_cache_tb 300us
  run_guard mmuicolor  cpu_cache_tb 400us
  run_guard mmudcbit   cpu_cache_tb 200us
  run_guard mmureloc   cpu_cache_tb 200us
  run_guard mmurelocif cpu_cache_tb 200us
  run_guard mmurelocbp cpu_cache_tb 200us
  run_guard mmupage4k       cpu_cache_tb 200us
  run_guard mmupagereloc16k cpu_cache_tb 200us
  run_guard mmupage16k  cpu_cache_tb 200us
  run_guard mmupage64k  cpu_cache_tb 200us
  run_guard mmupage1m   cpu_cache_tb 200us
  run_guard mmupagemix  cpu_cache_tb 200us
  run_guard mmupagemix2 cpu_cache_tb 200us
  run_guard mmupagewalk cpu_cache_tb 300us
  echo "== M8 fault-coverage sweep =="
# Mutation spot-checks (2026-08-01). A guard that passes proves nothing
# unless it can be shown to fail, so a sample was checked by corrupting one
# expected constant and confirming a sub-test-specific failure code (not the
# 0x7F early-exit clamp, which would mean the assertion is never reached):
#
#   mmufault  c_dmiss_r  0x60->0x61     => FAIL Result=2
#   mmusmep   c_iprot    0xA0->0xA1     => FAIL Result=2
#   mmuguard  p_expevt   0x180->0x181   => FAIL Result=2
#   mmuidx    p_val_plain               => FAIL Result=5
#   mmutsb    p_tsbbr_val               => FAIL Result=4
#
#   mmuxlate  UNPROVEN. Two attempts were uninformative rather than
#             revealing: p_testval is a self-consistent sentinel (loaded
#             into r4, stored, read back, compared against r4 -- mutating it
#             moves both sides), and p_ppn_mask masks an already-aligned
#             address, so widening it changes nothing. Proving this guard
#             needs a mutation chosen against its specific logic.
#
# This is a sample, not a proof about the suite. The magic-token change makes
# "did this guard run?" structural; "is its assertion strong?" still needs
# per-guard work like the above.

# Orphaned guards -- built by sim/tests/Makefile but invoked by nothing.
# Measured 2026-08-01, all four fail; they rotted precisely because nothing
# ran them. Recorded here so their state is in the repo rather than
# rediscovered:
#
#   mmubratest    IF: invalid read addr XXXXXXXX -- fetches an undefined
#                 address; the guard runs off the rails entirely.
#                 RETIRED 2026-08-07 (deleted, with its Makefile rule) --
#                 broken by construction, not rot, and not a CPU defect: it
#                 maps page 1 NO-EXECUTE (PTEL=0xA8, VPN=1) and then places
#                 _done/_fail at `.org 0x1000`, i.e. INSIDE that same
#                 no-execute page, so its exit path is unreachable. It also
#                 sets VBR=0 and installs no handler, so the resulting IPROT
#                 vectors to 0x400 -- which is `far1`, straight back into the
#                 nop sled. Re-measured on the current tree first: it fails
#                 identically to 2026-08-01, so deferred I-fetch delivery
#                 changed nothing here.
#                 It was a DIAGNOSTIC scaffold ("does a taken bra to a far
#                 label work after AT is enabled?"), written to isolate the
#                 mmuidslot hang -- not a guard of a CPU property. That
#                 question is now answered yes by m8_idslot_0-2 (green and
#                 wired in) and by the rest of this suite, which branches
#                 under AT throughout. Its historical role is recorded in
#                 docs/superpowers/handover-mmu-delay-slot-data-fault.md.
#   m8_idslot_0   Test failed. Result=2   (FIXED + wired in, 2026-08-06)
#   m8_idslot_1   Test failed. Result=25  (FIXED + wired in, 2026-08-06)
#   m8_idslot_2   Test failed. Result=49  (FIXED + wired in, 2026-08-06)
#   (the 2026-08-01 note recorded Result=2 for all three; re-measured at HEAD
#   immediately before the fix, _1 and _2 report 25 and 49 -- different cases of
#   the same axis, not different defects.)
#
# mmufaultage (added 2026-08-06, wired into the run below) locks the
# precise-exception squash fix in core/datapath.vhm's g_squash_ifetch
# (commit 0280b7e) using a non-idempotent faulting load. See the guard's own
# header for the mutation evidence and for why it does not demonstrate an
# exception-ordering defect (mis-ordered delivery was measured benign here).
#
# The three m8_idslot_* Result=2 failures were NOT rot: they were the real
# I-side delay-slot restart defect (the restart landed on the delay slot instead
# of backing up to the branch). Deferred I-fetch fault delivery fixes all three
# and they are now in the run below. mmubratest was the fourth orphan and is
# now RETIRED (see above) -- there are no orphaned guards left.
#
# m8_dsdslot_0 (2026-08-04 review round): the axis's branch-target vacuity
# bug (buggy and correct restart PCs coincided, so it could never fail) was
# fixed via a poison trap. Fixing it exposed a bus-ACK hang (Result=1, "Rd
# did not see ACK for data sram") on CAS.L Rm,Rn,@R0 and MOV.B @Rm+,Rn on
# CLEAN RTL. Root-caused via dp_if_pc + spec slot classification: BOTH are
# the SAME defect ("Defect 7") -- any D-side memory access whose ma_op slot
# launches after slot 0 (locked RMW forms, and post-increment @Rm+
# loads/stores, which spend slot 0 writing the incremented base before the
# access slot) shadows ma_dslot past its deassertion, so a DMISS in that
# slot restarts at the delay-slot instruction itself instead of the branch.
# Slot-0-access forms (plain @Rm, @-Rn, @(disp,Rm/Rn), register-direct) are
# unaffected -- confirmed against every one of the 26 spec-classified cases
# in m8_dsdslot_0 (22 slot-0, all PASS; 4 late-access: CAS.L Rm,Rn,@R0,
# MOV.B/L/W @Rm+,Rn, all Defect 7).
#
# DEFECT 7 IS FIXED (decode/decode_core.vhm, g_dslot). Root cause: the flag
# the datapath shadows as ma_dslot was re-sampled from delay_jump on EVERY
# non-stalled slot, so it was a one-SLOT pulse rather than a per-INSTRUCTION
# attribute -- a multi-slot delay-slot instruction saw it reload to '0' before
# its access slot. delay_slot_o now samples delay_jump once per instruction
# (gated on `dispatch') and HOLDS across every slot, so the arm selection is
# independent of which slot carries the access. mmudspcprobe_late (the standing
# reproducer, measured 0x00010101 before / PASS after) is wired into the active
# list below, and the full 69-guard suite is green.
#
# COVERAGE. All five late-access forms are locked by one guard each --
# mmudspcprobe_late{,b,w,c,m,mw} -- built from a single shared harness where the
# ONLY difference is the delay-slot instruction. Each was measured RED
# (Result=65793) on the pre-fix RTL and GREEN after, so none is vacuous. That
# per-form evidence is deliberate: the fix is structural, but "structural" is an
# argument and these are measurements.
#
# The generator's Defect 7 skips are gone too (emit.go: the lateAccess() helper
# and the MAC-specific skip), so m8_dsdslot_0 now emits the @Rm+ loads inline
# and its case numbering is UNCHANGED (the parked failure is still 1007).
# CAS.L IS NOW EMITTED (case 1) AND PASSES. An earlier revision of this file
# claimed it "hangs the bus in the maximal three-fault shape -- a locked RMW
# whose read faults appears not to release the bus lock". THAT WAS WRONG, and
# the retraction is worth reading because the symptom was so misleading: the
# real cause was that the IMAGE had outgrown the harness's fixed scratch block.
# kmain's own page-table setup was writing over the image (PGD[0] at 0x2000 onto
# case 23's literal pool, the PTEs at 0x2800 onto case 29's), and adding one more
# case pushed _edata past the 64-long TSB zero-fill at 0x2C00, which erased
# _m8_run_all itself -- so the dispatch jsr ran into zeros and the CPU
# reset-looped every ~4.8us. db_lock was '0' the entire time; there was never a
# lock involved. The block now lives at 0x00010000 and sim/tests/Makefile fails
# the build if an m8 image reaches it.
#
# MAC.{L,W} remain skipped on this axis for a SEPARATE, pre-existing reason
# ("dual memory-pointer instruction -- only one base register is seeded"), never
# a Defect 7 skip in substance; mmudspcprobe_latem{,w} cover them.
#
# m8_dsdslot_0 remains PARKED below on its own separate failure -- see the park
# comment there, which is NOT Defect 7.
#
# m8_smoke and m8_idslot_0-2 are wired into the run below (the latter as of
# 2026-08-06, see the note above).
  run_guard m8_smoke
  run_guard m8_dside    "" 420us
  # m8_dsdslot_0: UNPARKED 2026-08-06. 29 of its 32 cases run; STC.L GBR/SR/VBR,
  # @-Rn (26/27/28) are excluded from _m8_run_all via m8gen's dsdslotSkip -- they
  # hang the bus instead of reporting, MEASURED pre-existing (they hang
  # identically on 46b3cc2, before deferred I-fetch fault delivery), and the same
  # @-Rn addressing in MOV.W Rm,@-Rn (case 25) passes, so it is the
  # control-register store form. That is the axis's remaining open item.
  #
  # THE ORIGINAL PARK (Case A Result=1008, case 8 = MOV.B @(disp,Rm),R0) IS FIXED.
  # It needed BOTH halves and neither alone was enough:
  #   1. deferred I-fetch fault delivery (if_fault, core/components_pkg.vhd), so
  #      the delay-slot fetch fault restarts at the BRANCH; and
  #   2. clearing squash_ifetch_r when a D-side fault is raised inside a window an
  #      I-side fault opened (core/datapath.vhm, g_squash_ifetch). Without it the
  #      I-side "everything in this window is older, commit it all" exemption
  #      masked the D-side squash, so the faulting load COMMITTED r0=0xFFFFFFA1 at
  #      9660ns; the restart then re-ran MOV.B @(disp,R0),R0, whose base IS its
  #      destination, addressing @0xFFFFFFA1 and reading 0 -> SNAP_A=0x00000000.
  # Mutation-proven: removing (2) alone puts this guard straight back to
  # Result=1008 at 28180ns. Non-idempotent forms like case 8 are why a precise
  # squash cannot be traded for "just re-execute it".
  #
  # ---- HISTORY BELOW (the diagnosis that produced the deferred-delivery fix).
  # NARROWED 2026-08-06, still unfixed. It is NOT a harness construction bug and
  # NOT a wrong restart PC. Evidence:
  #   * SNAP_A (cold, 3-fault leg) = 0x00102000 -- the UN-loaded base; SNAP_B
  #     (warm) = 0xFFFFFFA1 -- the correct sign-extended load. Not 0xFFFFFFFF,
  #     so the poison trap never fired.
  #   (SNAP values and the trace below were measured when this case was still
  #   numbered 7 and the scratch block was at 0x2000; the mechanism is unchanged
  #   but the timestamps shift.)
  #   * if_dr trace across the case shows control flow is correct at all three
  #     faults: [4B2B 8400] -> fault -> restart on the BRANCH -> [4B2B 8400] ->
  #     4C2B (target) -> fault -> restart on the TARGET -> 4C2B -> capture.
  # So the delay-slot load issues, is correctly NOT re-executed, and its result
  # never reaches r0: a LOST WRITEBACK in the branch-target-IMISS shadow -- the
  # Defect 6 / z_grace family, on a load result. This is exactly the gap
  # core/datapath.vhm's g_wb_grace comment documents ("No guard specifically
  # exercises an I-fetch fault with a genuinely pending w-port writeback whose
  # delay slot is re-executed"); case 7 IS that guard. Cases 1-6 pass because
  # they target control registers -- case 7 is the first GPR destination.
  # Three probes REFUTED (each rebuilt, re-run, reverted):
  #   z_grace <= tlb_exc_ifetch (drop `not delay_slot')   -> still 1007
  #   reg_wr_w_g <= reg.wr_w    (w-port squash disabled)  -> still 1007
  #   drop `and tlb_squash_r = '0'' from the mem-issue gate -> still 1007
  # so the write is NOT being lost at either grace-gated port or the issue gate.
  # ---- FULL ROOT CAUSE 2026-08-06: TWO STACKED DEFECTS -----------------
  # This is why every single-cause fix failed: A and B must BOTH be fixed.
  # Fixing A alone converts the symptom into B's symptom; fixing B alone leaves
  # A. Measured by re-running each experiment with the isolation CORRECTLY
  # placed and then reading SNAP_A, which is the step that had been missing.
  #
  # DEFECT A -- a YOUNGER fetch fault overrides an OLDER one.
  #   decode's texc_req keeps the FIRST fault until dispatch; the datapath's
  #   tlb_exc_captured clears on tlb_exc_pend='0' and re-captures, so the LAST
  #   wins. The speculative branch-TARGET fetch (0x103000) thus overwrites the
  #   delay-slot fetch fault (0x101000); the single handler restarts at the
  #   target and the delay slot is never re-executed -> SNAP_A = 0x00102000
  #   (base, un-loaded).
  #   PROVEN FIXABLE: an exc_pending_r latch in cpu.vhd (set on tlb_exc_en,
  #   released at SR.RB=1) gating both fault branches makes the older fault win,
  #   and the delay-slot load then DOES commit -- measured W-PORT r0 <=
  #   0xFFFFFFA1. That intervention works; it just exposes B.
  #
  # DEFECT B -- the I-side DELAY-SLOT FETCH fault does not back up to the branch.
  #   With A fixed, the serviced fault is the delay-slot fetch at 0x101000, and
  #   its restart PC must be the BRANCH (0x100FFE) so the branch re-issues its
  #   delay slot. The I-side arm picks that with `if delay_slot = '1' then
  #   tlb_exc_pc := tlb_fault_va - 2', but delay_slot is EX-ALIGNED and the FETCH
  #   runs ahead of EX, so at capture time the branch has not reached EX yet.
  #   Measured at the two captures:
  #     19160ns tlb_exc_pc := 0x00101000  delay_jump=1  dslot=0   <- dslot FETCH
  #     20180ns tlb_exc_pc := 0x00103000  delay_jump=0  dslot=1   <- target fetch
  #   So the arm takes the "normal" branch, restarts ON the delay slot, the load
  #   re-executes and then falls through past the branch into the poison trap ->
  #   SNAP_A = 0xFFFFFFFF. That is the measured result with A fixed.
  #   NOTE the discriminator that works: delay_jump is '1' exactly at the
  #   delay-slot fetch capture and '0' at the target fetch capture, while dslot
  #   is the wrong way round for both. delay_jump ("the op in ID is a branch, so
  #   the next fetch is its delay slot") is fetch-aligned and is the correct
  #   predicate here; dslot answers a different question ("a delay-slot
  #   instruction is in EX"), which at 20180ns would wrongly compute
  #   0x103000-2 = 0x102FFE for the TARGET fetch.
  #   This is Defect 7 one more time -- delay-slot-ness sampled at the wrong
  #   pipeline point -- now on the I-fetch path. It is also exactly the arm
  #   z_grace's old COVERAGE WARNING said was never exercised, and the reason
  #   m8_idslot_0-2 (the I-side delay-slot sweep) are rotted orphans: nothing
  #   has ever tested this path.
  #
  # WHY NO ATTRIBUTION SCHEME CAN WORK -- ROOT CAUSE, measured 2026-08-06.
  # THE DELAY-SLOT FETCH FAULTS BEFORE ITS BRANCH DECODES. Deduplicated trace of
  # VA 0x00101000 (case 8 Case A cold leg, CLEAN tree):
  #     26060ns  FAULT on 0x00101000            delay_jump=0
  #     26100ns  fetch of 0x00101000 ISSUED     delay_jump=0
  #     26360ns  FAULT on 0x00101000            delay_jump=0   <- the captured one
  #     26370ns  fetch of 0x00101000 re-ISSUED  delay_jump=1   <- branch NOW decoded
  # delay_jump is '0' at EVERY instant the fault is raised, and at the issue of
  # the fetch that faults. It first rises at 26370, AFTER the fault. So:
  #   * capture-at-fault  reads 0  (tried -- exc_pc = 0x00101000)
  #   * capture-at-issue  reads 0  (tried -- same result)
  #   * retroactive tag   never fires (tried -- the windows do not overlap)
  # There is NO instant at which the hardware knows the faulting fetch is a delay
  # slot, because the branch has not been decoded yet. This is not a plumbing or
  # alignment problem and no fourth attribution scheme will fix it.
  #
  # CORRECTED: an earlier note here said "the fetch unit runs ahead of the
  # branch's decode" and a later one said delay_jump IS high at the delay-slot
  # fetch issue. BOTH were partly wrong. There are TWO issues of that VA; the one
  # that faults is the early one (delay_jump=0) and the one with delay_jump=1 is
  # a later RE-fetch that never faults.
  #
  # ARCHITECTURAL CONSEQUENCE -- IMPLEMENTED 2026-08-06. The I-side restart PC
  # cannot be decided at fault time. The fault must instead be CARRIED WITH THE
  # FETCHED INSTRUCTION and raised when that instruction reaches the point where
  # its context is known (its branch decoded) -- classic deferred / fault-on-use
  # exception delivery, the same "metadata travels with the instruction"
  # principle as US5774709A but applied to the FAULT, not just to EPC+BD.
  # This is now the RTL: core/components_pkg.vhd (if_fault / if_fault_prot ride
  # the instruction), core/datapath.vhm (deferred capture from if_pc), and
  # decode/decode_core.vhm (next_op raises TLB_IMISS/IPROT from if_fault, and
  # texc_defer_cap_o marks the dispatch boundary at which the capture fires --
  # if_fault's own rising edge is ONE SLOT TOO EARLY, decode has not registered
  # delay_slot yet, measured on sim/tests/mmuidslot.S).
  #
  # ---- earlier: HANG ROOT-CAUSED AND FIXED (2026-08-06). The per-stage first cut hung; the
  # cause was mis-ATTRIBUTION of the IF-stage delay-slot bit, not the design:
  #   While a branch sits in ID, TWO fetches are issued in the same delay_jump
  #   window -- the delay slot (SEQUENTIAL) and the branch TARGET (REDIRECTED).
  #   Tagging both meant the TARGET's fault restarted at target-2. Measured: the
  #   harness enters a case via `jmp @r5' whose target IS the branch at
  #   0x00100FFE; that fetch faulted, restarted at 0x00100FFC -- not an
  #   instruction boundary -- ran garbage, and reset-looped every ~4.8us
  #   (0x100FFC -> 0x80000330 -> 0x00000118 -> kmain -> repeat).
  #   FIX: qualify with the fetch's own addr_sel (sequential vs redirected).
  #   `delay_jump and not instr.addr_sel' removes the hang and restores a clean
  #   failure. KEEP THIS QUALIFIER in any future attempt.
  #
  # WHAT IS STILL WRONG, now measured precisely. Capture-at-ISSUE is TOO EARLY:
  #   19250ns EX 0x00101000 (delay slot)  dslot=0 delay_jump=1  exc_pc=0x00101000
  #   19490ns EX 0x00101000  <- restart landed ON the delay slot, branch NOT re-run
  #   19510ns EX 0x00101002  <- POISON  => SNAP_A = 0xFFFFFFFF
  # delay_jump is '1' while the delay slot is in EX but was '0' when its fetch
  # was ISSUED -- the fetch unit runs ahead of the branch's decode. So the bit
  # cannot be latched at issue.
  #
  # A retroactive tag was tried -- clear if_dslot at issue, then set it when
  # delay_jump rises on the still-outstanding sequential fetch (this.inst_o.en='1'
  # and this.inst_o.jp='0'). It compiles and does NOT hang, but never fires:
  # exc_pc is still 0x00101000 at the delay-slot fetch capture, so the
  # delay_jump-high window and "that fetch still outstanding" do not overlap.
  # MEASURE THAT OVERLAP FIRST (inst_o.en / jp / delay_jump around the delay-slot
  # fetch) before a third attribution scheme -- that is the one fact this whole
  # line of attack keeps turning on.
  #
  # ---- earlier: PER-STAGE RESTART METADATA -- first cut ATTEMPTED, hangs. Recorded so the
  # next attempt starts from the design and the failure, not from scratch.
  #
  # THE DESIGN (this part is sound and worth keeping). Every fault's restart is
  # determined by two fields belonging to THE STAGE THAT FAULTED:
  #     restart_pc = own_pc - (is_dslot ? 2 : 0)
  #     I-side entry: SPC = tlb_exc_pc     -> tlb_exc_pc = restart_pc
  #     D-side entry: SPC = tlb_exc_pc - 4 -> tlb_exc_pc = restart_pc + 4
  # The MA/EX record already exists (ex_if_pc + ma_dslot). The IF record does
  # NOT: tlb_fault_va supplies the PC but nothing supplies is_dslot for the
  # outstanding fetch, which is the whole of Defect B.
  #
  # WHAT WAS BUILT: a this.if_dslot field in datapath_reg_t (components_pkg.vhd),
  # latched at the instruction-fetch ISSUE point from decode's delay_jump (routed
  # via model/pkg.go + decode.vhd.tmpl + cpu.vhd + a datapath port + the
  # datapath_pkg.vhd COMPONENT decl), and consumed by the I-side arm. Latching at
  # ISSUE rather than sampling at fault time is the point: the combinational
  # delay_jump is not stable at the fault-capture edge.
  #
  # OUTCOME: HANGS -- 200us, no result, no compile error, with or without the
  # exc_pending_r latch (A). The hang point was NOT located. What was ruled out:
  # the I-side arm is structurally intact in the generated VHDL, and the early
  # captures that look wrong (exc_pc=0x800006D2 for fault_va=0x00100FFE) are
  # legitimate D-SIDE faults -- the harness PLANTS code by storing to 0x00100FFE,
  # so a DMISS_W there is expected and correctly takes the D-side arm.
  #
  # PRIME SUSPECT, unverified: delay_jump at fetch-ISSUE attributes the bit to the
  # wrong fetch. The fetch unit runs ahead, so the delay slot may well be fetched
  # BEFORE the branch reaches ID -- in which case delay_jump is still '0' at that
  # issue and '1' at some later, unrelated issue. If so the bit has to be
  # attributed retroactively, when the branch DECODES, to a fetch already in
  # flight -- which is exactly the FIFO-of-(EPC,BD)-per-stage structure of
  # US5774709A rather than a single latch. Measure the delay_jump/issue
  # relationship first; do not re-implement blind.
  #
  # ---- earlier: A+B ATTEMPTED AND MEASURED (2026-08-06). Both landed, wired and compiling
  # (decode delay_jump_o via model/pkg.go + decode.vhd.tmpl, a datapath
  # delay_jump input -- NOTE also datapath_pkg.vhd's COMPONENT decl, which is
  # easy to miss and gives "no declaration for delay_jump" in cpu.vhd -- plus
  # the exc_pending_r latch). Target case STILL Result=1007, SNAP_A = 0xFFFFFFFF
  # (poison), i.e. B did not take effect. Two things the waveform then showed:
  #
  #   1. delay_jump ARRIVES TOO LATE FOR THE CAPTURE. At the delay-slot fetch
  #      capture the VCD shows delay_jump=1 at that timestamp, yet the captured
  #      value is tlb_exc_pc = 0x00101000, not 0x00100FFE -- so at the clock edge
  #      the arm sampled '0' and delay_jump only rose later in the same
  #      timestamp. It is not merely EX-vs-fetch misalignment: the fetch-aligned
  #      flag is not stable at fault-capture time either. A usable predicate has
  #      to be registered ahead of the capture, not consumed combinationally.
  #
  #   2. A THIRD manifestation, not previously seen. The D-side DMISS in the same
  #      sequence captures tlb_exc_pc = 0x00101004 (fault_va=0x00102000) -- the
  #      NORMAL arm, ex_if_pc+4 -- meaning ma_dslot read '0' for the delay-slot
  #      load. So the Defect 7 per-instruction delay-slot flag does NOT survive
  #      this multi-fault sequence, even though mmudspcprobe_late (single fault,
  #      same page) passes. Whatever perturbs it is a third thing to find.
  #
  # So the fix is A + B + (3), and B needs a registered fetch-stage delay-slot
  # bit rather than a combinational one -- which is exactly the MIPS/US5774709A
  # shape: carry EPC+BD per PIPELINE STAGE so the faulting stage supplies both.
  #
  # ORIGINAL PLAN (superseded): FIX = A + B together. B needs a fetch-aligned delay-slot indicator routed to
  # the datapath (delay_jump is decode-internal today; dslot, the EX-aligned one,
  # is what is currently wired). Note the CAS.L regression seen under A-alone is
  # expected to be B as well, and should be re-checked once B lands.
  #
  # ---- earlier partial diagnosis (superseded by the above, kept for the
  #      measurements) ------------------------------------------------------
  # Two TLB faults are detected before EITHER is dispatched, and decode and the
  # datapath disagree about which one the exception describes.
  #
  #   decode   (decode_core.vhm texc_req_reg): latches the FIRST fault
  #            (`elsif tlb_exc_en='1' and texc_req='0'') and HOLDS it until
  #            texc_ack, i.e. until the exception is actually dispatched. A
  #            second fault arriving meanwhile is IGNORED.
  #   datapath (datapath.vhm tlb_exc_captured): clears the moment
  #            tlb_exc_pend='0', so a second fault RE-CAPTURES. LAST wins.
  #
  # tlb_exc_en and tlb_exc_pend are the SAME signal (cpu.vhd:632/634, both
  # <= exc_en), so both blocks see identical pulses -- only the HOLD differs.
  # decode therefore dispatches fault #1's kind while the datapath supplies
  # fault #2's restart PC (and TEA / PTEH / MMUFSR).
  #
  # Measured (29us MMU_VCD of this guard, case 8 Case A cold leg):
  #   26360ns  FAULT fault_va=0x00101000 ifetch=1 -> tlb_exc_pc := 0x00101000
  #   26380ns  FAULT fault_va=0x00103000 ifetch=1 -> tlb_exc_pc := 0x00103000
  #   26400ns  EX delay-slot load @0x101000  (executes exactly once)
  #   26460ns  handler entered ONCE, SPC = 0x00103000
  # So the restart resumes at the branch TARGET instead of the branch, the
  # delay slot is never re-executed, and its load result never reaches r0 --
  # which is exactly the measured SNAP_A = 0x00102000 (base, un-loaded).
  # Note the load itself does NOT fault here; expevt stays 0x040 (IMISS)
  # throughout and both faults are I-side.
  #
  # FIX DIRECTION: the datapath's capture must belong to the fault decode
  # dispatches, i.e. be released by decode's texc_ack -- which is currently NOT
  # routed to the datapath (decode_core-internal). Wiring it out is the work.
  #
  # CORRECTION 2026-08-06: three earlier entries below claimed a variant failed
  # "with CAS.L skipped too, so not CAS-specific". THAT ISOLATION WAS BROKEN --
  # the temporary skip was inserted into emitDSide (there are two `CAS.' guards
  # in emit.go and a first-match edit hits the D-side axis, not this one), so
  # CAS.L was never actually skipped and case 1 stayed CAS.L. Re-run with the
  # skip correctly placed in emitDSideDSlot, ALL THREE variants give the same
  # corrected picture:
  #     * they REGRESS CAS.L (case 1, Result=1001) -- a real regression, and
  #       CAS-specific after all, not a general breakage of the first case;
  #     * with CAS.L skipped they leave the target case UNFIXED, still
  #       Result=1007 at 20860ns (case 7 once CAS.L is out of the numbering).
  # So none of them touches the actual defect, and each additionally breaks the
  # locked RMW. Do not re-derive "it breaks case 1 generally" from the older
  # wording below -- that conclusion came from the broken isolation.
  #
  # A fourth variant was tried and refuted the same way: stall the instruction
  # FETCH while a fault is outstanding (datapath, gate the "start new instruction
  # request" issue on tlb_squash_r='0', the same window the memory-issue gate
  # uses) -- i.e. suppress the younger FETCH rather than its fault, which is what
  # the untranslated-address finding said was needed. Same outcome: CAS.L
  # regresses to 1001, and with CAS.L skipped the target case is still 1007.
  #
  # BOTH "hold the capture until dispatch" variants are now REFUTED, which is
  # the useful result: the fix is NOT in the capture-release logic.
  #   (a) release on handler entry (this.sr.rb = '1')  -> case 1 RED (1001),
  #       with CAS.L skipped too, so not CAS-specific.
  #   (b) release on decode's texc_ack, properly plumbed out of decode_core
  #       (model/pkg.go port lists + decode.vhd.tmpl + cpu.vhd + a datapath
  #       tlb_exc_ack input; wiring verified -- one decode and one datapath
  #       instance, all three references present) -> the CPU HANGS: 200us with
  #       no result and no error. Between dispatch and SR.RB=1 faults are still
  #       enabled, so re-arming that early lets the exception entry's own fetch
  #       re-capture and clobber the TEA/PTEH the handler is about to read.
  #
  #   (c) suppress the YOUNGER fault at the RAISE point: an exc_pending_r latch
  #       in cpu.vhd (set on tlb_exc_en, released at SR.RB=1) gating both the
  #       i_at_translated and d_at_translated branches, so at most one fault is
  #       ever outstanding -> case 1 RED (1001), and again with CAS.L skipped,
  #       so not CAS-specific. ROOT CAUSE OF THAT REGRESSION, and it is the
  #       useful part: on a TLB miss NEITHER branch of the instruction address
  #       mux applies (cpu.vhd, g_inst_p1_fold: the P1 fold, else
  #       i_at_translated and tlb_i_hit='1'), so inst_o.a passes through
  #       UNTRANSLATED -- the raw VA is used as the physical address. That is
  #       normally harmless because the fault redirects the pipeline before the
  #       fetched word matters. Suppress only the FAULT and the fetch still
  #       completes, against an untranslated address, and the garbage it returns
  #       is executed.
  #
  # So suppressing the younger fault is NOT enough: the younger FETCH itself has
  # to be stalled/not issued while an older fault is outstanding. That is a
  # fetch-unit change (gating sig_inst_o.en / driving if_stall), not a change to
  # the fault-raise condition, and it is the next thing to try.
  #
  # So neither "first wins" nor "last wins" nor "hold until dispatch" is right,
  # because the capture is not where the ordering decision belongs. The actual
  # violation is upstream: a YOUNGER fetch fault (the speculative branch TARGET,
  # 0x103000) is raised while an OLDER one (the delay-slot fetch, 0x101000) is
  # still pending, and precise-exception semantics require the OLDEST fault to
  # win. That prioritisation has to happen where the fault is raised -- cpu.vhd's
  # exc_en / the TLB fault detect -- so that only one fault is ever outstanding.
  # Then decode and the datapath cannot disagree, whatever their hold windows.
  #
  # REFUTED, do not repeat: replacing the release condition with handler entry
  #   if PRIV_ARCH and this.sr.rb = '1' then this.tlb_exc_captured := '0';
  # turns case 1 RED (Result=1001) and does so even with CAS.L skipped, so it is
  # not CAS-specific. "Keep the FIRST episode" is therefore just as wrong as
  # "keep the last": within a single dispatched fault there can be several
  # tlb_exc_pend episodes, and a later one can carry the correct VA -- see the
  # existing first-cycle-capture comment in datapath.vhm about the I-fetch
  # stream advancing a word while an IMISS persists. Only texc_ack marks the
  # boundary that actually matters.
  # STOP-TIME BUDGET (measured, not guessed). This axis takes ~2600 TLB misses,
  # so its runtime is dominated by the m8_runtime.inc miss handler and it is the
  # single most stop-time-sensitive guard in the suite. The old 600us was set
  # when the handler read PTEH/ASIDR/TSBPTR with register-only STC overlays and
  # the guard completed at 585.21us -- 2.5% of headroom, which was not a budget
  # so much as a coincidence. Phase 3 retired those STC forms in favour of the
  # P4 MMIO aliases, so each of the five reads became a PC-relative literal load
  # plus an MMIO load; the handler got ~4.7% more expensive and completion moved
  # to 612.79us, silently overrunning. That is a real and intended cost, not a
  # defect: nothing hangs and no assertion changed. 900us restores ~47% margin
  # (measured completion 612.79us) so the next handler change does not rediscover
  # this the hard way. Both figures are the final timestamp of an MMU_VCD dump,
  # which ends at the "Test Passed" exit. Wall budget raised to 240s to match.
  run_guard m8_dsdslot_0 "" 1100us 240
  # mmudspcprobe_late: ACTIVE since Defect 7 was fixed (decode/decode_core.vhm,
  # g_dslot -- see the writeup above). Built from mmudspcprobe.S (which pins the
  # slot-0 arm to exactness) with the delay-slot instruction swapped for
  # MOV.L @Rm+,Rn, so the faulting access launches in slot 1. That pairing is
  # the regression lock: mmudspcprobe holds the slot-0 arm, this one holds the
  # late-access arm, and the only variable between them is which slot carries
  # the access. Measured 0x00010101 (restart landed on the delay slot) before
  # the fix, PASS after.
  run_guard mmudspcprobe_late   cpu_tb 80us
  # ...and one guard per REMAINING late-access form. The fix is structural, but
  # "structural" is an argument, not a measurement: each form gets its own file
  # differing in exactly one instruction. All five were measured RED
  # (Result=65793 = 0x00010101) on the pre-fix RTL and GREEN after.
  run_guard mmudspcprobe_lateb  cpu_tb 80us    # MOV.B @Rm+,Rn
  run_guard mmudspcprobe_latew  cpu_tb 80us    # MOV.W @Rm+,Rn
  run_guard mmudspcprobe_latec  cpu_tb 80us    # CAS.L Rm,Rn,@R0  (locked RMW)
  run_guard mmudspcprobe_latem  cpu_tb 80us    # MAC.L @Rm+,@Rn+  (dual pointer)
  run_guard mmudspcprobe_latemw cpu_tb 80us    # MAC.W @Rm+,@Rn+  (dual pointer)
  # Task 14: is STC.L GBR,@-Rn restart-safe when planted in a branch delay
  # slot and its store faults? Modeled on mmudspcprobe_late.S but for a
  # pre-decrement STORE. Measured GREEN: Rn ends at initial-4 (decrement
  # applied exactly once) and the stored word matches the GBR sentinel.
  # Non-vacuity proven by mutating the expected delta to 8 (RED, code
  # 0x0BADB008) and reverting.
  run_guard mmustcldslot        cpu_tb 60us
  run_guard m8_macarith
  run_guard m8_macseq
  run_guard m8_ifetch_0 "" 12ms 240
  run_guard m8_ifetch_1 "" 12ms 240
  run_guard m8_ifetch_2 "" 12ms 240
  # m8_idslot_0-2: the I-side delay-slot sweep. UNPARKED 2026-08-06 -- these are
  # the regression lock for deferred I-fetch fault delivery. All three failed
  # (Result=2/25/49 -- restart landed on the delay slot, not the branch) on every earlier
  # tree and pass only now that the I-side restart PC is derived at DISPATCH from
  # the faulting instruction's own if_pc record; see if_fault in
  # core/components_pkg.vhd. Each was measured RED immediately before the fix, so
  # none can pass vacuously.
  run_guard m8_idslot_0 "" 400us
  run_guard m8_idslot_1 "" 400us
  run_guard m8_idslot_2 "" 400us
  # Genuine TLB MULTI_HIT reachability + the 30af728 restart-shadow guard
  # (I-side MULTI_HIT must not arm the D-side restore; D-side MULTI_HIT
  # still must). Measured completion ~3.95us (m8_pass.vcd); 100us margin.
  run_guard m8_multihit_ifetch "" 100us
  # Task #12 MEASUREMENT guard: an I-side MULTI_HIT belongs to an instruction
  # being FETCHED (younger than anything in EX/MA) yet rides the first-come
  # D-side held path. mmumhorder puts an older D-side DMISS_R in the delay slot
  # of the branch whose target multi-hits and separates the two possible
  # defects: Result=2 means the younger MULTI_HIT pre-empted the older fault
  # (ordering), Result=4 means the older delay-slot load was squashed and never
  # re-executed (lost instruction). See the file header before touching the RTL.
  run_guard mmumhorder "" 100us
  # Ordered delivery of an OLDER held D-side TLB fault against a YOUNGER
  # deferred I-fetch fault at the same dispatch boundary. Locks the
  # two decode_core terms -- texc_defer_cap_o's `texc_req = '0'` (delivery) and
  # the same term on next_op's if_fault arms (the older access is restarted):
  # against the pristine tree this guard reports Result=2, the older page fault
  # never delivered at all. All four checks are asserted, including that the
  # older access lands its value -- nothing is lost once delivery is ordered.
  run_guard mmuidorder "" 100us
  # COVERAGE for the walker's older-instruction-first ordering gate. Measured:
  # deleting `and sig_db_o.en = '0' and d_fault_held = '0'' from walk_i_miss in
  # core/cpu.vhd left EVERY ordering guard above green and fired
  # p_walk_order_assert in exactly one image -- m8_dsdslot_0, a generated
  # fault-permutation axis that crosses the window by accident. mmuwalkorderhit
  # builds the window on purpose: an older D access that HITS the TLB (so
  # walk_d_miss stays '0', which is what excludes mmuidorder/mmumhorder) live
  # on the bus while a younger delay-slot I-fetch misses. Read its header
  # before reshaping it.
  run_guard mmuwalkorderhit "" 100us
  # REGRESSION LOCK for the walker's per-REQUEST one-shot (e6ee313,
  # core/tlb_walk.vhd). One continuous `req' level spans a younger I-side fetch
  # miss that gives up and the OLDER instruction's D-side miss; keying `tried'
  # on the level denied that second miss a walk for a VA it was never tried
  # for. Invisible while LDTLB exists (software just installs the entry), so
  # this guard asserts WHO resolved it, not what came back: with the fix the
  # D side is walked and installed, takes no exception, and the only fault left
  # is the younger IMISS. Revert core/tlb_walk.vhd to e6ee313^ and it reports
  # Result=2 (DMISS_R -- the D-side walk was denied). Read its header.
  run_guard mmuwalkrearm "" 100us
  # TSB COHERENCY (R1). Software writes a TSB row over a different, valid entry
  # for the same VA with ordinary cacheable stores -- Linux's exact path -- and
  # the walker must install the row software LAST wrote. Run under BOTH tops on
  # purpose: only cpu_cache_tb puts a D-cache in the walker's path, and that is
  # the configuration whose routing R1 was about. Read its header before
  # reshaping it -- the window between the good store and the test load must
  # stay free of every cacheable data access, literal-pool loads included.
  run_guard mmutsbcoh "" 100us
  run_guard mmutsbcoh cpu_cache_tb 200us
fi

if [ "$fail" = 0 ]; then echo "==> all guards PASSED"; else echo "==> FAILURES above" >&2; exit 1; fi
