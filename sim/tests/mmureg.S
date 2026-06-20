! MMU register round-trip test (J4, MMU_ARCH).
! Covers PTEH/PTEL/ASIDR individual round-trips (two distinct patterns each)
! plus an independence check: write three distinct values then STC each back
! to prove no cross-clobber (the bug: LDC Rm,PTEL wrote PTEH instead).
!
! result 0 = pass; nonzero = failure code:
!   1  PTEH pattern A (0xA5A5A5A5) mismatch
!   2  PTEH pattern B (0x5A5A5A5A) mismatch
!   3  PTEL pattern A mismatch
!   4  PTEL pattern B mismatch
!   5  ASIDR pattern A mismatch
!   6  ASIDR pattern B mismatch
!   7  independence: PTEH clobbered after writing all three
!   8  independence: PTEL clobbered after writing all three
!   9  independence: ASIDR clobbered after writing all three
!
! Runs in privileged mode (MD=1, the reset state).
! LDC/STC MMU regs are privileged; assembler doesn't know these overlay opcodes.
!
! LDC r0,PTEH  = 0100 0000 0101 1110 = 0x405E
! STC PTEH,r1  = 0000 0001 0101 0011 = 0x0153
! LDC r0,PTEL  = 0100 0000 0110 1110 = 0x406E
! STC PTEL,r1  = 0000 0001 0110 0011 = 0x0163
! LDC r0,ASIDR = 0100 0000 0111 1110 = 0x407E
! STC ASIDR,r1 = 0000 0001 0111 0011 = 0x0173

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

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
ENTRY(start)
#if CONFIG_PRIV_ARCH
        ! ---- PTEH round-trip ----
        ! Pattern A: 0xA5A5A5A5
        mov.l   p_patA, r0
        .word   0x405E             ! LDC r0,PTEH
        .word   0x0153             ! STC PTEH,r1
        cmp/eq  r0, r1
        mov     #1, r9             ! code 1 = PTEH pattern A mismatch
        bf      _fail

        ! Pattern B: 0x5A5A5A5A
        mov.l   p_patB, r0
        .word   0x405E             ! LDC r0,PTEH
        .word   0x0153             ! STC PTEH,r1
        cmp/eq  r0, r1
        mov     #2, r9             ! code 2 = PTEH pattern B mismatch
        bf      _fail

        ! ---- PTEL round-trip ----
        ! Pattern A: 0xA5A5A5A5
        mov.l   p_patA, r0
        .word   0x406E             ! LDC r0,PTEL
        .word   0x0163             ! STC PTEL,r1
        cmp/eq  r0, r1
        mov     #3, r9             ! code 3 = PTEL pattern A mismatch
        bf      _fail

        ! Pattern B: 0x5A5A5A5A
        mov.l   p_patB, r0
        .word   0x406E             ! LDC r0,PTEL
        .word   0x0163             ! STC PTEL,r1
        cmp/eq  r0, r1
        mov     #4, r9             ! code 4 = PTEL pattern B mismatch
        bf      _fail

        ! ---- ASIDR round-trip ----
        ! Pattern A: 0xA5A5A5A5
        mov.l   p_patA, r0
        .word   0x407E             ! LDC r0,ASIDR
        .word   0x0173             ! STC ASIDR,r1
        cmp/eq  r0, r1
        mov     #5, r9             ! code 5 = ASIDR pattern A mismatch
        bf      _fail

        ! Pattern B: 0x5A5A5A5A
        mov.l   p_patB, r0
        .word   0x407E             ! LDC r0,ASIDR
        .word   0x0173             ! STC ASIDR,r1
        cmp/eq  r0, r1
        mov     #6, r9             ! code 6 = ASIDR pattern B mismatch
        bf      _fail

        ! ---- Independence check: write 3 distinct values, STC each ----
        ! PTEH <- 0xDEAD0001, PTEL <- 0xDEAD0002, ASIDR <- 0xDEAD0003
        mov.l   p_ind1, r0
        .word   0x405E             ! LDC r0,PTEH
        mov.l   p_ind2, r0
        .word   0x406E             ! LDC r0,PTEL
        mov.l   p_ind3, r0
        .word   0x407E             ! LDC r0,ASIDR

        ! STC PTEH -> r1, verify == 0xDEAD0001
        .word   0x0153             ! STC PTEH,r1
        mov.l   p_ind1, r2
        cmp/eq  r1, r2
        mov     #7, r9             ! code 7 = PTEH clobbered
        bf      _fail

        ! STC PTEL -> r1, verify == 0xDEAD0002
        .word   0x0163             ! STC PTEL,r1
        mov.l   p_ind2, r2
        cmp/eq  r1, r2
        mov     #8, r9             ! code 8 = PTEL clobbered
        bf      _fail

        ! STC ASIDR -> r1, verify == 0xDEAD0003
        .word   0x0173             ! STC ASIDR,r1
        mov.l   p_ind3, r2
        cmp/eq  r1, r2
        mov     #9, r9             ! code 9 = ASIDR clobbered
        bf      _fail

        bra     _done
        nop

        .align 2
p_patA: .long 0xA5A5A5A5
p_patB: .long 0x5A5A5A5A
p_ind1: .long 0xDEAD0001
p_ind2: .long 0xDEAD0002
p_ind3: .long 0xDEAD0003
#else
        ! J2: MMU regs not present -> skip-pass (negative test is Task 9)
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0            ! distinct nonzero code per failed assertion
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
