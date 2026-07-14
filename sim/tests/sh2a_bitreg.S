! SH-2A register bit-manipulation instructions: BCLR/BSET/BST/BLD #imm3,Rn.
!
! Task 1 (Group 6) guard. Exercises the new "ni3" format + decode-time
! IMM_BIT3_MASK/IMM_BIT3_MASK_INV masks (BSET/BCLR/BLD) and the new
! zbus_sel=SEL_BITSET datapath path (BST) added in core/datapath.vhm.
!
! sh2-elf-as (plain -m2) does not know the SH-2A "ni3" format, so every
! bit-op opcode is hand-encoded via .word. Encoding: nnnn = op.code(11:8)
! (Rn), iii = op.code(2:0) (imm3), and op.code(3) distinguishes
! BCLR/BST (0) from BSET/BLD (1):
!   BCLR #imm3,Rn = 1000 0110 nnnn 0iii
!   BSET #imm3,Rn = 1000 0110 nnnn 1iii
!   BST  #imm3,Rn = 1000 0111 nnnn 0iii
!   BLD  #imm3,Rn = 1000 0111 nnnn 1iii
!
! Marker convention mirrors sim/tests/sh2a_movl12.S: 0 = pass at
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
        .long _fail1
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
        .global start
start:
        ! --- case 1: BSET #3,r1 (r1=0 -> expect bit3 set = 8) ---
        mov     #0, r1
        .word   0x861B          ! BSET #3,r1
        nop
        mov     #8, r5
        cmp/eq  r1, r5
        bf      _fail1

        ! --- case 2: BCLR #3,r1 (r1=8 -> expect cleared = 0) ---
        .word   0x8613          ! BCLR #3,r1
        nop
        mov     #0, r5
        cmp/eq  r1, r5
        bf      _fail2

        ! --- case 3: BSET #0,r1 boundary (r1=0 -> expect 1) ---
        mov     #0, r1
        .word   0x8618          ! BSET #0,r1
        nop
        mov     #1, r5
        cmp/eq  r1, r5
        bf      _fail3

        ! --- case 4: BSET #7,r1 boundary (r1=0 -> expect 0x80) ---
        mov     #0, r1
        .word   0x861F          ! BSET #7,r1
        nop
        mov.l   p_0x80, r5
        cmp/eq  r1, r5
        bf      _fail4

        ! --- case 5: BLD #3,r2 with bit clear -> T=0 ---
        mov     #0, r2
        .word   0x872B          ! BLD #3,r2
        nop
        movt    r0
        mov     #0, r5
        cmp/eq  r0, r5
        bf      _fail5

        ! --- case 6: BLD #3,r2 with bit set -> T=1 ---
        mov     #8, r2
        .word   0x872B          ! BLD #3,r2
        nop
        movt    r0
        mov     #1, r5
        cmp/eq  r0, r5
        bf      _fail6

        ! --- case 7: BST #5,r3 with T=1 -> bit5 set (r3=0 -> 0x20) ---
        sett
        mov     #0, r3
        .word   0x8735          ! BST #5,r3
        nop
        mov     #0x20, r5
        cmp/eq  r3, r5
        bf      _fail7

        ! --- case 8: BST #5,r3 with T=0 -> bit5 cleared (r3=-1 -> ~0x20) ---
        clrt
        mov     #-1, r3
        .word   0x8735          ! BST #5,r3
        nop
        mov.l   p_not_0x20, r5
        cmp/eq  r3, r5
        bf      _fail8

        bra     _done
        nop

        .align 2
p_0x80:      .long 0x00000080
p_not_0x20:  .long 0xFFFFFFDF

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail1:
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #2, r9
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #3, r9
        mov.l   r9, @r0
        bra     _fail3
        nop
_fail4:
        mov.l   p_test_result, r0
        mov     #4, r9
        mov.l   r9, @r0
        bra     _fail4
        nop
_fail5:
        mov.l   p_test_result, r0
        mov     #5, r9
        mov.l   r9, @r0
        bra     _fail5
        nop
_fail6:
        mov.l   p_test_result, r0
        mov     #6, r9
        mov.l   r9, @r0
        bra     _fail6
        nop
_fail7:
        mov.l   p_test_result, r0
        mov     #7, r9
        mov.l   r9, @r0
        bra     _fail7
        nop
_fail8:
        mov.l   p_test_result, r0
        mov     #8, r9
        mov.l   r9, @r0
        bra     _fail8
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
