! SH-2A MOVML.L @R15+,Rn (pop) bring-up: pop R0..Rn from the R15 stack.
!
! Exercises the decode_core.vhm (SH2A_ARCH) counted-loop sequencer counting the
! register index UP 0..n. Push R0..R4 with MOVML.L r4,@-r15 (0x44F1), clobber
! R0..R4, then pop them back with MOVML.L @r15+,r4 (0100 0100 1111 0101 = 0x44F5)
! and check each register equals its sentinel and R15 is net-restored.
!
! sh2-elf-as (-m2) does not know SH-2A MOVML.L, so opcodes are hand-encoded.
! Marker convention mirrors sim/tests/sh2a_movml.S: 0 = pass, non-zero = fail.

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
        mov.l   p_s0, r0
        mov.l   p_s1, r1
        mov.l   p_s2, r2
        mov.l   p_s3, r3
        mov.l   p_s4, r4
        nop

        ! push R4,R3,R2,R1,R0 (R15 -= 20)
        .word   0x44F1
        nop
        nop

        ! clobber so the pop genuinely reads memory
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        nop

        ! --- instruction under test: MOVML.L @r15+,r4 (pop R0..R4) ---
        .word   0x44F5
        nop
        nop

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
        mov.l   r9, @r0
        bra     _done
        nop

_fail0: mov.l p_test_result, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail0
        nop
_fail1: mov.l p_test_result, r0
        mov #2, r9
        mov.l r9, @r0
        bra _fail1
        nop
_fail2: mov.l p_test_result, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail2
        nop
_fail3: mov.l p_test_result, r0
        mov #4, r9
        mov.l r9, @r0
        bra _fail3
        nop
_fail4: mov.l p_test_result, r0
        mov #5, r9
        mov.l r9, @r0
        bra _fail4
        nop
_fail5: mov.l p_test_result, r0
        mov #6, r9
        mov.l r9, @r0
        bra _fail5
        nop
_fail:  mov.l p_test_result, r0
        mov #7, r9
        mov.l r9, @r0
        bra _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
