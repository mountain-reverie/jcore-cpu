! SH-2A MOVML.L @R15+,Rn (pop) with n=0: pop a single register, no loop.
!
! Mirrors sh2a_movml0.S (push, n=0) on the pop side: exercises the
! single-slot (non-looping) path of the decode_core.vhm sequencer when
! n=0, i.e. MOVML.L r0,@-r15 (0x40F1) followed by MOVML.L @r15+,r0
! (0100 0000 1111 0101 = 0x40F5). Marker: 0 = pass, non-zero = fail.

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
        nop

        ! push R0 only (R15 -= 4)
        .word   0x40F1

        ! clobber so the pop genuinely reads memory
        mov     #0, r0
        nop

        ! --- instruction under test: MOVML.L @r15+,r0 (pop R0 only) ---
        .word   0x40F5

        mov.l   p_s0, r7
        cmp/eq  r0, r7
        bf      _fail0

        mov.l   p_sp0, r7
        cmp/eq  r15, r7
        bf      _fail1

        bra     _done
        nop

        .align 2
p_s0:  .long 0xF0F0F000
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
_fail:  mov.l p_test_result, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
