! pmuovf.S -- PMCR.EN freezes, counters are writable, and PMOVF is a sticky
! per-counter write-1-to-clear wrap flag.
!
! THE DEFECT THIS EXISTS TO PREVENT. The counters this block replaces were
! 16-bit `walks_r <= walks_r + 1` with plain silent wrap: a sampling reader
! could not tell one wrap from two, so the pair could witness "a walk happened"
! and nothing more. Width alone does not fix that -- it only moves the wrap
! period. What fixes it is that the reader can DETECT a wrap, and that is what
! PMOVF is for. A flag nobody has ever seen set is not a flag, so this guard
! drives a real 32-bit wrap and observes it.
!
! IT IS ONLY TESTABLE BECAUSE THE COUNTERS ARE WRITABLE. Reaching a 32-bit
! wrap by counting takes 2^32 cycles, which no simulation stop-time will ever
! cover. Preloading PMCYC to 0xFFFFFFFE reaches it in three. That is the
! decisive argument for the writable counter port in core/datapath.vhm, over
! and above Linux perf wanting it to program a sampling period.
!
! PMWLK is used as the writability witness rather than PMCYC because it is
! QUIESCENT here: this guard never enables MMUCR.AT, so no TLB miss occurs, no
! walk is armed, and the counter cannot move between the write and the
! read-back. A read-back check on a running counter would be a race.
!
! Result codes (r9):
!   0x01  PMWLK did not read back the value written to it
!   0x10  PMCR.EN = 0 did not freeze PMCYC -- two reads across 8 nops differed
!   0x11  PMCR.EN = 1 did not resume PMCYC -- two reads across 8 nops matched
!   0x20  writing 0xFFFFFFFF to PMOVF did not clear it
!   0x21  PMCYC did not read back the value written while frozen
!   0x22  PMOVF after the wrap is not EXACTLY 0x00000001 -- either the wrap was
!         not flagged, or the flag is global rather than per-counter
!   0x23  PMCYC did not wrap -- it saturated, or it is not counting
!   0x30  writing 0 to PMOVF cleared a set bit: it is not write-1-to-clear
!   0x40  the REFERENCE sweep saw no wrap at all -- reserved anti-vacuity: the
!         coincidence phase below cannot observe anything, so its comparison
!         would pass on a block that never overflows
!   0x41  a wrap that the reference sweep recorded was LOST when the same cycle
!         carried a PMOVF write-1-to-clear. The clear is overriding a coincident
!         wrap instead of the wrap overriding the clear
!   0x31  writing 1 to PMOVF did not clear the bit
!
! No MMU translation is set up and none is needed (P4 is untranslated), so the
! repo's no-identity-mapping rule is not engaged -- there is no mapping here.
#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define O_PMCR   0
#define O_PMOVF  4
#define O_PMIDR  8
#define O_PMCYC  32
#define O_PMWLK  56
#define SWEEP_N  16

        .macro  NOP8
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        .endm

        .section .vect
        .long start
        .long 0x00007000
        .long start
        .long 0x00007000
        .rept 60
        .long 0
        .endr
        .long SIM_INSTR_MAGIC
        .long _sim_instr_end
        .long _done
        .long _fail
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
ENTRY(start)
#if CONFIG_PRIV_ARCH

        mov.l   p_pmubase, r8

        ! ================= 1: counters are writable =======================
        mov.l   p_pat, r1               ! 0x12345678
        mov.l   r1, @(O_PMWLK,r8)
        mov.l   @(O_PMWLK,r8), r2
        cmp/eq  r1, r2
        mov     #0x01, r9
        bf      _fail

        ! ================= 2: PMCR.EN freezes and resumes =================
        ! EQUALITY, not "moved less": a frozen counter must not advance by ONE.
        ! This is also what makes a coherent multi-counter snapshot possible --
        ! see docs/pmu/perf-counters.md on why EN exists to freeze rather than
        ! to arm.
        mov     #0, r1
        mov.l   r1, @(O_PMCR,r8)
        mov.l   @(O_PMCYC,r8), r1
        NOP8
        mov.l   @(O_PMCYC,r8), r2
        cmp/eq  r1, r2
        mov     #0x10, r9
        bf      _fail

        mov     #1, r1
        mov.l   r1, @(O_PMCR,r8)
        mov.l   @(O_PMCYC,r8), r1
        NOP8
        mov.l   @(O_PMCYC,r8), r2
        cmp/eq  r1, r2
        mov     #0x11, r9
        bt      _fail                   ! equal here means it never resumed

        ! ================= 3: drive a real 32-bit wrap ====================
        mov     #0, r1
        mov.l   r1, @(O_PMCR,r8)        ! freeze while arming
        mov.l   p_all1, r1              ! clear EVERY overflow bit (W1C)
        mov.l   r1, @(O_PMOVF,r8)
        mov.l   @(O_PMOVF,r8), r1
        tst     r1, r1
        mov     #0x20, r9
        bf      _fail

        mov.l   p_near, r1              ! 0xFFFFFFFE, two counts from the wrap
        mov.l   r1, @(O_PMCYC,r8)
        mov.l   @(O_PMCYC,r8), r2
        cmp/eq  r1, r2
        mov     #0x21, r9
        bf      _fail

        mov     #1, r1
        mov.l   r1, @(O_PMCR,r8)        ! run: PMCYC crosses 0xFFFFFFFF
        NOP8
        mov     #0, r1
        mov.l   r1, @(O_PMCR,r8)        ! freeze so the checks below are stable

        ! PMOVF must be EXACTLY 0x00000001. Not "bit 0 is set" -- the whole
        ! word, because that simultaneously asserts that the flag is PER
        ! COUNTER: nothing else wrapped, so no other bit may be set. A global
        ! "some counter overflowed" bit would pass a masked test and fail this.
        mov.l   @(O_PMOVF,r8), r1
        mov     #1, r0
        cmp/eq  r0, r1
        mov     #0x22, r9
        bf      _fail

        ! And the counter must have WRAPPED, not saturated: it is now a small
        ! number, not 0xFFFFFFFF. Saturation would be the wrong fix -- see
        ! docs/pmu/perf-counters.md: once a saturating counter is pinned the
        ! reader learns nothing more, whereas a wrapping counter plus modular
        ! arithmetic reconstructs the total exactly.
        mov.l   @(O_PMCYC,r8), r1
        mov.l   p_lim, r2               ! 0x00001000
        cmp/hs  r2, r1                  ! T = (PMCYC >= 0x1000) unsigned
        mov     #0x23, r9
        bt      _fail

        ! ================= 4: PMOVF is WRITE-1-to-clear ===================
        mov     #0, r1
        mov.l   r1, @(O_PMOVF,r8)       ! a write of 0 must clear NOTHING
        mov.l   @(O_PMOVF,r8), r1
        mov     #1, r0
        cmp/eq  r0, r1
        mov     #0x30, r9
        bf      _fail

        mov     #1, r1
        mov.l   r1, @(O_PMOVF,r8)       ! a write of 1 must clear bit 0
        mov.l   @(O_PMOVF,r8), r1
        tst     r1, r1
        mov     #0x31, r9
        bf      _fail

        ! ============ 5: a coincident wrap must SURVIVE the W1C ==========
        ! WHY CHECKS 0x20-0x31 ABOVE CANNOT SEE THIS. Every one of them does
        ! its PMOVF write with PMCR.EN already cleared -- section 3 freezes so
        ! its reads are stable -- and no counter can wrap while frozen. So they
        ! verify write-1-to-clear as a STATIC property of the register and are
        ! completely blind to the ordering between a clear and a simultaneous
        ! wrap. That blindness is not hypothetical: this guard passed under BOTH
        ! orderings until this phase was added, including against RTL that lost
        ! the coincident wrap outright.
        !
        ! THE CONSTRUCTION. With EN set, PMCYC increments every cycle, so
        ! preloading it to 0xFFFFFFFF - m puts its wrap exactly m + 1 cycles
        ! after the store that re-enables counting. Sweeping m therefore walks
        ! the wrap across the cycles around the following store, and one value
        ! of m lands it exactly ON that store.
        !
        ! THE ASSERTION IS A COMPARISON, NOT A PINNED BITMAP. The sweep is run
        ! twice with byte-identical code, differing only in the ADDRESS held in
        ! r14 for one store:
        !     pass A  r14 = PMOVF          -> the store is a write-1-to-clear
        !     pass B  r14 = 0xFF001100     -> an undecoded PMU offset; the store
        !                                     is discarded, so nothing clears
        ! Pass B records which m values produce an observable wrap at all --
        ! that is, the window in which the wrap happens before the freeze. Pass
        ! A must record exactly the same set: issuing a W1C must not lose a wrap
        ! that had not already been reported. Equality, so there is no measured
        ! constant here and a pipeline change cannot silently invalidate it.
        !
        ! IF THIS PHASE EVER FAILS BECAUSE THE STORE MOVED, THAT IS THE RIGHT
        ! FAILURE. The comparison is only meaningful while the clearing store
        ! sits on the earliest cycle a wrap can occupy; if a pipeline change
        ! moves it later, some wrap becomes legitimately older than the clear,
        ! the two passes diverge, and the guard says so instead of quietly
        ! losing its power. Re-derive the alignment; do not weaken the check.
        mov.l   p_all1, r12             ! 0xFFFFFFFF, live across both sweeps
        mov.l   p_pmovf_a, r14          ! pass A: the real W1C target
        bsr     Lsweep
        nop
        mov     r10, r5                 ! r5 = survival bitmap WITH the clear

        mov.l   p_undec_a, r14          ! pass B: an undecoded offset
        bsr     Lsweep
        nop
        mov     r10, r6                 ! r6 = wraps observable at all

        tst     r6, r6                  ! reserved anti-vacuity
        mov     #0x40, r9
        bt      _fail

        cmp/eq  r5, r6
        mov     #0x41, r9
        bf      _fail

        ! Leave the block counting, as reset does.
        mov     #1, r1
        mov.l   r1, @(O_PMCR,r8)

        mov     #0, r9
        bra     _done
        nop

        bra     Lafter_sweep
        nop

        ! ---- Lsweep: r14 = address of the store under test, returns the
        ! ---- survival bitmap in r10 (bit SWEEP_N-1 = m 0, descending).
        ! Every instruction between the enabling store and the freezing store
        ! is fixed, so the only thing that varies across the sweep is where the
        ! wrap falls -- and the only thing that differs between the two passes
        ! is r14.
        .align 2
Lsweep:
        mov     #0, r10                 ! bitmap
        mov     #0, r13                 ! m
        mov     #SWEEP_N, r7
Ls_loop:
        mov     #0, r1
        mov.l   r1, @(O_PMCR,r8)        ! freeze while arming
        mov.l   r12, @(O_PMOVF,r8)      ! clear every overflow bit
        mov     r12, r1
        sub     r13, r1                 ! 0xFFFFFFFF - m
        mov.l   r1, @(O_PMCYC,r8)       ! preload: wrap lands m+1 cycles on
        mov     #1, r1
        mov.l   r1, @(O_PMCR,r8)        ! resume -- counters live from here
        mov.l   r12, @r14               ! THE STORE UNDER TEST
        mov     #0, r1
        mov.l   r1, @(O_PMCR,r8)        ! freeze so the read below is stable
        mov.l   @(O_PMOVF,r8), r1
        mov     r1, r0
        and     #1, r0                  ! did PMCYC's wrap survive?
        shll    r10
        or      r0, r10
        add     #1, r13
        cmp/eq  r13, r7
        bf      Ls_loop
        rts
        nop
Lafter_sweep:

        .align 2
p_pmovf_a: .long 0xFF001004             ! PMOVF, the real W1C target
p_undec_a: .long 0xFF001100             ! undecoded in-page offset (pmucnt 0x03)
p_pmubase: .long 0xFF001000
p_pat:     .long 0x12345678
p_all1:    .long 0xFFFFFFFF
p_near:    .long 0xFFFFFFFE
p_lim:     .long 0x00001000
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: never write the PASS
        bf      1f                      ! token from the failure path.
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC
