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
    echo "$out" | grep -iE 'result|fail|invalid' | tail -3
    fail=1
  fi
}

if [ $# -ge 1 ]; then
  # Single guard. Default the top + stop-time for the known cache/long guards.
  name="$1"; top="${2:-}"; stop="${3:-}"
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
    m8_dside)   stop="${stop:-200us}" ;;
    m8_ifetch_*) stop="${stop:-12ms}" ;;
  esac
  run_guard "$name" "$top" "${stop:-80us}" "${4:-240}"
else
  echo "== priv-arch + MMU guards (cpu_tb) =="
  for t in exctest trapatest pm3vec pm3guard privmode banktest excguard \
           rteredir mmureg mmuguard mmuxlate mmurte mmustore mmuimiss mmuimiss_illegal \
           mmusr mmufault mmufsr mmudslot mmuidslot mmuldtlbr mmutsb mmuidx mmustres mmustr2 mmuimissrest mmushadowld mmushadowst mmurestartpc \
           mmustale mmuasid mmuglobal mmumultihit mmudblflt mmunest_trapa mmunest_slotill mmunest mmuremap mmucmpcsr mmurun mmuirun mmuainc mmuainc2 mmusmep j4_illegal_trap; do
    run_guard "$t"
  done
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
#   m8_idslot_0   Test failed. Result=2
#   m8_idslot_1   Test failed. Result=2
#   m8_idslot_2   Test failed. Result=2
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
# comment there, which is NOT Defect 7. Per the same-shaped emitIFetchDSlot
# convergent-target flaw noted below, m8_idslot_* likely share that vacuity as
# a SEPARATE, still-uninvestigated defect, so their bus-ACK-hang failures above
# may currently be masking it too; not invoked below until diagnosed.
#
# m8_smoke passes and is wired into the run below. Fixing m8_idslot_* is its
# own piece of work; until then m8_idslot_* stays out, and this comment is the
# reason why.
  run_guard m8_smoke
  run_guard m8_dside    "" 200us
  # m8_dsdslot_0: PARKED on Case A Result=1008 (case 8 = MOV.B @(disp,Rm),R0 --
  # a plain SLOT-0 access, and NOT Defect 7, which is now fixed anyway).
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
  # ---- ROOT CAUSE FOUND 2026-08-06 (fix NOT yet landed) ----------------
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
  #   if MMU_ARCH and this.sr.rb = '1' then this.tlb_exc_captured := '0';
  # turns case 1 RED (Result=1001) and does so even with CAS.L skipped, so it is
  # not CAS-specific. "Keep the FIRST episode" is therefore just as wrong as
  # "keep the last": within a single dispatched fault there can be several
  # tlb_exc_pend episodes, and a later one can carry the correct VA -- see the
  # existing first-cycle-capture comment in datapath.vhm about the I-fetch
  # stream advancing a word while an IMISS persists. Only texc_ack marks the
  # boundary that actually matters.
  # run_guard m8_dsdslot_0 "" 200us
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
  run_guard m8_macarith
  run_guard m8_macseq
  run_guard m8_ifetch_0 "" 12ms 240
  run_guard m8_ifetch_1 "" 12ms 240
  run_guard m8_ifetch_2 "" 12ms 240
  # Genuine TLB MULTI_HIT reachability + the 30af728 restart-shadow guard
  # (I-side MULTI_HIT must not arm the D-side restore; D-side MULTI_HIT
  # still must). Measured completion ~3.95us (m8_pass.vcd); 100us margin.
  run_guard m8_multihit_ifetch "" 100us
fi

if [ "$fail" = 0 ]; then echo "==> all guards PASSED"; else echo "==> FAILURES above" >&2; exit 1; fi
