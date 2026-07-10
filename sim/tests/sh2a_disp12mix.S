! SH-2A two-word @(disp12,Rn) mov.l isolation matrix: exercises every
! back-to-back adjacency of two-word STORE / LOAD ops with NO nop spacing
! between the pair, which is what stresses the instruction-fetch prefetch
! race that corrupted store->load (the following op's extension word was
! sourced from a not-yet-advanced if_dr_next).
!
! word1 for both store and load = "0011 nnnn mmmm 0001":
!   store MOV.L Rm,@(disp,Rn): n=Rn(base) m=Rm(data), ext word2 hi nibble 0010
!   load  MOV.L @(disp,Rm),Rn: n=Rn(dest) m=Rm(base), ext word2 hi nibble 0110
! ext word2 low 12 bits = disp; byte offset = disp*4.
!
! Base register r2 = scratch. Seeds r1, r3. Fail markers are distinct.

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
        .long 0
_sim_instr_end: .long 0

        .text
        .global start
start:
        mov.l   p_seed1, r1            ! r1 = 0xAAAA1111
        mov.l   p_seed3, r3            ! r3 = 0xBBBB2222
        mov.l   p_scratch, r2          ! r2 = scratch base
        nop

        ! ---- store -> store (back to back, no nop between) ----
        .word   0x3211                 ! store r1 -> @(0,r2)
        .word   0x2000
        .word   0x3231                 ! store r3 -> @(1,r2)  (r2+4)
        .word   0x2001
        nop
        nop

        ! ---- load -> load (back to back) : read the two just-stored words ----
        .word   0x3421                 ! load @(0,r2) -> r4
        .word   0x6000
        .word   0x3521                 ! load @(1,r2) -> r5
        .word   0x6001
        nop
        nop
        cmp/eq  r1, r4
        bf      _fail_ll1
        cmp/eq  r3, r5
        bf      _fail_ll2

        ! ---- load -> store (back to back) : load r1 from (0), store it to (2) ----
        .word   0x3621                 ! load @(0,r2) -> r6
        .word   0x6000
        .word   0x3261                 ! store r6 -> @(2,r2)  (r2+8)
        .word   0x2002
        nop
        nop
        ! read (2) back with spacing, verify == r1
        .word   0x3721                 ! load @(2,r2) -> r7
        .word   0x6002
        nop
        nop
        cmp/eq  r1, r7
        bf      _fail_ls

        ! ---- store -> load (back to back) : the original failing case ----
        .word   0x3231                 ! store r3 -> @(3,r2)  (r2+12)
        .word   0x2003
        .word   0x3821                 ! load @(3,r2) -> r8
        .word   0x6003
        nop
        nop
        cmp/eq  r3, r8
        bf      _fail_sl

        bra     _done
        nop

        .align 4
p_seed1:   .long 0xAAAA1111
p_seed3:   .long 0xBBBB2222
p_scratch: .long scratch

        .global _done
_done:
        mov.l   p_res, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail_ll1:
        mov.l   p_res, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail_ll1
        nop
_fail_ll2:
        mov.l   p_res, r0
        mov     #2, r9
        mov.l   r9, @r0
        bra     _fail_ll2
        nop
_fail_ls:
        mov.l   p_res, r0
        mov     #3, r9
        mov.l   r9, @r0
        bra     _fail_ls
        nop
_fail_sl:
        mov.l   p_res, r0
        mov     #4, r9
        mov.l   r9, @r0
        bra     _fail_sl
        nop
_fail:
        mov.l   p_res, r0
        mov     #5, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_res:  .long TEST_RESULT_ADDRESS

        .align 4
scratch: .space 0x40
