! Post-loop regression: movml.l immediately followed by a mov.l @r15+ that
! mov.l @r15+ that READS R15 with NO nops. If the movml's final R15 writeback
! READS R15 with NO nops. Exercises the fix that suppresses if_issue/incpc during
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
        movml.l r2,@-r15         ! push R2,R1,R0; R15-=12
        mov.l   @r15+, r5        ! IMMEDIATE R15 read, NO nops -> tests post-loop interlock. r5=R0
        nop
        mov.l   p_s0, r6
        cmp/eq  r5, r6
        bf      _fail
        bra     _done
        nop
        .align 2
p_s0:   .long 0xAA0000AA
p_s1:   .long 0xBB1111BB
p_s2:   .long 0xCC2222CC
_done:  mov.l p_res, r0
        mov #0, r9
        mov.l r9, @r0
        bra _done
        nop
_fail:  mov.l p_res, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail
        nop
        .align 2
p_res:  .long TEST_RESULT_ADDRESS
