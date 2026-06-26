! m8_macseq -- fault-then-clean MAC sequencing guard (M8).
!
! Proves the acc_squash latch does NOT linger: a CLEAN MAC executed immediately
! AFTER a faulting MAC must accumulate exactly once (acc_sq re-samples at
! dispatch). Without re-sampling, the latch armed by the faulting MAC would
! wrongly suppress the following clean MAC's accumulate.
!
! Sequence (MMU on, identity pages 0x00100000 / 0x00101000):
!   page A = {2, 5}, page B = {3, 7}
!   clear MAC; flush TLB cold
!   MAC.L @r0+,@r8+   ! r0=A,r8=B: faults cold -> precise -> acc = 2*3 = 6
!   MAC.L @r0+,@r8+   ! warm now, NO acc clear: acc += 5*7 = 35 -> acc = 41
!   expect MACH=0, MACL=41 (0x29). 6 (squash lingered) or 35 (first lost) FAIL.
!
! Reuses m8_runtime.inc's MMU bring-up + slow-path TLB handler; this file only
! supplies _m8_run_all (the dispatch target kmain jsr's into).

#include "m8_runtime.inc"

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        .text
ENTRY(_m8_run_all)
        sts.l   pr, @-r15
        ! ---- seed both pages (these writes warm the TLB; flush undoes it) ----
        mov.l   ms_va,  r0
        mov.l   ms_a0,  r1 ; mov.l r1, @r0
        mov.l   ms_a1,  r1 ; mov.l r1, @(4,r0)
        mov.l   ms_vb,  r0
        mov.l   ms_b0,  r1 ; mov.l r1, @r0
        mov.l   ms_b1,  r1 ; mov.l r1, @(4,r0)
        ! ---- arm a COLD TLB ----
        mov.l   ms_flush, r3
        jsr     @r3
        nop
        ! ---- clear MAC (lds, not clrmac -- see m8_runtime sim-init note) ----
        mov     #0, r9
        lds     r9, mach
        lds     r9, macl
        ! ---- faulting MAC: precise, acc = A0*B0 = 6 ----
        mov.l   ms_va, r0
        mov.l   ms_vb, r8
        mac.l   @r0+, @r8+
        ! ---- clean MAC (pages warm now), NO acc clear: acc += A1*B1 = 35 ----
        mac.l   @r0+, @r8+
        ! ---- check acc == 41 (MACH=0, MACL=0x29) ----
        sts     mach, r2
        mov.l   ms_exp_h, r3
        cmp/eq  r3, r2
        bf      _ms_fail
        sts     macl, r2
        mov.l   ms_exp_l, r3
        cmp/eq  r3, r2
        bf      _ms_fail
        lds.l   @r15+, pr
        rts
        nop
_ms_fail:
        mov.l   ms_result, r0
        mov     #2, r9                 ! distinct failure code
        mov.l   r9, @r0
1:      bra     1b
        nop

        .align 2
ms_va:     .long 0x00100000
ms_vb:     .long 0x00101000
ms_a0:     .long 2
ms_a1:     .long 5
ms_b0:     .long 3
ms_b1:     .long 7
ms_exp_h:  .long 0x00000000
ms_exp_l:  .long 0x00000029           ! 6 + 35 = 41
ms_flush:  .long 0x80000000 + _m8_flush
ms_result: .long TEST_RESULT_ADDRESS
#endif
