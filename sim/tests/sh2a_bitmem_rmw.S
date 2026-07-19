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

        bra     _done
        nop

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0          ! 0 = pass
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
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
