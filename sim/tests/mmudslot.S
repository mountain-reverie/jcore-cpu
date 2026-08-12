! mmudslot.S -- DMISS in a branch delay slot must restart at the BRANCH,
! not the delay-slot instruction (J4).
!
! Repro for the handover finding "MMU data-access fault in a branch delay slot
! restarts the delay slot, not the branch"
! (docs/superpowers/handover-mmu-delay-slot-data-fault.md).
!
! Scenario:
!   mov.l  c_page1_va, r2      ! r2 = 0x1000 (page 1, NOT in TLB)
!   bra    taken_target        ! branch executes
!   mov.l  @r2, r3             ! DELAY SLOT: load DMISSes (page 1 unmapped)
!
! The DMISS_R handler installs a full-access mapping for page 1 and RTEs to the
! hardware-saved SPC WITHOUT overriding it (a realistic page-fault handler).
! The re-executed load now succeeds; where control lands afterwards is the test:
!
!   CORRECT: SPC = branch PC  -> branch re-issues its delay slot -> taken_target -> PASS (0)
!   BUGGY  : SPC = delay-slot PC -> load re-executes, then falls THROUGH the
!            (already-executed) branch -> fall-through path -> FAIL (2)
!
! VBR layout: VBR = _v_load - 0x400 so VBR+0x400 = _v_load (D-load handler).
!
! Result codes:
!   0  PASS  (branch taken after fault serviced)
!   1  no exception fired (page 1 was reachable without faulting -- setup bug)
!   2  FAIL  (fell through the branch -- the handover bug)
!   3  the delay-slot load was SKIPPED on the restart (r3 kept its sentinel)
!   4  the handler did not service EXACTLY ONE fault -- 0 means the delay-slot
!      access never missed, so the scenario was never constructed at all; >1
!      means the handler failed to make progress
!
! J4 overlay opcodes:
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E

!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS. Since the per-sub-test fail-code globals
! start at 0 until a sub-test sets them, a fault reaching _fail BEFORE the first
! sub-test runs would otherwise silently report PASS. _fail now clamps r9==0 to
! 0x7F before the store so 0 can never leave through the fail path. Fail-code
! globals below use loud sentinels (_g_exp_* = 0xFFFFFFFF, _g_bad_* = small
! distinct values) so an early exit still names its cause.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_load - 0x400 (so VBR+0x400 = _v_load). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB: base 0x00004000, TSB_SIZE_LOG=6 (64 sets x
        ! ---- 32 bytes = 0x4000..0x47FF), HASH_SHIFT=6, HASH_MODE=1. Clear of
        ! ---- page 0 and the fault page at 0x1000. Zero-filled image, so the
        ! ---- fill below is the only thing that populates it. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Map page 0 (VA 0x0000-0x0FFF) identity, W|X|C|G|V, U=0 (SMEP).
        ! ---- This used to be an LDTLB; it is now a TSB row the walker pulls in
        ! ---- on demand -- I-side on the first fetch after AT goes on, D-side on
        ! ---- the first literal load. GLOBAL, so no ASID change perturbs it.
        ! ---- The set address is asked of the P4 slot helper (0xFF000048). ----
        mov.l   p_tsbslot_reg, r12
        mov     #0, r6                  ! VA 0x00000000
        mov     #0, r7                  ! ASID 0
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_page0, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ==============================================================
        ! The faulting delay slot.
        ! ==============================================================
        ! NOTE the `bra` below is UNCONDITIONAL, so both the faulting and the
        ! non-faulting case land on taken_target. Result 1 therefore cannot be
        ! reached by falling through, and until this was fixed nothing in the
        ! guard checked that the delay-slot access faulted AT ALL: pointing it
        ! at a mapped VA still passed (measured, on the pre-migration file too).
        ! The handler now counts its entries and taken_target requires exactly
        ! one, which is a positive witness rather than an absence.
        mov     #0x5A, r3               ! sentinel: delay-slot load must overwrite this with 0
        mov.l   c_page1_va, r2          ! r2 = 0x1000 (page 1, unmapped)
        bra     taken_target
        mov.l   @r2, r3                 ! DELAY SLOT: DMISS_R -> _v_load (loads 0 from page 1)

        ! Fall-through path (BUGGY landing): branch was skipped.
        mov     #2, r9
        bra     _fail
        nop

ENTRY(taken_target)
        ! CORRECT landing: branch was taken after the fault was serviced.
        ! Also verify the delay-slot LOAD actually executed: r3 must be 0 (loaded
        ! from zero-filled page 1), not the 0x5A sentinel. If r3==0x5A the delay
        ! slot was SKIPPED on the restart -> result 3.
        mov     #0x5A, r0
        cmp/eq  r0, r3
        bt      _dslot_skipped
        ! Exactly one fault must have been serviced. Zero means the delay-slot
        ! access never missed (the scenario was not constructed); more than one
        ! means the handler failed to make progress.
        mov.l   c_fcount_p, r0
        mov.l   @r0, r0
        mov     #1, r1
        cmp/eq  r1, r0
        bf      _bad_fault_count
        mov     #0, r9
        bra     _done
        nop
_bad_fault_count:
        mov     #4, r9
        bra     _fail
        nop
_dslot_skipped:
        mov     #3, r9
        bra     _fail
        nop

        ! ============================================================
        ! Literals.
        ! ============================================================
        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000CD        ! identity PPN 0 | W|X|C|G|V, U=0
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00004006        ! base=0x00004000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
c_page1_va:     .long 0x00001000
c_fcount_p:     .long _g_fault_count

#endif  ! CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS
p_test_result_pass:  .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ================================================================
        ! DMISS_R / DPROT_R handler at VBR+0x400 = _v_load.
        ! Installs a full-access mapping for page 1 and RTEs to the
        ! hardware-saved SPC (NO manual SPC override).
        ! ================================================================
        .balign 4
_v_load:                                ! = VBR + 0x400
        ! The handler no longer ends in LDTLB. It writes page 1's TSB ROW and
        ! RTEs; the restarted access re-walks, hits that row, and the walker
        ! installs it -- into the DTLB for a data access and the ITLB for a
        ! fetch, by side. The fault train is unchanged: still exactly one fault
        ! for page 1's first touch. AT is still ON in here, so the TSB write
        ! must go through the P1 alias (0x8xxxxxxx), which bypasses the MMU;
        ! a P0 store would itself fault on the unmapped TSB page.
        mov.l   Hpteh1, r1              ! r1 = VA 0x00001000 (page 1 base)
        mov.l   Hslot, r2
        mov.l   r1, @r2                 ! ask the P4 helper for this VA's set
        mov.l   @r2, r2
        mov.l   Hp1, r0
        or      r0, r2                  ! P1 alias -- untranslated
        mov.l   Hptel1, r3
        mov     #0, r0                  ! ASID_TAG = 0
        tsb_fill r2, r1, r0, r3
        ! Non-vacuity: count this fault. taken_target requires exactly one.
        ! The TSB row above is already committed, so this store is ordinary
        ! P1-alias scratch and cannot perturb the walk.
        mov.l   Hfcount, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        rte                             ! PC <- SPC (hardware value)
        nop

        .balign 4
Hpteh1:         .long 0x00001000        ! VPN = 1
Hptel1:         .long 0x000010E9        ! PA 0x1000 (identity) | W|X|U|C|V
Hslot:          .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
Hp1:            .long 0x80000000        ! P1 alias -- TSB writes bypass the MMU
Hfcount:        .long 0x80000000 + _g_fault_count

        ! ================================================================
        ! Fault-page padding: VA 0x1000-0x1FFF (page 1, zero-filled so the
        ! bus does not fault before the TLB exception fires).
        ! ================================================================
        .balign 4
_g_fault_count: .long 0

        .balign 4
_fault_pages:
        .space 0x4000, 0

#endif  ! CONFIG_PRIV_ARCH
