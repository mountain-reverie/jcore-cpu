! SH-2A MOVML.L Rm,@-R15 bring-up: push R0..Rm onto the R15 stack.
!
! Exercises the decode_core.vhm (SH2A_ARCH) counted-loop sequencer for the
! seed instruction added to decode/gen-go/spec/sh2a/mov.toml. MOVML.L r4,@-r15
! (opcode 0100 0100 1111 0001 = 0x44F1) pushes R4,R3,R2,R1,R0 (m+1 = 5 longs),
! R4 at the highest address, R0 at the lowest, and leaves R15 -= 20.
!
! sh2-elf-as (-m2) does not know the SH-2A MOVML.L mnemonic, so the opcode is
! hand-encoded with .word 0x44F1.
!
! Strategy: seed R0..R4 with distinct sentinels, push them with MOVML.L,
! clobber R0..R4, then pop them back with plain "mov.l @r15+,rk" (lowest
! address first => R0, then R1..R4) and check each equals its sentinel.
!
! Marker convention mirrors sim/tests/sh2a_movl12.S: 0 = pass at
! TEST_RESULT_ADDRESS, non-zero = distinct fail code.

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
        .long _fail
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
        .global start
start:
        ! Seed R0..R4 with distinct sentinels from the literal pool.
        mov.l   p_s0, r0
        mov.l   p_s1, r1
        mov.l   p_s2, r2
        mov.l   p_s3, r3
        mov.l   p_s4, r4
        nop

        ! --- instruction under test: MOVML.L r4,@-r15 (push R4,R3,R2,R1,R0) ---
        .word   0x44F1

        ! Clobber R0..R4 so the pop-back genuinely reads memory.
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        nop

        ! Pop back: lowest address first == R0, then R1..R4.
        mov.l   @r15+, r0
        mov.l   @r15+, r1
        mov.l   @r15+, r2
        mov.l   @r15+, r3
        mov.l   @r15+, r4
        nop

        ! Verify each popped register equals its original sentinel.
        mov.l   p_s0, r7
        cmp/eq  r0, r7
        bf      _fail0
        mov.l   p_s1, r7
        cmp/eq  r1, r7
        bf      _fail1
        mov.l   p_s2, r7
        cmp/eq  r2, r7
        bf      _fail2
        mov.l   p_s3, r7
        cmp/eq  r3, r7
        bf      _fail3
        mov.l   p_s4, r7
        cmp/eq  r4, r7
        bf      _fail4

        ! Also confirm R15 is back where it started (0x7000): push then pop of
        ! 5 longs is net-neutral.
        mov.l   p_sp0, r7
        cmp/eq  r15, r7
        bf      _fail5

        bra     _done
        nop

        .align 2
p_s0:  .long 0xA0A0A000
p_s1:  .long 0xB1B1B111
p_s2:  .long 0xC2C2C222
p_s3:  .long 0xD3D3D333
p_s4:  .long 0xE4E4E444
p_sp0: .long 0x00007000

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop

! Distinct fail codes: N+1 => register RN mismatch; 6 => R15 not restored.
_fail0:
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail0
        nop
_fail1:
        mov.l   p_test_result, r0
        mov     #2, r9
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #3, r9
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #4, r9
        mov.l   r9, @r0
        bra     _fail3
        nop
_fail4:
        mov.l   p_test_result, r0
        mov     #5, r9
        mov.l   r9, @r0
        bra     _fail4
        nop
_fail5:
        mov.l   p_test_result, r0
        mov     #6, r9
        mov.l   r9, @r0
        bra     _fail5
        nop
_fail:
        mov.l   p_test_result, r0
        mov     #7, r9
        mov.l   r9, @r0
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
