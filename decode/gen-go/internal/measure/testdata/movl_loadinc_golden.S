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
        mov.l   led, r14           ! r14 = 0xABCD0000 (PIO marker addr)
        bra     begin
        nop
        .align 2
led:    .long   0xABCD0000
begin:
        mov.l   ptr_lit, r10
        bra     1f
        nop
        .align 2
ptr_lit:        .long   0x00008000
1:
        mov     #0x11, r0
        mov.b   r0, @r14
        .rept 100
        nop
        .endr
        mov     #0x12, r0
        mov.b   r0, @r14
        mov     #0x13, r0
        mov.b   r0, @r14
        .rept 200
        nop
        .endr
        mov     #0x14, r0
        mov.b   r0, @r14
        mov     #0x33, r0
        mov.b   r0, @r14
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov     #0x44, r0
        mov.b   r0, @r14
        mov     #0x55, r0
        mov.b   r0, @r14
        mov.l   ptr_lit2, r10
        bra     1f
        nop
        .align 2
ptr_lit2:        .long   0x00008000
1:
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov.l   @r10+, r3
        mov.l   @r10+, r4
        mov.l   @r10+, r5
        mov.l   @r10+, r6
        mov.l   @r10+, r7
        mov.l   @r10+, r8
        mov.l   @r10+, r1
        mov.l   @r10+, r2
        mov     #0x66, r0
        mov.b   r0, @r14
        bra     _done
        nop
        .align 2
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
p_res:  .long   TEST_RESULT_ADDRESS
