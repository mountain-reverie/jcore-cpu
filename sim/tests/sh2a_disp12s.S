! SH-2A two-word instruction round-trip: MOV.L Rm,@(disp12,Rn) store, then
! MOV.L @(disp12,Rm),Rn load-back.
!
! Task 1 (feat/j2a-group1-disp12): proves the generator's ext_word[15:12]
! discrimination end-to-end. Both instructions share word1
! "0011 nnnn mmmm 0001"; only the extension word's high nibble tells them
! apart (store = 0010, load = 0110). Before the discrimination fix, the
! decoder's elsif chain (simple table) / QMC-reduced expression (direct
! table) could not distinguish the two -- one instruction's microcode
! silently executed in place of the other.
!
! sh2-elf-as (plain -m2) does not know the SH-2A "nmd12" format, so both
! two-word opcodes are hand-encoded via .word:
!   store: word1 = 0x3n m1 (0011 nnnn mmmm 0001), word2 = 0x2ddd (disp12)
!   load:  word1 = 0x3n m1 (0011 nnnn mmmm 0001), word2 = 0x6ddd (disp12)
!
! Two cases:
!   1. disp12 = 0: store r1 -> @(0,r2), then load @(0,r4),r5 back from the
!      same address (r4 = r2), verify r5 == r1.
!   2. disp12 = large (0xFFF, the max 12-bit value -> byte offset
!      0xFFF*4 = 0x3FFC): store r1 -> @(0xFFF,r2) i.e. @(r2+0x3FFC), then
!      load @(0xFFF,r6),r7 (r6 = r2) back, verify r7 == r1.
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
        .long 0
_sim_instr_end: .long 0

        .text
        .global start
start:
        ! --- case 1: disp12 = 0 ---
        mov.l   p_seed1, r1             ! seed value to round-trip
        mov.l   p_scratch1, r2          ! r2 = scratch word address (disp12=0 base)
        nop

        ! Register roles for word1 "0011 nnnn mmmm 0001":
        !   n = Rn (base address register), m = Rm (data/dest register).
        !   r1 = seed value (data to store)
        !   r2 = scratch address (base register for both store and load)
        ! store: MOV.L r1,@(0,r2)  ->  n=2(Rn=r2 base), m=1(Rm=r1 data)
        !   word1 = 0011 0010 0001 0001 = 0x3211
        ! load:  MOV.L @(0,r2),r5 ->  n=5(Rn=r5 dest), m=2(Rm=r2 base)
        !   word1 = 0011 0101 0010 0001 = 0x3521
        .word   0x3211                  ! word1: MOV.L Rm,@(disp12,Rn) n=2(r2) m=1(r1)
        .word   0x2000                  ! word2: disp12 = 0  -> store r1 @ (r2+0)
        nop
        nop
        .word   0x3521                  ! word1: MOV.L @(disp12,Rm),Rn n=5(r5) m=2(r2)
        .word   0x6000                  ! word2: disp12 = 0  -> load (r2+0) into r5
        nop
        nop

        cmp/eq  r1, r5
        bf      _fail_loop

        ! --- case 2: disp12 = 0xFFF (max 12-bit value, byte offset 0x3FFC) ---
        mov.l   p_seed2, r1              ! new seed value
        mov.l   p_scratch2_base, r2      ! r2 = base such that base+0x3FFC is writable scratch

        ! store: MOV.L r1,@(0xFFF,r2)  -> n=2(Rn=r2 base), m=1(Rm=r1 data)
        !   word1 = 0x3211 (same register assignment as case 1)
        .word   0x3211
        .word   0x2fff                   ! word2: disp12 = 0xFFF (store)
        nop
        nop
        ! load: MOV.L @(0xFFF,r2),r6 -> n=6(r6 dest), m=2(Rm=r2 base)
        !   word1 = 0011 0110 0010 0001 = 0x3621
        .word   0x3621
        .word   0x6fff                   ! word2: disp12 = 0xFFF (load)
        nop
        nop

        cmp/eq  r1, r6
        bf      _fail_loop2
        bra     _done
        nop

        .align 4
p_seed1:          .long 0xA5A5A5A5
p_scratch1:       .long scratch1
p_seed2:          .long 0x5A5A5A5A
p_scratch2_base:  .long scratch2_base

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail_loop:
        mov.l   p_test_result, r0
        mov     #1, r9         ! 1 = case 1 (disp12=0) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail_loop
        nop
_fail_loop2:
        mov.l   p_test_result2, r0
        mov     #2, r9         ! 2 = case 2 (disp12=0xFFF) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail_loop2
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS
p_test_result2: .long TEST_RESULT_ADDRESS

        .align 4
scratch1: .long 0x11111111

        ! scratch2_base positioned so that scratch2_base + 0x3FFC (disp12=0xFFF,
        ! *4) lands well inside RAM; give it generous headroom.
        .align 4
scratch2_base: .space 0x4000
