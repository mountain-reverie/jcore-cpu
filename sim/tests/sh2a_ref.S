! Reference: plain MOV.L R0,@-R15 then MOV.L @R15+,R1, NO nops between.
! Does the BASE pipeline interlock the R15 dependency, or need nops like movml?
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
        mov.l   p_val, r0
        nop
        mov.l   r0, @-r15        ! push r0
        mov.l   @r15+, r1        ! pop immediately (no nops) -> tests base interlock
        nop
        mov.l   p_val, r2
        cmp/eq  r1, r2
        bf      _fail
        bra     _done
        nop
        .align 2
p_val:  .long 0xABCD1234
_done:  mov.l   p_res, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail:  mov.l   p_res, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_res:  .long TEST_RESULT_ADDRESS
