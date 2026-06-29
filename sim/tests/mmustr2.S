! mmustr2.S -- back-to-back store-fault repro (M6 6th defect).
!
! mmustres.S proves a SINGLE resumed store writes. This isolates the case the
! task describes: a resumed store (DMISS_W -> LDTLB.RN) whose VERY NEXT access is
! ITSELF a DMISS_W. The first store's write must NOT be collateral-damaged by
! the second access's fault.
!
! Flow (AT on, identity maps; code page pre-mapped):
!   - store SVAL1 to unmapped identity page 1 -> DMISS_W.
!     Handler installs identity PTE for the faulting VA, LDTLB.RN resumes.
!     The resumed store re-executes and WRITES SVAL1; the immediately
!     following instruction is ...
!   - store SVAL2 to unmapped identity page 2 -> a second DMISS_W (back-to-back).
!     Same handler resumes it; it writes SVAL2.
!   - read page 1 back, then page 2 back. Classify:
!       both match        -> PASS (0)
!       page1 wrong/seed   -> fail 2 (FIRST resumed store lost -- the defect)
!       page2 wrong/seed   -> fail 5 (second store lost)
!
! The handler is VA-driven: it reads the faulting VPN from PTEH (HW-captured at
! 4 KB) and installs an identity PTE = (PTEH_page | 0xE8). One handler services
! both pages, so the test does not depend on TSB/walker/flush machinery.
!
! VBR = _v_store - 0x440 so DMISS_W (VBR+0x440) lands on _v_store.

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define SVAL1 0x5B5B0011
#define SVAL2 0x5B5B0022

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

        ! ---- VBR = _v_store - 0x440. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page (identity, W+X+U+C = 0xE8). ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Two back-to-back faulting stores. ----
        mov.l   c_fault1_va, r2
        mov.l   c_sval1, r3
        mov.l   c_fault2_va, r10
        mov.l   c_sval2, r11
        mov.l   r3, @r2                  ! DMISS_W #1; on resume must WRITE SVAL1
        mov.l   r11, @r10               ! immediately faults -> DMISS_W #2

        ! ---- Read both back & classify. ----
        mov.l   c_fault1_va, r2
        mov.l   @r2, r6                 ! page1 readback
        mov.l   c_fault2_va, r10
        mov.l   @r10, r12              ! page2 readback

        mov.l   c_sval1, r3
        cmp/eq  r3, r6
        mov     #2, r9
        bf      _fail                   ! page1 not SVAL1 -> FIRST resumed store lost (the defect)

        mov.l   c_sval2, r11
        cmp/eq  r11, r12
        mov     #5, r9
        bf      _fail                   ! page2 not SVAL2 -> second store lost
        bra     _pass
        nop

ENTRY(_pass)
        mov.l   pr_test_result, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _pass
        nop
        .align 2
pr_test_result: .long TEST_RESULT_ADDRESS

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_store - 0x440
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000E8
c_fault1_va:    .long _fault_page1
c_fault2_va:    .long _fault_page2
c_sval1:        .long SVAL1
c_sval2:        .long SVAL2

#endif

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

        ! ---- VA-driven DMISS_W handler at VBR+0x440 ----
        ! Reads faulting VPN from PTEH, installs identity PTE = (page | 0xE8),
        ! LDTLB.RN to resume. Bank-1 scratch; AT stays on.
        .balign 4
        .space 0x440, 0
        .balign 4
_v_store:                               ! = VBR + 0x440
        ! HW captured PTEH = faulting page VPN (4 KB). Leave PTEH as-is (it is
        ! the LDTLB tag); just derive the identity PTEL from it.
        .word   0x0153                  ! STC PTEH, r1   (faulting page VPN, 4KB)
        mov.l   Hpagemask, r0
        and     r0, r1                  ! r1 = page base
        mov.l   Hflags, r0
        or      r1, r0                  ! PTEL = page | 0xE8
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0078                  ! LDTLB.RN -- install + return atomically
_h_fail_spin:
        bra     _h_fail_spin
        nop

        .align 2
Hpagemask:      .long 0xFFFFF000
Hflags:         .long 0x000000E8

        ! ---- Two unmapped identity fault pages (seed 0). ----
        .balign 0x1000
_fault_page1:
        .long 0
        .space 0x1000 - 4, 0
_fault_page2:
        .long 0
        .space 0x1000 - 4, 0

#endif
