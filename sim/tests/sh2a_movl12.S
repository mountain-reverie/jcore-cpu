! SH-2A two-word instruction bring-up: MOV.L @(disp12,Rm),Rn
!
! Task 1.3C observation harness. Exercises the seed SH-2A instruction added
! to decode/gen-go/spec/sh2a/mov.toml: a 2-microcode-slot op where slot0
! latches the second opcode word (the disp12 extension word, "ext_word")
! and slot1 performs the actual load using imm_from_ext to source the
! disp12*4 immediate.
!
! Uses the native SH-2A MOV.L @(disp12,Rm),Rn mnemonic (requires
! -Wa,--isa=sh2a):
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
        .word   0x3121          ! MOV.L @(disp12,Rm),Rn n=1 m=2, disp12=0 -- no gas mnemonic (small disp fits base short disp4 form, gas prefers that; two-word form needed to test disp12 extension path)
        .word   0x6000
        ! --- instructions AFTER the two-word insn: if PC lands correctly at
        !     the instr after word2, these execute in order; if word2 gets
        !     mis-executed as its own instruction, behavior diverges here.
        nop
        nop

        ! r3 = expected sentinel value
        mov.l   p_sentinel_val, r3
        cmp/eq  r1, r3
        bf      _fail_loop

        ! --- second case: NON-ZERO disp12, to actually exercise the ext_word
        !     displacement bits (disp=0 above leaves the immediate 0, so it
        !     would pass even if ext_word's disp bits were mis-wired). ---
        ! r4 = base of a 4-word table; word at base+12 (disp12=3, *4) is the
        ! sentinel. MOV.L @(3,r4),r6 -> r6 = *(r4 + 3*4).
        mov.l   p_base2, r4
        nop
        .word   0x3641          ! MOV.L @(disp12,Rm),Rn n=6 m=4, disp12=3 -- no gas mnemonic / encodes differently, see sync report
        .word   0x6003
        nop
        nop
        mov.l   p_sentinel2_val, r5
        cmp/eq  r6, r5
        bf      _fail_loop2
        bra     _done
        nop

        .align 2
p_sentinel_addr: .long sentinel
p_sentinel_val:  .long 0xDEADBEEF
p_base2:         .long base2
p_sentinel2_val: .long 0xCAFEBABE

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail_loop:
        mov.l   p_test_result, r0
        mov     #1, r9         ! 1 = r1 mismatch (disp=0 load did not produce sentinel)
        mov.l   r9, @r0
        bra     _fail_loop
        nop
_fail_loop2:
        mov.l   p_test_result2, r0
        mov     #2, r9         ! 2 = r6 mismatch (disp=3 load did not produce sentinel2)
        mov.l   r9, @r0
        bra     _fail_loop2
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result2: .long TEST_RESULT_ADDRESS

        .align 4
sentinel: .long 0xDEADBEEF
        .align 4
base2:  .long 0x11111111       ! base+0
        .long 0x22222222       ! base+4
        .long 0x33333333       ! base+8
        .long 0xCAFEBABE       ! base+12  (disp12=3 -> 3*4)
