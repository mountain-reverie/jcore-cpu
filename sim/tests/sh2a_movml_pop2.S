! SH-2A MOVML.L @R15+,Rn (pop) with n=2: pop R0..R2 (3 registers, a short
! counted loop) to cover a loop length distinct from the n=4 round-trip in
! sh2a_movml_pop.S. Push R2,R1,R0 with MOVML.L r2,@-r15 (0100 0010 1111 0001
! = 0x42F1), clobber R0..R2, then pop them back with MOVML.L @r15+,r2
! (0100 0010 1111 0101 = 0x42F5) and check each register + R15 net-restore.
! Marker: 0 = pass, non-zero = fail.

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
        nop

        ! push R2,R1,R0 (R15 -= 12)
        .word   0x42F1

        ! clobber so the pop genuinely reads memory
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        nop

        ! --- instruction under test: MOVML.L @r15+,r2 (pop R0..R2) ---
        .word   0x42F5

        mov.l   p_s0, r7
        cmp/eq  r0, r7
        bf      _fail0
        mov.l   p_s1, r7
        cmp/eq  r1, r7
        bf      _fail1
        mov.l   p_s2, r7
        cmp/eq  r2, r7
        bf      _fail2

        mov.l   p_sp0, r7
        cmp/eq  r15, r7
        bf      _fail3

        bra     _done
        nop

        .align 2
p_s0:  .long 0x02020200
p_s1:  .long 0x12121211
p_s2:  .long 0x22222222
p_sp0: .long 0x00007000

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop

_fail0: mov.l p_test_result, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail0
        nop
_fail1: mov.l p_test_result, r0
        mov #2, r9
        mov.l r9, @r0
        bra _fail1
        nop
_fail2: mov.l p_test_result, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail2
        nop
_fail3: mov.l p_test_result, r0
        mov #4, r9
        mov.l r9, @r0
        bra _fail3
        nop
_fail:  mov.l p_test_result, r0
        mov #5, r9
        mov.l r9, @r0
        bra _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
