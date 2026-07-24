! Post-loop regression: MOVMU.L push immediately followed by MOVMU.L pop,
! with NO nops between them. This stresses the movml_hold-gated single
! if_issue/incpc suppression across two back-to-back counted loops for the
! movmu shapes (push = pre-loop PR store slot + register store loop; pop =
! register load loop + PR-load slot + terminal R15 adjust slot), not just a
! plain mov.l @r15+ like sh2a_movml_b2b.S. Marker: 0 = pass, non-zero = fail.

#include "sim_instr.h"

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
        .global start
start:
        mov.l   p_s0, r0
        mov.l   p_s1, r1
        mov.l   p_s2, r2
        mov.l   p_spr, r6
        lds     r6, pr
        nop
        movmu.l r2,@-r15         ! push PR,R2,R1,R0 (R15 -= 16)
        movmu.l @r15+,r2         ! IMMEDIATE pop R0..R2,PR, NO nops between loops
        mov     #7, r3           ! must not be skipped by the pop's terminal slot

        mov.l   p_s0, r7
        cmp/eq  r0, r7
        bf      _fail0
        mov.l   p_s1, r7
        cmp/eq  r1, r7
        bf      _fail1
        mov.l   p_s2, r7
        cmp/eq  r2, r7
        bf      _fail2

        mov     #7, r7
        cmp/eq  r3, r7
        bf      _fail3

        sts     pr, r7
        mov.l   p_spr, r6
        cmp/eq  r6, r7
        bf      _fail4

        mov.l   p_sp0, r7        ! R15 net-neutral after push+pop
        cmp/eq  r15, r7
        bf      _fail5

        bra     _done
        nop

        .align 2
p_s0:   .long 0xAA0000AA
p_s1:   .long 0xBB1111BB
p_s2:   .long 0xCC2222CC
p_spr:  .long 0xDD3333DD
p_sp0:  .long 0x00007000

        .global _done
_done:  mov.l p_res, r0
        mov #0, r9
        mov.l r9, @r0
        bra _done
        nop
_fail0: mov.l p_res, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail0
        nop
_fail1: mov.l p_res, r0
        mov #2, r9
        mov.l r9, @r0
        bra _fail1
        nop
_fail2: mov.l p_res, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail2
        nop
_fail3: mov.l p_res, r0
        mov #4, r9
        mov.l r9, @r0
        bra _fail3
        nop
_fail4: mov.l p_res, r0
        mov #5, r9
        mov.l r9, @r0
        bra _fail4
        nop
_fail5: mov.l p_res, r0
        mov #6, r9
        mov.l r9, @r0
        bra _fail5
        nop
_fail:  mov.l p_res, r0
        mov #7, r9
        mov.l r9, @r0
        bra _fail
        nop

        .align 2
p_res: .long TEST_RESULT_ADDRESS
