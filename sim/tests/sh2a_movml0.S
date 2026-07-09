! Isolating test: movml.l r0,@-r15 (m=0) = single store of R0, NO loop.
! If this passes with only the seed (no decode_core loop hardware), the DIRECT
! decoder emits the store correctly and the loop is the only remaining work.
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
        mov.l   p_val, r0        ! r0 = 0xABCD1234
        nop
        .word   0x40F1           ! movml.l r0,@-r15  (m=0: one store of R0)
        nop
        nop
        mov.l   @r15+, r1        ! pop it back
        nop
        mov.l   p_val, r2
        cmp/eq  r1, r2
        bf      _fail
        bra     _done
        nop
        .align 2
p_val:  .long 0xABCD1234
_done:
        mov.l   p_res, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail:
        mov.l   p_res, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_res:  .long TEST_RESULT_ADDRESS
