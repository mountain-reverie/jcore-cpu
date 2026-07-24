! SH-2A memory bit-manipulation read-modify-write: BSET.B #imm3,@(disp12,Rn)
!
! Group 3 PR-A cosim. Exercises the two-word "nd12i3" format byte-RMW added to
! decode/gen-go/spec/sh2a/bitmem.toml: EA=Rn+disp12 is precomputed into TEMP1,
! the byte is READ into TEMP0, OR'd with the decode-time one-hot MASK3_64 mask,
! then WRITTEN back.
!
! Assembled with native SH-2A nd12i3 mnemonics (bset.b/bclr.b/bst.b/bld.b/
! bldnot.b/band.b/bandnot.b/bor.b/bornot.b/bxor.b #imm3,@(disp12,Rn)); gas
! requires -Wa,--isa=sh2a to accept this format. The encoding is:
!   word1 = 0011 nnnn 0iii 1001  (n = Rn, iii = imm3)
!   word2 = eeee dddd dddd dddd  (eeee = op-select, disp12, byte-scaled x1)
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
        bset.b  #3, @(4, r2)
        mov.b   @(4, r2), r0     ! mov.b @(disp,Rn) targets R0 only
        extu.b  r0, r0
        mov     #0x89, r6       ! 0x89 has bit7 set -> mov # sign-extends;
        extu.b  r6, r6          ! extu.b to match the zero-extended readback
        cmp/eq  r0, r6
        bf      _fail1

        ! --- case 2: bset.b #0,@(0,r2): 0x00 -> 0x01 (bit0, disp=0) ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        bset.b  #0, @(0, r2)
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail2

        ! --- case 3: bset.b #7,@(0,r2): 0x7F -> 0xFF (bit7, disp=0) ---
        mov     #0x7F, r0
        mov.b   r0, @(0, r2)
        bset.b  #7, @(0, r2)
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0xFF, r6       ! mov #0xFF sign-extends to 0xFFFFFFFF;
        extu.b  r6, r6          ! extu.b -> 0x000000FF to match the extu'd load
        cmp/eq  r0, r6
        bf      _fail3

        ! --- case 4: load-use with NO filler (fetch/prefetch fix guard) ---
        mov     #0x7F, r0
        mov.b   r0, @(8, r2)
        bset.b  #7, @(8, r2)
        mov.b   @(8, r2), r0     ! LOAD  (immediately follows the RMW)
        extu.b  r0, r0           ! USE   (must NOT be swallowed by the RMW)
        mov     #0xFF, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail4

        ! --- case 5: bclr.b #3,@(4,r2): 0x89 -> 0x81 (clear mid bit, disp!=0) ---
        mov     #0x89, r0
        mov.b   r0, @(4, r2)
        bclr.b  #3, @(4, r2)
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
        bst.b   #5, @(0, r2)
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x20, r6
        cmp/eq  r0, r6
        bf      _fail6

        ! --- case 7: bst.b #5,@(0,r2) with T=0: 0xFF -> 0xDF (bit5 cleared) ---
        mov     #0xFF, r0
        mov.b   r0, @(0, r2)
        clrt                     ! T = 0
        bst.b   #5, @(0, r2)
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0xDF, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail7

        ! --- case 8: bld.b #0,@(0,r2): byte=0x01 (bit0 SET) -> T=1, mem unchanged ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        bld.b   #0, @(0, r2)
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
        bld.b   #7, @(0, r2)
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
        bldnot.b #0, @(0, r2)
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
        bldnot.b #7, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail11
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x7F, r6
        cmp/eq  r0, r6
        bf      _fail11

        ! Also covers band.b/bandnot.b/bor.b/bornot.b/bxor.b (Group 3 PR-C):
        ! T-combine memory bit ops. T_new = T_old <op> bit, bit = mem-bit
        ! imm3. NO store, NO GPR write -- same 14-slot skeleton as bld/bldnot
        ! (word1 shared "0011 nnnn 0iii 1001"), ext[15:12] = 0100 (band) /
        ! 1100 (bandnot) / 0101 (bor) / 1101 (bornot) / 0110 (bxor),
        ! discriminated at the modify slot. Each op is exercised with all 4
        ! (T_old, bit) combinations, and imm3 extremes 0 (T=1 cases) and 7
        ! (T=0 cases). Memory byte verified UNCHANGED after each op.

        ! --- case 12: band.b #0,@(0,r2): T=1, bit0=1 -> T=1&1=1 ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        sett
        band.b  #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail12
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail12

        ! --- case 13: band.b #0,@(0,r2): T=1, bit0=0 -> T=1&0=0 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        sett
        band.b  #0, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail13
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail13

        ! --- case 14: band.b #7,@(0,r2): T=0, bit7=1 -> T=0&1=0 ---
        mov     #0x80, r0
        mov.b   r0, @(0, r2)
        clrt
        band.b  #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail14
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x80, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail14

        ! --- case 15: band.b #7,@(0,r2): T=0, bit7=0 -> T=0&0=0 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        clrt
        band.b  #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail15
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail15

        ! --- case 16: bandnot.b #0,@(0,r2): T=1, bit0=1 -> T=1&~1=0 ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        sett
        bandnot.b #0, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail16
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail16

        ! --- case 17: bandnot.b #0,@(0,r2): T=1, bit0=0 -> T=1&~0=1 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        sett
        bandnot.b #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail17
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail17

        ! --- case 18: bandnot.b #7,@(0,r2): T=0, bit7=1 -> T=0&~1=0 ---
        mov     #0x80, r0
        mov.b   r0, @(0, r2)
        clrt
        bandnot.b #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail18
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x80, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail18

        ! --- case 19: bandnot.b #7,@(0,r2): T=0, bit7=0 -> T=0&~0=0 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        clrt
        bandnot.b #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail19
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail19

        ! --- case 20: bor.b #0,@(0,r2): T=1, bit0=1 -> T=1|1=1 ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        sett
        bor.b   #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail20
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail20

        ! --- case 21: bor.b #0,@(0,r2): T=1, bit0=0 -> T=1|0=1 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        sett
        bor.b   #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail21
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail21

        ! --- case 22: bor.b #7,@(0,r2): T=0, bit7=1 -> T=0|1=1 ---
        mov     #0x80, r0
        mov.b   r0, @(0, r2)
        clrt
        bor.b   #7, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail22
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x80, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail22

        ! --- case 23: bor.b #7,@(0,r2): T=0, bit7=0 -> T=0|0=0 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        clrt
        bor.b   #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail23
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail23

        ! --- case 24: bornot.b #0,@(0,r2): T=1, bit0=1 -> T=1|~1=1 ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        sett
        bornot.b #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail24
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail24

        ! --- case 25: bornot.b #0,@(0,r2): T=1, bit0=0 -> T=1|~0=1 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        sett
        bornot.b #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail25
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail25

        ! --- case 26: bornot.b #7,@(0,r2): T=0, bit7=1 -> T=0|~1=0 ---
        mov     #0x80, r0
        mov.b   r0, @(0, r2)
        clrt
        bornot.b #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail26
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x80, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail26

        ! --- case 27: bornot.b #7,@(0,r2): T=0, bit7=0 -> T=0|~0=1 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        clrt
        bornot.b #7, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail27
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail27

        ! --- case 28: bxor.b #0,@(0,r2): T=1, bit0=1 -> T=1^1=0 ---
        mov     #0x01, r0
        mov.b   r0, @(0, r2)
        sett
        bxor.b  #0, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail28
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x01, r6
        cmp/eq  r0, r6
        bf      _fail28

        ! --- case 29: bxor.b #0,@(0,r2): T=1, bit0=0 -> T=1^0=1 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        sett
        bxor.b  #0, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail29
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail29

        ! --- case 30: bxor.b #7,@(0,r2): T=0, bit7=1 -> T=0^1=1 ---
        mov     #0x80, r0
        mov.b   r0, @(0, r2)
        clrt
        bxor.b  #7, @(0, r2)
        movt    r0
        mov     #1, r6
        cmp/eq  r0, r6
        bf      _fail30
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x80, r6
        extu.b  r6, r6
        cmp/eq  r0, r6
        bf      _fail30

        ! --- case 31: bxor.b #7,@(0,r2): T=0, bit7=0 -> T=0^0=0 ---
        mov     #0x00, r0
        mov.b   r0, @(0, r2)
        clrt
        bxor.b  #7, @(0, r2)
        movt    r0
        mov     #0, r6
        cmp/eq  r0, r6
        bf      _fail31
        mov.b   @(0, r2), r0
        extu.b  r0, r0
        mov     #0x00, r6
        cmp/eq  r0, r6
        bf      _fail31

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
_fail12:
        mov.l   p_test_result, r0
        mov     #12, r9
        mov.l   r9, @r0
        bra     _fail12
        nop
_fail13:
        mov.l   p_test_result, r0
        mov     #13, r9
        mov.l   r9, @r0
        bra     _fail13
        nop
_fail14:
        mov.l   p_test_result, r0
        mov     #14, r9
        mov.l   r9, @r0
        bra     _fail14
        nop
_fail15:
        mov.l   p_test_result, r0
        mov     #15, r9
        mov.l   r9, @r0
        bra     _fail15
        nop
_fail16:
        mov.l   p_test_result, r0
        mov     #16, r9
        mov.l   r9, @r0
        bra     _fail16
        nop
_fail17:
        mov.l   p_test_result, r0
        mov     #17, r9
        mov.l   r9, @r0
        bra     _fail17
        nop
_fail18:
        mov.l   p_test_result, r0
        mov     #18, r9
        mov.l   r9, @r0
        bra     _fail18
        nop
_fail19:
        mov.l   p_test_result, r0
        mov     #19, r9
        mov.l   r9, @r0
        bra     _fail19
        nop
_fail20:
        mov.l   p_test_result, r0
        mov     #20, r9
        mov.l   r9, @r0
        bra     _fail20
        nop
_fail21:
        mov.l   p_test_result, r0
        mov     #21, r9
        mov.l   r9, @r0
        bra     _fail21
        nop
_fail22:
        mov.l   p_test_result, r0
        mov     #22, r9
        mov.l   r9, @r0
        bra     _fail22
        nop
_fail23:
        mov.l   p_test_result, r0
        mov     #23, r9
        mov.l   r9, @r0
        bra     _fail23
        nop
_fail24:
        mov.l   p_test_result, r0
        mov     #24, r9
        mov.l   r9, @r0
        bra     _fail24
        nop
_fail25:
        mov.l   p_test_result, r0
        mov     #25, r9
        mov.l   r9, @r0
        bra     _fail25
        nop
_fail26:
        mov.l   p_test_result, r0
        mov     #26, r9
        mov.l   r9, @r0
        bra     _fail26
        nop
_fail27:
        mov.l   p_test_result, r0
        mov     #27, r9
        mov.l   r9, @r0
        bra     _fail27
        nop
_fail28:
        mov.l   p_test_result, r0
        mov     #28, r9
        mov.l   r9, @r0
        bra     _fail28
        nop
_fail29:
        mov.l   p_test_result, r0
        mov     #29, r9
        mov.l   r9, @r0
        bra     _fail29
        nop
_fail30:
        mov.l   p_test_result, r0
        mov     #30, r9
        mov.l   r9, @r0
        bra     _fail30
        nop
_fail31:
        mov.l   p_test_result, r0
        mov     #31, r9
        mov.l   r9, @r0
        bra     _fail31
        nop
_end:
        bra     _end
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
