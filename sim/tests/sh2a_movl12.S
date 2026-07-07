! SH-2A two-word instruction bring-up: MOV.L @(disp12,Rm),Rn
!
! Task 1.3C observation harness. Exercises the seed SH-2A instruction added
! to decode/gen-go/spec/sh2a/mov.toml: a 2-microcode-slot op where slot0
! latches the second opcode word (the disp12 extension word, "ext_word")
! and slot1 performs the actual load using imm_from_ext to source the
! disp12*4 immediate.
!
! sh2-elf-as (plain -m2) does not know the SH-2A "nmd12" format, so the
! two-word opcode is hand-encoded via .word:
!   word1 = 0x3121  (0011 nnnn mmmm 0001, n=1(r1) m=2(r2))
!   word2 = 0x6000  (0110 dddd dddd dddd, disp12=0)
! -> MOV.L @(0,r2),r1  i.e. r1 = *(uint32_t*)(r2 + 0*4)
!
! Known-open questions this test is designed to surface (see brief):
!   1. Does word2 get fetched/executed as a spurious instruction?
!   2. Does check_illegal_instruction fire on word2 as it transits if_dr?
!   3. Does PC end up correctly at the instruction AFTER word2 (PC+4 from
!      word1), or does something mis-execute / hang / trap?
!
! Marker convention mirrors sim/tests/banktest.S: 0 = pass at
! TEST_RESULT_ADDRESS, non-zero = fail (distinct codes below).

#include "sim_instr.h"

        .section .vect
        .long start            ! 0: power-on PC
        .long 0x00007000       ! 1: power-on SP (inside RAM)
        .long start            ! 2: manual reset PC
        .long 0x00007000       ! 3: manual reset SP
        .rept 60
        .long 0
        .endr
        .long SIM_INSTR_MAGIC
        .long _sim_instr_end
        .long _done
        .long _fail_loop
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
        .global start
start:
        ! r2 = address of the sentinel word (A)
        mov.l   p_sentinel_addr, r2
        nop                      ! avoid load-use hazard confound (SH-2 load delay)

        ! --- the instruction under test: MOV.L @(0,r2),r1 (two-word SH-2A form) ---
        .word   0x3121          ! word1: MOV.L @(disp12,Rm),Rn  n=1 m=2
        .word   0x6000          ! word2: disp12 = 0
        ! --- instructions AFTER the two-word insn: if PC lands correctly at
        !     the instr after word2, these execute in order; if word2 gets
        !     mis-executed as its own instruction, behavior diverges here.
        nop
        nop

        ! r3 = expected sentinel value
        mov.l   p_sentinel_val, r3
        cmp/eq  r1, r3
        bf      _fail_loop
        bra     _done
        nop

        .align 2
p_sentinel_addr: .long sentinel
p_sentinel_val:  .long 0xDEADBEEF

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail_loop:
        mov.l   p_test_result, r0
        mov     #1, r9         ! 1 = r1 mismatch (load did not produce sentinel)
        mov.l   r9, @r0
        bra     _fail_loop
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

        .align 4
sentinel: .long 0xDEADBEEF
