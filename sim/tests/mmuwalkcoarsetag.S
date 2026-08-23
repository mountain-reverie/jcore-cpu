! mmuwalkcoarsetag.S -- CONTRACT LOCK C1 (docs/mmu/pagemask-walker-contract.md
! sections 2/C1 and 7.2). Lane 1, cpu_tb.
!
! WHAT THIS LOCKS, AND WHAT IT DOES *NOT* TEST
! ============================================
! This is a GROUP-C guard: it PASSES on today's RTL and exists to turn RED if
! someone "fixes" the TSB tag defect the wrong way. It is not a reproducer for
! that defect -- the reproducers are the Group-B guards (mmupmsub4k / mmupmsubi
! / mmupmsubhuge), which live on the A1a and A1b branches.
!
! The contract's C1/C3 say: `tag_hi` is ALWAYS `VA_fault & 0xFFFF_F000` and the
! walker's compare is an EXACT 32-bit equality against `{VA_fault[31:12],12'b0}`
! -- no PageMask, no page-size field, no programmable shift, for EVERY page
! size. The tempting wrong fix (rejected alternatives (a) and (b) in section 3)
! is to make the walker mask its tag compare by the entry's page size so the
! kernel's existing `addr & PAGE_MASK` store starts matching again. That fix
! would make the anti-duplicate invariant C6 constructible and would let a
! stale coarse-tagged row hijack a fresh mapping.
!
! So this guard writes the row TODAY'S KERNEL WRITES -- a 16 KB-granular tag,
! `VA & ~0x3FFF` -- for a VA whose `VA[13:12]` is 01, and asserts THE WALKER
! REJECTS IT. A coarse tag is not a valid tag.
!
! PHASE STRUCTURE (the positive control is what makes the negative assertion
! mean something)
! ------------------------------------------------------------------------
!   Phase 1  row at set(0x00045000) carries tag_hi = 0x00044000 (coarse).
!            The load of VA 0x00045000 must MISS the walker and take the
!            DMISS_R exception. cnt_walks MUST advance (the walker really ran
!            and the counter really is live) while cnt_hits MUST NOT (no way
!            was accepted). That pairing is contract P1's "counter
!            trustworthiness" rule: a non-increment assertion alone is
!            satisfied by a DEAD counter, so it is paired with an increment
!            assertion in the SAME run. This guard therefore does NOT depend on
!            any Group-B guard for its non-vacuity, and P1g is not needed.
!   Phase 2  the handler rewrites the SAME row's tag_hi to the canonical
!            0x00045000 -- changing nothing else, not tag_lo, not data -- and
!            RTEs. The re-executed load must now resolve with NO exception, a
!            cnt_hits delta of +1, and the sentinel planted at the RELOCATED
!            physical address. Phase 2 is what proves phase 1's miss was caused
!            by the tag VALUE and not by a broken row, a broken set index, a
!            disabled MMU or a dead walker.
!
! IDENTITY MAPPING (jcore-cpu/CLAUDE.md "Never identity-map the page under
! test", sim/tests/README-identity-mapping.md)
! ------------------------------------------------------------------------
! The PAGE UNDER TEST IS NOT IDENTITY-MAPPED: VA 0x00044000 -> PA 0x00060000
! (pm=1, 16 KB), so the tested access VA 0x00045000 relocates to PA 0x00061000.
! PA 0x00061000 is seeded with the expected sentinel and PA 0x00045000 -- the
! address an UNTRANSLATED access would reach -- is seeded with a distinct
! poison word, so an inert MMU reads poison and fails check +7. The frame is
! movable by editing p_ptel_data alone; identity was not forced and was not
! used.
! The CODE page (VA 0x1000 -> PA 0x1000) *is* identity, forced by layout: the
! cosim loads the image flat, so the instruction stream's PA is fixed by the
! link. Category (b) of README-identity-mapping.md. Its witness is not needed
! for the property under test -- every assertion in this file is about the DATA
! page, which is non-identity, and about the walker counters.
!
! P5 (VA-backing, contract section 7.0): every VA dereferenced under AT=1 --
! 0x00045000, and the code page -- is inside the cosim's 16 MB backed window
! [0, 0x0100_0000). Phase 1 deliberately MISSES, so the raw VA 0x00045000 is
! driven onto the data bus during the miss window; it is backed.
!
! RESULT CODES (base 0x10; the sibling mmuwalktagmbz uses base 0x20)
!   0x11  phase 1: NO exception at all -- the walker ACCEPTED the coarse tag.
!                  THIS IS THE MUTATION CODE.
!   0x12  phase 1: EXPEVT is not DMISS_R (0x60)
!   0x13  phase 1: TEA is not the faulting VA
!   0x14  phase 1: cnt_hits MOVED -- some way was accepted
!   0x15  phase 1: cnt_walks did NOT move -- no walk happened, or the counter
!                  is dead (anti-vacuity; see the phase note above)
!   0x16  phase 2: a SECOND fault -- the canonical tag was rejected too
!   0x17  phase 2: wrong data -- translation absent or wrong (this is the
!                  check an identity mapping would have made vacuous)
!   0x18  phase 2: cnt_hits did not move -- phase 2 was not resolved by a walk
!   0xE5  phase 1 TRIP: the bounded fault counter passed 2. Contract P2's trip
!         band is `0xE0 | phase`; this guard's data codes (0x11..) are too wide
!         to embed, so it allocates from the documented fallback range
!         phase = 5..10: PHASE 1 -> 0xE5, PHASE 2 -> 0xE6.
!   0xD1  an unexpected GENERAL exception (VBR+0x100) fired
!
! MUTATION EVIDENCE
! =================
!   (filled in by the mutation runs -- see the block at the end of this header)
!
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

! ---- Parameters. mmuwalktagmbz.S #defines these and #includes this file. ----
#ifndef CTAG_BASE
#define CTAG_BASE  0x10
#define CTAG_TRIP1 0xE5
#define CTAG_BADTAG 0x00044000
#endif

#define C_NOEXC   (CTAG_BASE + 1)
#define C_EXPEVT  (CTAG_BASE + 2)
#define C_TEA     (CTAG_BASE + 3)
#define C_HITMOVE (CTAG_BASE + 4)
#define C_NOWALK  (CTAG_BASE + 5)
#define C_REFAULT (CTAG_BASE + 6)
#define C_DATA    (CTAG_BASE + 7)
#define C_NOHIT2  (CTAG_BASE + 8)

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

        ! ---- Ensure RB=0 (bank 0). core/cpu.vhd's walk_req is gated on
        ! ---- dp_sr.rb = '0' and the cosim starts in bank 1, so without this
        ! ---- nothing ever walks and the failure is silent.
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_gen - 0x100, so VBR+0x100 is the general stub and
        ! ---- VBR+0x400 is the TLB-miss stub (see the vector block below).
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR  (0100 nnnn 0010 1110)

        ! ---- Seed physical memory, AT off, untranslated P0 stores.
        ! ----   PA 0x00061000 : the RELOCATED address the mapping produces
        ! ----   PA 0x00045000 : the address an UNTRANSLATED access reaches
        mov.l   p_pa_relocated, r2
        mov.l   p_expect, r3
        mov.l   r3, @r2
        mov.l   p_pa_raw, r2
        mov.l   p_poison, r3
        mov.l   r3, @r2

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR  = 0x00010006
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG = 0x00000061

        ! ---- ASIDR = 0 (both rows are written under it, and the walker
        ! ---- compares tag_lo against the live ASIDR).
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR (0100 nnnn 0111 1110)
        nop
        nop

        ! ---- Code page: VA = PA = `start`, 4 KB, GLOBAL, U=0 (SMEP), written
        ! ---- to WAY 1 so it can never collide with the data row in way 0.
        ! ---- Set address from the P4 slot helper, never hand-computed.
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- The row under test, WAY 0 of the set the HARDWARE computes for
        ! ---- the faulting VA 0x00045000 -- that is where the kernel's
        ! ---- jcore_read_tsbptr() path puts it too. Only the TAG is wrong:
        ! ---- tag_hi = VA & ~0x3FFF (C1) or VA | 0x001 (C2, the MBZ lock).
        mov.l   p_testva, r6            ! the VA whose SET we want
        mov.l   r6, @r12
        mov.l   @r12, r10               ! set(0x00045000)
        mov.l   p_badtag, r1            ! the DELIBERATELY WRONG tag_hi
        mov     #0, r7                  ! tag_lo = ASID 0 (correct)
        mov.l   p_ptel_data, r8         ! data = PTEL, pm=1, V=1, STALE=0
        tsb_fill r10, r1, r7, r8

        mov     #0, r10                 ! r10 = fault count (unbanked)
        bra     _run
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_gen - 0x100
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD ! identity code page, U=0 (SMEP), G=1
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_testva:       .long 0x00045000        ! VA[13:12] = 01 -- a NON-base sub-page
p_badtag:       .long CTAG_BADTAG
p_ptel_data:    .long 0x000601E9        ! PA 0x00060000, pm=1 (16 KB), W|X|U|C|V
p_pa_relocated: .long 0x00061000        ! 0x00060000 | (0x00045000 & 0x3FFF)
p_pa_raw:       .long 0x00045000
p_expect:       .long 0xC0A45E17
p_poison:       .long 0xDEAD0BAD

ENTRY(_run)
        ! ---- Enable AT. ----
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        nop
        nop
        nop
        nop

        ! ---- Warm the DTLB for the CODE page. The walker installs into the
        ! ---- faulting side's array only, so the I-side fetch that resolved
        ! ---- the code page did NOT populate the DTLB; the first literal-pool
        ! ---- load under AT still walks. Doing it HERE keeps that walk out of
        ! ---- the phase-1 delta below, which has to be exact.
        mov.l   q_warm, r11

        ! ---- Snapshot P4_TSBCNT immediately BEFORE the access under test.
        ! ---- [31:16] = cnt_walks, [15:0] = cnt_hits. Taking it before (not
        ! ---- after) is what attributes the delta to THIS access -- contract
        ! ---- P1, "prefer the stronger form".
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13

        ! ---- PHASE 1: the access. The row exists, is valid, has the right
        ! ---- tag_lo and the right data -- ONLY its tag_hi is coarse. The
        ! ---- walker must reject it and the miss exception must fire.
        mov.l   q_testva, r0
        mov.l   @r0, r4                 ! <-- must FAULT

        ! ---- Control rejoins here TWICE over the run: once when phase 1's
        ! ---- access completes without faulting (the failure this guard is
        ! ---- named for), and once after the handler's RTE has restarted the
        ! ---- same instruction in phase 2. r10, the fault counter, is what
        ! ---- separates them -- there is no other way to tell, because RTE
        ! ---- resumes at the faulting instruction, not past it.
        mov     r10, r0
        tst     r0, r0
        bf      _p2_check               ! r10 != 0 -> we came back through the
                                        ! handler, so phase 1 DID fault
        mov     #C_NOEXC, r9            ! r10 == 0 -> the coarse tag was taken
        bra     _fail_at
        nop

        ! ================= PHASE 2 checks ==================
_p2_check:
        ! r4 = the value the re-executed load returned.
        mov.l   q_expect, r0
        cmp/eq  r4, r0
        mov     #C_DATA, r9
        bf      _fail_at

        ! exactly ONE fault in the whole run
        mov     r10, r0
        cmp/eq  #1, r0
        mov     #C_REFAULT, r9
        bf      _fail_at

        ! cnt_hits must have advanced past the snapshot the handler took
        ! after it repaired the tag: phase 2 was resolved BY THE WALKER.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        mov     r12, r2
        extu.w  r2, r2
        cmp/eq  r1, r2
        mov     #C_NOHIT2, r9
        bt      _fail_at

        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        bra     _done
        nop

_fail_at:
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off before reporting
        bra     _fail
        nop

        .align 2
q_mmucr:        .long 0xFF000010
q_warm:         .long 0x00000000
q_walkcnt:      .long 0xFF000054        ! [31:16]=cnt_walks [15:0]=cnt_hits
q_testva:       .long 0x00045000
q_expect:       .long 0xC0A45E17

#else
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS
        bf      1f                      ! token, so _fail must never write it.
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ================================================================
        ! Vector block. VBR = _v_gen - 0x100, so
        !   _v_gen          = VBR + 0x100  general / illegal / protection
        !   _v_gen + 0x300  = VBR + 0x400  TLB miss
        ! ================================================================
        .balign 0x100
_v_gen:
        mov.l   Hg_code, r9
        bra     _fail
        nop
        .align 2
Hg_code:        .long 0x000000D1

        .space  0x300 - (. - _v_gen)
_v_fault:                               ! = VBR + 0x400
        add     #1, r10                 ! bounded fault counter (unbanked)
        mov     r10, r0
        cmp/eq  #1, r0
        bt      _p1_handle
        mov     r10, r0
        cmp/eq  #2, r0
        bt      _p2_unexpected
        mov.l   H_trip1, r9             ! >2 faults: TRIP, do not spin forever
        bra     _fail_at
        nop

_p2_unexpected:
        mov     #C_REFAULT, r9          ! the canonical tag was rejected too
        bra     _fail_at
        nop

_p1_handle:
        ! ---- EXPEVT must be DMISS_R.
        mov.l   H_expevt, r0
        mov.l   @r0, r1
        mov.l   H_dmiss_r, r2
        cmp/eq  r1, r2
        mov     #C_EXPEVT, r9
        bf      _fail_at

        ! ---- TEA must be the faulting VA.
        mov.l   H_tea, r0
        mov.l   @r0, r1
        mov.l   H_testva, r2
        cmp/eq  r1, r2
        mov     #C_TEA, r9
        bf      _fail_at

        ! ---- The counter pair. r13 was snapshotted immediately before the
        ! ---- access, so both deltas belong to THIS access.
        mov.l   H_walkcnt, r0
        mov.l   @r0, r11

        ! cnt_hits MUST NOT have moved: no way may be accepted.
        mov     r11, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        cmp/eq  r1, r2
        mov     #C_HITMOVE, r9
        bf      _fail_at

        ! cnt_walks MUST have moved. This is the increment half of contract
        ! P1's pairing rule -- without it a DEAD counter would satisfy the
        ! cnt_hits check above and the guard would prove nothing.
        mov     r11, r1
        shlr16  r1
        mov     r13, r2
        shlr16  r2
        cmp/eq  r1, r2
        mov     #C_NOWALK, r9
        bt      _fail_at

        ! ---- Repair ONLY tag_hi, to the canonical VA & 0xFFFFF000. tag_lo
        ! ---- and data are untouched, so phase 2 differs from phase 1 in
        ! ---- exactly one word -- and in exactly the bits C1 is about.
        ! ---- AT is switched off first: the TSB lives at PA 0x00010000, a P0
        ! ---- address with no mapping, so a translated store would double-fault.
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov.l   H_tsbslot, r3
        mov.l   H_testva, r6
        mov.l   r6, @r3
        mov.l   @r3, r5                 ! set(0x00045000)
        mov.l   r6, @r5                 ! tag_hi = 0x00045000 (canonical)
        mov.l   H_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on

        ! ---- Fresh snapshot for the phase-2 delta, taken BEFORE the
        ! ---- re-executed access (which RTE is about to restart).
        mov.l   H_walkcnt, r0
        mov.l   @r0, r12

        ! ---- Return to the faulting instruction. It re-executes; this time
        ! ---- the walker must hit. Nothing else in the machine changed.
        rte
        nop

        .align 2
H_trip1:        .long CTAG_TRIP1
H_expevt:       .long 0xFF000024
H_dmiss_r:      .long 0x00000060
H_tea:          .long 0xFF00000C
H_testva:       .long 0x00045000
H_walkcnt:      .long 0xFF000054
H_mmucr:        .long 0xFF000010
H_tsbslot:      .long 0xFF000048

        ! Force .text to 4 KB alignment so `start` lands at VA 0x1000 and the
        ! whole guard -- code, literal pools and vectors -- lives in the ONE
        ! 4 KB code page mapped above. The pad page keeps the image clear of
        ! the TSB at PA 0x00010000.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
