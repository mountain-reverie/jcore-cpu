! mmuldtlbr.S -- guard for LDTLB.RN (fused Load-TLB-and-No-delay-slot-Return, 0x0068).
!
! Proves the two halves of the fused instruction in a SINGLE observable event:
!   (1) INSTALL: LDTLB.RN latches {PTEH, PTEL, ASIDR} into a TLB entry.
!   (2) RETURN : LDTLB.RN restores PC<-SPC, SR<-SSR (NO delay slot --
!                the instruction immediately after LDTLB.RN must NOT execute).
! The DMISS_R handler does NOT touch AT and does NOT set SPC by hand: it relies
! on the hardware-captured SPC (= faulting load PC) and on LDTLB.RN installing
! the mapping so the RE-EXECUTED load hits the fresh TLB entry, reads a known
! sentinel, and falls through to the PASS writer. If LDTLB.RN failed to install,
! the re-executed load would fault again (infinite miss loop -> timeout). If it
! failed to return, execution would fall through the handler -> spin -> timeout.
! Only a correct fused install+return reaches _pass.
!
! r9 is the fail-code register (set to 2 before the faulting load; the post-
! LDTLB.RN slot sets it to 1 if it executes). The guard after the sentinel
! check asserts r9==2: if r9==1 the delay slot ran -> decoder is still delayed.
!
! Contrast with mmurte.S (return only, AT disabled in handler): here AT stays ON
! across the return, so the re-executed access is genuinely re-translated.
!
! RED before change: 0x0068 is a delayed branch, so the slot (mov #1,r9)
! executes -> r9==1 -> the no-delay-slot guard trips -> "Test failed. Result=1".
!
! VBR = _v_load - 0x420 so the DMISS_R vector (VBR+0x420) hits _v_load.

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define SENTINEL 0x5A4D7011

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

        ! ---- Map the code page (identity, W+X+U+C = 0xE8). ----
        ! `start` is forced 4 KB-aligned (the .balign 0x1000 on _fault_page below
        ! raises the .text section alignment), so all of this test's code/data
        ! live in one page whose base == `start`.  `.long start` is therefore a
        ! valid page-aligned PTEH/PTEL base (VPN<<12, ASID=0).
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Take a DMISS_R: load from VA in page 1 (unmapped). ----
        ! After the handler's LDTLB.RN installs page 1 and returns, THIS load
        ! re-executes against the fresh entry and reads SENTINEL into r3.
        mov     #2, r9                  ! sentinel: if we fall through, fail code 2
        mov.l   c_sentinel_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (DMISS_R); on re-exec reads SENTINEL

        ! ---- Returned here by LDTLB.RN with AT still on. Verify install worked. ----
        mov.l   c_sentinel_val, r4
        cmp/eq  r3, r4
        bf      _fail                   ! r3 != SENTINEL -> install/return wrong (r9=2)
        ! ---- No-delay-slot guard: r9 must still be 2 (slot must NOT have run). ----
        mov     #1, r4
        cmp/eq  r9, r4
        bt      _fail                   ! r9==1 -> post-LDTLB.RN slot executed -> delay slot present (RED)

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
p_vbr_val:      .long _v_load - 0x420
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start                     ! code page base (4KB-aligned), ASID=0
p_ptel_code:    .long start + 0x000000E8        ! identity PPN | (W+X+U+C)
c_sentinel_va:  .long _sentinel
c_sentinel_val: .long SENTINEL

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
        ! Pad so _v_load lands at >= 0x420 and clear of page 0's code.
        .balign 4
        .space 0x600, 0
        .balign 4
_v_load:                                ! = VBR + 0x420
        ! Map the faulting page identity (W+X+U+C = 0xE8) using the page's VPN.
        ! _sentinel lives in the page-1 region; PTEH.VPN must name that page.
        mov.l   Hpteh, r0               ! r0 = _sentinel page base (VPN<<12, 4KB page)
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   Hptel, r0               ! identity PPN | 0xE8
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0068                  ! LDTLB.RN -- install + return (NO delay slot)
        mov     #1, r9                  ! MUST NOT execute: LDTLB.RN has no delay slot
        ! If LDTLB.RN failed to return, execution falls through to here -> spin
        ! WITHOUT writing a result (RED = timeout).
_h_fail_spin:
        bra     _h_fail_spin
        nop

        .align 2
        ! 4 KB base page: VPN occupies VA[31:12]; mask off VA[11:0].
        ! _sentinel is in its own page; both PTEH.VPN and PTEL.PPN use its base.
Hpteh:          .long _sentinel                 ! _sentinel is 4KB-aligned: VPN<<12, ASID=0
Hptel:          .long _sentinel + 0x000000E8    ! identity PPN | (W+X+U+C); low 12b are 0

        ! ---- Fault page: holds SENTINEL at _sentinel. ----
        .balign 0x1000                  ! align to a 4 KB page boundary
_fault_page:
_sentinel:      .long SENTINEL
        .space 0x1000 - 4, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
