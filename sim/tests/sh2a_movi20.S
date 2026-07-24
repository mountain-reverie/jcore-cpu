! SH-2A movi20 / movi20s bring-up. Uses native movi20/movi20s mnemonics
! (requires -Wa,--isa=sh2a).
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
        ! (1) movi20 #0x00012,r1 -> 0x00000012
        movi20  #0x00012,r1
        nop
        mov.l   e1, r8
        cmp/eq  r1, r8
        bf      _fail1

        ! (2) movi20 #0x80000,r2 -> 0xFFF80000 (sign-extend)
        movi20  #-524288,r2
        nop
        mov.l   e2, r8
        cmp/eq  r2, r8
        bf      _fail2

        ! (3) movi20 #0x7FFFF,r3 -> 0x0007FFFF (max positive)
        movi20  #524287,r3
        nop
        mov.l   e3, r8
        cmp/eq  r3, r8
        bf      _fail3

        ! (4) movi20s #0x00123,r6 -> 0x00012300 (<<8)
        movi20s #74496,r6
        nop
        mov.l   e6, r8
        cmp/eq  r6, r8
        bf      _fail6

        ! (5) movi20s #0x80000,r7 -> 0xF8000000 (sign-extend then <<8)
        movi20s #-134217728,r7
        nop
        mov.l   e7, r8
        cmp/eq  r7, r8
        bf      _fail7

        ! (6) back-to-back movi20 (no nop between) -> r10=1, r11=2
        movi20  #1,r10
        movi20  #2,r11
        nop
        mov     #1, r8
        cmp/eq  r10, r8
        bf      _fail10
        mov     #2, r8
        cmp/eq  r11, r8
        bf      _fail11
        bra     _done
        nop

        .align 2
e1: .long 0x00000012
e2: .long 0xFFF80000
e3: .long 0x0007FFFF
e6: .long 0x00012300
e7: .long 0xF8000000

        .global _done
_done:
        mov.l   pr0, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail1: mov #1, r9
        bra _fail
        nop
_fail2: mov #2, r9
        bra _fail
        nop
_fail3: mov #3, r9
        bra _fail
        nop
_fail6: mov #6, r9
        bra _fail
        nop
_fail7: mov #7, r9
        bra _fail
        nop
_fail10: mov #10, r9
        bra _fail
        nop
_fail11: mov #11, r9
        bra _fail
        nop
_fail:  mov.l pr0, r0
        mov.l r9, @r0
        bra _fail
        nop
        .align 2
pr0: .long TEST_RESULT_ADDRESS
