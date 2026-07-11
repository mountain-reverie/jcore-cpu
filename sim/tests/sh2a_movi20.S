! SH-2A movi20 / movi20s bring-up. Hand-encoded (.word) — -m2 lacks SH-2A.
!   movi20  #imm20,Rn = 0000 nnnn iiii 0000 | iiii iiii iiii iiii
!   movi20s #imm20,Rn = 0000 nnnn iiii 0001 | iiii iiii iiii iiii
!   Rn=op.code(11:8); imm[19:16]=op.code(7:4); imm[15:0]=word2; sign=bit19.
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
        .word 0x0100            ! n=1, imm[19:16]=0
        .word 0x0012
        nop
        mov.l   e1, r8
        cmp/eq  r1, r8
        bf      _fail1

        ! (2) movi20 #0x80000,r2 -> 0xFFF80000 (sign-extend)
        .word 0x0280            ! n=2, imm[19:16]=8
        .word 0x0000
        nop
        mov.l   e2, r8
        cmp/eq  r2, r8
        bf      _fail2

        ! (3) movi20 #0x7FFFF,r3 -> 0x0007FFFF (max positive)
        .word 0x0370            ! n=3, imm[19:16]=7
        .word 0xFFFF
        nop
        mov.l   e3, r8
        cmp/eq  r3, r8
        bf      _fail3

        ! (4) movi20s #0x00123,r6 -> 0x00012300 (<<8)
        .word 0x0601            ! n=6, imm[19:16]=0, s
        .word 0x0123
        nop
        mov.l   e6, r8
        cmp/eq  r6, r8
        bf      _fail6

        ! (5) movi20s #0x80000,r7 -> 0xF8000000 (sign-extend then <<8)
        .word 0x0781            ! n=7, imm[19:16]=8, s
        .word 0x0000
        nop
        mov.l   e7, r8
        cmp/eq  r7, r8
        bf      _fail7

        ! (6) back-to-back movi20 (no nop between) -> r10=1, r11=2
        .word 0x0A00            ! movi20 #1,r10
        .word 0x0001
        .word 0x0B00            ! movi20 #2,r11
        .word 0x0002
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
