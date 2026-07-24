! SH-2A two-word instruction: MOVU.B/MOVU.W @(disp12,Rm),Rn unsigned
! (zero-extending) byte/word loads.
!
! Task 3 (feat/j2a-group1-disp12): adds the unsigned counterparts of
! MOV.B/MOV.W @(disp12,Rm),Rn (sh2a_disp12bw.S, Task 2). Same word1
! "0011 nnnn mmmm 0001"; only the extension word's high nibble tells them
! apart:
!   byte load (sign)   = 0100   byte load (unsigned) = 1000
!   word load (sign)   = 0101   word load (unsigned) = 1001
!
! Uses native SH-2A MOVU.B/MOVU.W @(disp12,Rm),Rn and MOV.B/MOV.W
! Rm,@(disp12,Rn) mnemonics (requires -Wa,--isa=sh2a).
!
! Cases:
!   1. byte round-trip, disp12=0, positive value (baseline, no extension
!      visible either way)
!   2. word round-trip, disp12=0, positive value (baseline)
!   3. byte zero-extension: store 0x80, load with MOVU.B, expect
!      0x00000080 (CONTRAST: MOV.B sign-extending load gives 0xFFFFFF80,
!      see sh2a_disp12bw.S case 5)
!   4. word zero-extension: store 0x8000, load with MOVU.W, expect
!      0x00008000 (CONTRAST: MOV.W sign-extending load gives 0xFFFF8000,
!      see sh2a_disp12bw.S case 6)
!
! Marker convention mirrors sim/tests/banktest.S: 0 = pass at
! TEST_RESULT_ADDRESS, non-zero = fail (distinct codes per case below).

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
        .long 0
_sim_instr_end: .long 0

        .text
        .global start
start:
        ! --- case 1: MOVU.B round-trip, disp12=0, positive value ---
        mov.l   p_seed1, r1              ! r1 = 0x00000045
        mov.l   p_scratch_b1, r2         ! r2 = byte scratch addr

        mov.b   r1,@(0,r2)
        nop
        nop
        movu.b  @(0,r2),r5
        nop
        nop

        cmp/eq  r1, r5
        bf      _fail1

        ! --- case 2: MOVU.W round-trip, disp12=0, positive value ---
        mov.l   p_seed2, r1              ! r1 = 0x00001234
        mov.l   p_scratch_w1, r3         ! r3 = word scratch addr

        mov.w   r1,@(0,r3)
        nop
        nop
        movu.w  @(0,r3),r6
        nop
        nop

        cmp/eq  r1, r6
        bf      _fail2

        ! --- case 3: MOVU.B zero-extension: store 0x80, expect 0x00000080 ---
        mov.l   p_seed3, r1              ! r1 = 0x00000080
        mov.l   p_scratch_b2, r2         ! r2 = byte scratch addr

        mov.b   r1,@(0,r2)
        nop
        nop
        movu.b  @(0,r2),r7
        nop
        nop

        mov.l   p_expect3, r0            ! r0 = 0x00000080
        cmp/eq  r0, r7
        bf      _fail3

        ! --- case 4: MOVU.W zero-extension: store 0x8000, expect 0x00008000 ---
        mov.l   p_seed4, r1              ! r1 = 0x00008000
        mov.l   p_scratch_w2, r3         ! r3 = word scratch addr

        mov.w   r1,@(0,r3)
        nop
        nop
        movu.w  @(0,r3),r8
        nop
        nop

        mov.l   p_expect4, r0            ! r0 = 0x00008000
        cmp/eq  r0, r8
        bf      _fail4

        bra     _done
        nop

        .align 4
p_seed1:        .long 0x00000045
p_scratch_b1:    .long scratch_b1
p_seed2:        .long 0x00001234
p_scratch_w1:    .long scratch_w1
p_seed3:        .long 0x00000080
p_scratch_b2:    .long scratch_b2
p_expect3:      .long 0x00000080
p_seed4:        .long 0x00008000
p_scratch_w2:    .long scratch_w2
p_expect4:      .long 0x00008000

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail1:
        mov.l   p_test_result, r0
        mov     #1, r9          ! 1 = case 1 (MOVU.B, disp=0) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #2, r9          ! 2 = case 2 (MOVU.W, disp=0) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #3, r9          ! 3 = case 3 (MOVU.B zero-extension) mismatch
        mov.l   r9, @r0
        bra     _fail3
        nop
_fail4:
        mov.l   p_test_result, r0
        mov     #4, r9          ! 4 = case 4 (MOVU.W zero-extension) mismatch
        mov.l   r9, @r0
        bra     _fail4
        nop
_fail_loop:
        mov.l   p_test_result, r0
        mov     #7, r9          ! 7 = generic/unexpected fault
        mov.l   r9, @r0
        bra     _fail_loop
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS

        .align 4
scratch_b1: .long 0x11111111
scratch_w1: .long 0x22222222
scratch_b2: .long 0x33333333
scratch_w2: .long 0x44444444
