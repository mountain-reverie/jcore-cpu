! mmurte.S -- minimal RED guard for the RTE-redirect-after-TLB-exception defect.
!
! Reproduces, in isolation, the CPU defect proven in
! .superpowers/sdd/mmufault-regression-investigation.md: after a hardware-
! injected TLB exception entry, a handler RTE must redirect PC to SPC. The
! IDENTICAL LDC r0,SPC + rte idiom is known-good after a General/privilege
! exception (exctest.S), so this test isolates the TLB-entry-specific defect.
!
! Flow:
!   - map page 0 identity (W|X|U|C), enable AT
!   - load from VA 0x1000 (page 1, unmapped) -> DMISS_R TLB exception
!   - handler: disable AT, set SPC = _resume, RTE
!   - if RTE redirects (correct): _resume runs -> result 0 (PASS)
!   - if RTE falls through (defect): lands on `bra _fail` -> result 1 (FAIL)
!
! VBR = _v_load - 0x420 so the DMISS_R vector (VBR+0x420) hits _v_load.

#include "sim_instr.h"
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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_load - 0x420 (so VBR+0x420 = _v_load). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Take a DMISS_R: load from VA 0x1000 (page 1, unmapped). ----
        mov     #1, r9                  ! sentinel: if no fault, fail code 1
        mov.l   c_page1_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (VBR+0x420), DMISS_R

        ! If RTE redirects correctly, we never reach here (we land on _resume).
        bra     _fail
        nop

ENTRY(_resume)
        ! RTE redirected correctly: write result 0 (PASS) directly. AT is off
        ! (the handler disabled it) so this P-region store is reliable.
        mov.l   pr_test_result, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _resume
        nop
        .align 2
pr_test_result: .long TEST_RESULT_ADDRESS

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x420
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000E8
c_page1_va:     .long 0x00001000

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- DMISS_R handler at VBR+0x420 ----
        ! Pad so _v_load lands at >= 0x420 (so VBR = _v_load-0x420 is positive
        ! and the handler sits clear of page 0's code).
        .balign 4
        .space 0x600, 0
        .balign 4
_v_load:                                ! = VBR + 0x420
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        mov.l   Ph_resume, r0          ! r0 = _resume address (Ph_resume: .long _resume)
        .word   0x404E                 ! LDC r0, SPC
        rte
        nop
        ! If the RTE fails to redirect (the defect), execution falls through
        ! to here instead of jumping to _resume: take the explicit fail path so
        ! the result is a deterministic FAIL rather than running into the
        ! literal pool.
        ! RTE fell through (the defect): spin WITHOUT writing a result. The only
        ! path that writes TEST_RESULT is _resume (reached iff the RTE redirected
        ! to SPC). So RED = run times out with no "Test Passed"; GREEN = the RTE
        ! redirects, _resume runs, "Test Passed" is printed.
_h_fail_spin:
        bra     _h_fail_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Ph_resume:      .long _resume

        ! ---- Fault-page padding: VA 0x1000. ----
_fault_pages:
        .space 0x2000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
