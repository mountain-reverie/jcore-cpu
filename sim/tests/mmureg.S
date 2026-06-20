! MMU register round-trip test (J4, MMU_ARCH). LDC r0,PTEH then STC PTEH,r1
! two distinct patterns to rule out stuck-at-reset false pass.
! result 0 = pass; 1 = pattern A (0xA5A5A5A5) mismatch; 2 = pattern B (0x5A5A5A5A) mismatch.
!
! Runs in privileged mode (MD=1, the reset state) — do NOT drop to user mode;
! LDC/STC PTEH are privileged instructions.
!
! LDC Rm,PTEH = 0100 mmmm 0101 1110; r0 -> 0100 0000 0101 1110 = 0x405E
! STC PTEH,Rn = 0000 nnnn 0101 0011; r1 <- 0000 0001 0101 0011 = 0x0153
! (the assembler does not know these J4/MMU overlay opcodes, so .word them)

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
        ! --- Pattern A: 0xA5A5A5A5 ---
        mov.l   p_patA, r0
        .word   0x405E             ! LDC r0, PTEH  (0100 0000 0101 1110)
        .word   0x0153             ! STC PTEH, r1  (0000 0001 0101 0011)
        cmp/eq  r0, r1
        mov     #1, r9             ! code 1 = pattern A mismatch
        bf      _fail

        ! --- Pattern B: 0x5A5A5A5A ---
        mov.l   p_patB, r0
        .word   0x405E             ! LDC r0, PTEH  (0100 0000 0101 1110)
        .word   0x0153             ! STC PTEH, r1  (0000 0001 0101 0011)
        cmp/eq  r0, r1
        mov     #2, r9             ! code 2 = pattern B mismatch
        bf      _fail

        bra     _done
        nop

        .align 2
p_patA: .long 0xA5A5A5A5
p_patB: .long 0x5A5A5A5A
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
