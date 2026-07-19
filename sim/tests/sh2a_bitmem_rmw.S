! SH-2A memory bit-manipulation read-modify-write: BSET.B #imm3,@(disp12,Rn)
!
! Group 3 PR-A cosim. Exercises the two-word "nd12i3" format byte-RMW added to
! decode/gen-go/spec/sh2a/bitmem.toml: EA=Rn+disp12 is precomputed into TEMP1,
! the byte is READ into TEMP0, OR'd with the decode-time one-hot MASK3_64 mask,
! then WRITTEN back.
!
! sh2-elf-as (plain -m2) does not know the SH-2A "nd12i3" format, so the two-word
! opcode is hand-encoded via .word:
!   word1 = 0011 nnnn 0iii 1001  (n = Rn, iii = imm3)
!   word2 = 0001 dddd dddd dddd  (disp12, byte-scaled x1)
!
! Cases (bit-position extremes + disp=0 vs disp!=0):
!   1. bset.b #3,@(4,r2)   0x81 -> 0x89   (mid bit, disp!=0)
!   2. bset.b #0,@(0,r2)   0x00 -> 0x01   (bit0, disp=0)
!   3. bset.b #7,@(0,r2)   0x7F -> 0xFF   (bit7 = mask MSB, disp=0)
!   4. load-use with NO filler after the RMW: mov.b @,r0 ; extu.b r0,r0. This
!      guards the fetch/prefetch fix -- a mis-accounted two-word RMW drops the
!      instruction after itself, so the dependent USE (extu.b) would be swallowed
!      and r0 would keep the raw sign-extended load. It must round-trip to 0xFF.
!
! Also covers BLD.B/BLDNOT.B #imm3,@(disp12,Rn) (Group 3 PR-B): load byte,
! extract bit imm3 -> T (bldnot inverted). NO store -- same 14-slot skeleton,
! ext[15:12] = 0011 (bld) / 1011 (bldnot), discriminated at the modify slot.
! Cases 8-11 cover bit SET/CLEAR x bld/bldnot, plus imm3 extremes 0 and 7, and
! verify the memory byte is UNCHANGED (movt readback of T after each op).
!
! Marker convention: 0 = pass at TEST_RESULT_ADDRESS, non-zero = distinct fail.

#include "sim_instr.h"

        .section .vect
        .long start             ! 0: power-on PC
        .long 0x00007000        ! 1: power-on SP (inside RAM)
        .long start             ! 2: manual reset PC
        .long 0x00007000        ! 3: manual reset SP
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
        ! RAM scratch buffer below the initial SP (ROM/.text is not writable).
        mov     #-64, r2
        add     r15, r2

        ! --- case 1: bset.b #3,@(4,r2): 0x81 -> 0x89 (mid bit, disp!=0) ---
        mov     #0x81, r0
        mov.b   r0, @(4, r2)     ! seed target byte
        .word   0x3239          ! word1: BSET.B #3,@(disp12,r2)
        .word   0x1004          ! word2: disp12 = 4
        mov.b   @(4, r2), r0     ! mov.b @(disp,Rn) targets R0 only
        extu.b  r0, r0
        mov     #0x89, r6       ! 0x89 has bit7 set -> mov # sign-extends;
        extu.b  r6, r6          ! extu.b to match the zero-extended readback
        cmp/eq  r0, r6
        bf      _fail1

        ! --- case 2: bset.b #0,@(0,r2): 0x00 -> 0x01 (bit0, disp=0) ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        .word   0x3209          ! word1: BSET.B #0,@(disp12,r2)
        .word   0x1000          ! word2: disp12 = 0
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail2

        ! --- case 3: bset.b #7,@(0,r2): 0x7F -> 0xFF (bit7, disp=0) ---
        mov     #0x7F, r0
        mov.b   r0, @(0, r2)
        .word   0x3279          ! word1: BSET.B #7,@(disp12,r2)
        .word   0x1000          ! word2: disp12 = 0
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0xFF, r6       ! mov #0xFF sign-extends to 0xFFFFFFFF;
        extu.b  r6, r6          ! extu.b -> 0x000000FF to match the extu'd load
        cmp/eq  r0, r6
        bf      _fail3

        ! --- case 4: load-use with NO filler (fetch/prefetch fix guard) ---
        mov     #0x7F, r0
        mov.b   r0, @(8, r2)
        .word   0x3279          ! word1: BSET.B #7,@(disp12,r2)
        .word   0x1008          ! word2: disp12 = 8
        mov.b   @(8, r2), r0     ! LOAD  (immediately follows the RMW)
        extu.b  r0, r0           ! USE   (must NOT be swallowed by the RMW)
        mov     #0xFF, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail4

        ! --- case 5: bclr.b #3,@(4,r2): 0x89 -> 0x81 (clear mid bit, disp!=0) ---
        mov     #0x89, r0
        mov.b   r0, @(4, r2)
        .word   0x3239          ! word1: BCLR.B #3,@(disp12,r2)
        .word   0x2004          ! word2: ext=0010 (bclr), disp12 = 4
        mov.b   @(4, r2), r0
        extu.b  r0, r0
        mov     #0x81, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail5

        ! --- case 6: bst.b #5,@(0,r2) with T=1: 0x00 -> 0x20 (insert T into bit5) ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        sett                     ! T = 1
        .word   0x3259          ! word1: BST.B #5,@(disp12,r2)
        .word   0x7000          ! word2: ext=0111 (bst), disp12 = 0
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x20, r6
        cmp/eq  r0, r6
        bf      _fail6

        ! --- case 7: bst.b #5,@(0,r2) with T=0: 0xFF -> 0xDF (bit5 cleared) ---
        mov     #0xFF, r0
        mov.b   r0, @(0, r2)
        clrt                     ! T = 0
        .word   0x3259          ! word1: BST.B #5,@(disp12,r2)
        .word   0x7000          ! word2: ext=0111 (bst), disp12 = 0
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0xDF, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail7

        ! --- case 8: bld.b #0,@(0,r2): byte=0x01 (bit0 SET) -> T=1, mem unchanged ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        .word   0x3209          ! word1: BLD.B #0,@(disp12,r2)
        .word   0x3000          ! word2: ext=0011 (bld), disp12 = 0
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail8
        mov.b   @(0, r2), r0    ! verify memory byte is UNCHANGED (no store)
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail8

        ! --- case 9: bld.b #7,@(0,r2): byte=0x7F (bit7 CLEAR) -> T=0, mem unchanged ---
        mov     #0x7F, r0
        mov.b   r0, @(0, r2)
        .word   0x3279          ! word1: BLD.B #7,@(disp12,r2)
        .word   0x3000          ! word2: ext=0011 (bld), disp12 = 0
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail9
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x7F, r6
        cmp/eq  r0, r6
        bf      _fail9

        ! --- case 10: bldnot.b #0,@(0,r2): byte=0x01 (bit0 SET) -> T=0 (inverted) ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        .word   0x3209          ! word1: BLDNOT.B #0,@(disp12,r2)
        .word   0xB000          ! word2: ext=1011 (bldnot), disp12 = 0
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail10
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail10

        ! --- case 11: bldnot.b #7,@(0,r2): byte=0x7F (bit7 CLEAR) -> T=1 (inverted) ---
        mov     #0x7F, r0
        mov.b   r0, @(0, r2)
        .word   0x3279          ! word1: BLDNOT.B #7,@(disp12,r2)
        .word   0xB000          ! word2: ext=1011 (bldnot), disp12 = 0
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail11
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x7F, r6
        cmp/eq  r0, r6
        bf      _fail11

        bra     _done
        nop

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0          ! 0 = pass
        bra     _end
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
_fail9:
        mov.l   p_test_result, r0
        mov     #9, r9
        mov.l   r9, @r0
        bra     _fail9
        nop
_fail10:
        mov.l   p_test_result, r0
        mov     #10, r9
        mov.l   r9, @r0
        bra     _fail10
        nop
_fail11:
        mov.l   p_test_result, r0
        mov     #11, r9
        mov.l   r9, @r0
        bra     _fail11
        nop
_end:
        bra     _end
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
