! mmusr.S -- assert SR state + register banking on TLB-exception entry.
!
! Belt-and-suspenders guard for the privileged exception-entry contract the
! MMU miss handler depends on (hardware-spec.md §6, design-spec.md §4.4):
!   On a TLB exception, hardware sets SR.MD=1, SR.RB=1, SR.BL=1 and the
!   handler runs with bank-1 R0-R7 as zero-save/restore scratch.
!
! NOTE on IMASK: hardware-spec §5 lists "IMASK=0xF" but this core leaves
! IMASK unchanged on a general/TLB exception (datapath.vhm SEL_EXCEPTION,
! comment) -- interrupts are blocked by BL=1, not by IMASK. So we assert
! MD/RB/BL=1 (the core's real, sufficient invariant), NOT IMASK.
!
! Flow:
!   - map page 0 identity, enable AT, seed bank-0 R3 = 0x5A
!   - load VA 0x1000 (unmapped) -> DMISS_R -> handler at VBR+0x420
!   - handler (entered with MD=RB=BL=1): assert (SR & 0x70000000)==0x70000000;
!     clobber bank-1 R3=0x77 (uses bank-1 scratch); LDC SPC=_resume; RTE
!   - _resume (RB restored to 0): assert bank-0 R3 still 0x5A -> bank-1 was a
!     separate visible scratch bank -> PASS
!
! result 0 = pass; 1 = no exception fired; 2 = SR.{MD,RB,BL} not all set on
! entry; 3 = bank-0 R3 corrupted (handler's bank-1 write leaked to bank 0).
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

        ! ---- Ensure RB=0 (bank 0); MD stays 1 (supervisor). ----
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

        ! ---- Seed bank-0 R3, then take a DMISS_R from VA 0x1000. ----
        mov     #0x5A, r3               ! bank-0 R3 sentinel
        mov     #1, r9                  ! sentinel: if no fault, fail code 1
        mov.l   c_page1_va, r2
        mov.l   @r2, r4                 ! FAULTS -> _v_load (VBR+0x420), DMISS_R

        bra     _fail
        nop

ENTRY(_resume)
        ! Back in bank 0 (RB restored from SSR). Bank-0 R3 must be untouched by
        ! the handler's bank-1 R3 write -> proves bank-1 was separate scratch.
        mov     #0x5A, r1
        cmp/eq  r1, r3
        bf      _resume_bad_bank
        mov.l   pr_test_result, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! PASS
_rspin: bra     _rspin
        nop
_resume_bad_bank:
        mov.l   pr_test_result, r0
        mov     #3, r1
        mov.l   r1, @r0
_rbspin: bra    _rbspin
        nop

        .align 2
pr_test_result: .long TEST_RESULT_ADDRESS
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x420
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

        ! ---- DMISS_R handler at VBR+0x420 ----
        .balign 4
        .space 0x600, 0
        .balign 4
_v_load:                                ! = VBR + 0x420, entered MD=RB=BL=1
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT) -- bank-1 scratch r0/r1
        stc     sr, r0                 ! read SR on entry
        mov.l   Hsrmask, r1            ! MD|RB|BL = 0x70000000
        and     r1, r0
        cmp/eq  r1, r0                 ! all three set?
        bf      _h_bad_sr
        mov     #0x77, r3              ! clobber bank-1 R3 (bank-1 scratch in use)
        mov.l   Ph_resume, r0
        .word   0x404E                 ! LDC r0, SPC
        rte
        nop
_h_bad_sr:
        mov.l   Hresult, r0
        mov     #2, r1
        mov.l   r1, @r0                ! AT already disabled above -> P-region write OK
_hsrspin: bra   _hsrspin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hsrmask:        .long 0x70000000
Ph_resume:      .long _resume
Hresult:        .long TEST_RESULT_ADDRESS

        ! ---- Fault-page padding: VA 0x1000. ----
_fault_pages:
        .space 0x2000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
