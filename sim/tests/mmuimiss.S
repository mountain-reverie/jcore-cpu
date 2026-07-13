! mmuimiss.S -- isolated RED guard for the IMISS TEA-capture defect (Defect 2).
!
! Reproduces, in isolation, the defect described in
! docs/superpowers/handover-mmu-m3-datapath-defects.md: on an instruction-fetch
! TLB miss (IMISS) taken via a jmp to an unmapped VA, TEA captures 0 instead of
! the faulting VA. The D-side (DMISS_R, mmurte.S) captures TEA correctly, so this
! test isolates the I-side faulting-VA capture path.
!
! Flow:
!   - map page 0 identity (W|X|U|C), enable AT
!   - jmp to VA 0x1000 (page 1, unmapped) -> IMISS TLB exception
!   - handler (VBR+0x400): disable AT, read TEA, compare to 0x1000
!       * TEA correct -> set SPC=_resume, RTE -> _resume -> result 0 (PASS)
!       * TEA wrong   -> result 9 (the Defect-2 symptom: TEA=0)
!       * no exception / fall-through -> times out, no "Test Passed" (RED)
!
! VBR = _v_ifetch - 0x400 so the IMISS vector (VBR+0x400) hits _v_ifetch.

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

        ! ---- VBR = _v_ifetch - 0x400 (so VBR+0x400 = _v_ifetch). ----
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

        ! ---- Take an IMISS: jump to VA 0x1000 (page 1, unmapped). ----
        mov.l   c_page1_va, r0
        jmp     @r0                     ! FAULTS -> _v_ifetch (VBR+0x400), IMISS
        nop

        ! If the IMISS does not fire, we fall here only after running page-1
        ! zeros; in practice we never reach this. Deterministic fail anyway.
        mov     #7, r9
        bra     _fail
        nop

ENTRY(_resume)
        ! RTE redirected after a correct TEA: write result 0 (PASS). AT is off
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
p_vbr_val:      .long _v_ifetch - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C8
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

        ! ---- IMISS handler at VBR+0x400 ----
        ! Pad so _v_ifetch lands at >= 0x400 (kept clear of page 0's code and
        ! within page 0 so the handler fetch itself is mapped).
        .balign 4
        .space 0x600, 0
        .balign 4
_v_ifetch:                              ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        mov.l   Htea_addr, r0
        mov.l   @r0, r2                 ! r2 = TEA (faulting VA)
        mov.l   Hexp_tea, r3           ! r3 = 0x1000 (expected)
        cmp/eq  r3, r2
        bf      _h_tea_bad             ! TEA wrong -> Defect 2 symptom
        mov.l   Ph_resume, r0          ! r0 = _resume address
        .word   0x404E                 ! LDC r0, SPC
        rte
        nop
_h_tea_bad:
        mov     #9, r9                 ! fail code 9: IMISS TEA != 0x1000
        mov.l   Hres_addr, r0
        mov.l   r9, @r0
_h_bad_spin:
        bra     _h_bad_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Htea_addr:      .long 0xFF00000C
Hexp_tea:       .long 0x00001000
Ph_resume:      .long _resume
Hres_addr:      .long TEST_RESULT_ADDRESS

        ! ---- Fault-page padding: VA 0x1000. ----
_fault_pages:
        .space 0x2000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
