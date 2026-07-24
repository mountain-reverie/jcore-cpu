! SH-2A two-word instruction round-trip: MOV.B/MOV.W @(disp12,Rm),Rn loads and
! MOV.B/MOV.W Rm,@(disp12,Rn) stores.
!
! Task 2 (feat/j2a-group1-disp12): adds byte/word variants of the disp12
! load/store family alongside the MOV.L version (sh2a_disp12s.S). All four
! share word1 "0011 nnnn mmmm 0001" with the .L load/store; only the
! extension word's high nibble (ext_word[15:12]) tells them apart:
!   byte load  = 0100   word load  = 0101
!   byte store = 0000   word store = 0001
!
! These opcodes now use native SH-2A mov.b/mov.w @(disp12,Rm),Rn mnemonics,
! assembled with -Wa,--isa=sh2a. Each two-word op is a single mnemonic; the
! disp12 field lives in the extension word. gas takes the BYTE displacement,
! so a word op with disp12=0xFFF is written @(8190,Rn) (0xFFF*2).
!
! Cases:
!   1. byte round-trip, disp12=0, positive value (no sign-extension observed)
!   2. word round-trip, disp12=0, positive value
!   3. byte round-trip, disp12=0xFFF (max, byte offset 0xFFF)
!   4. word round-trip, disp12=0xFFF (max, byte offset 0x1FFE)
!   5. byte sign-extension: store 0x80, load back, expect 0xFFFFFF80
!   6. word sign-extension: store 0x8000, load back, expect 0xFFFF8000
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
        ! --- case 1: MOV.B round-trip, disp12=0, positive value ---
        mov.l   p_seed1, r1              ! r1 = 0x00000045
        mov.l   p_scratch_b1, r2         ! r2 = byte scratch addr

        mov.b   r1, @(0, r2)             ! store: byte, disp12=0
        nop
        nop
        mov.b   @(0, r2), r5             ! load: byte, disp12=0
        nop
        nop

        cmp/eq  r1, r5
        bf      _fail1

        ! --- case 2: MOV.W round-trip, disp12=0, positive value ---
        mov.l   p_seed2, r1              ! r1 = 0x00001234
        mov.l   p_scratch_w1, r3         ! r3 = word scratch addr

        mov.w   r1, @(0, r3)             ! store: word, disp12=0
        nop
        nop
        mov.w   @(0, r3), r6             ! load: word, disp12=0
        nop
        nop

        cmp/eq  r1, r6
        bf      _fail2

        ! --- case 3: MOV.B round-trip, disp12=0xFFF ---
        mov.l   p_seed3, r1              ! r1 = 0x00000067
        mov.l   p_scratch_b2, r2         ! r2 = byte scratch base (offset 0xFFF from here)

        mov.b   r1, @(4095, r2)          ! store: byte, disp12=0xFFF
        nop
        nop
        mov.b   @(4095, r2), r7          ! load: byte, disp12=0xFFF
        nop
        nop

        cmp/eq  r1, r7
        bf      _fail3

        ! --- case 4: MOV.W round-trip, disp12=0xFFF (byte offset 0x1FFE) ---
        mov.l   p_seed4, r1              ! r1 = 0x00001357
        mov.l   p_scratch_w2, r3         ! r3 = word scratch base

        mov.w   r1, @(8190, r3)          ! store: word, disp12=0xFFF (byte off 0x1FFE)
        nop
        nop
        mov.w   @(8190, r3), r8          ! load: word, disp12=0xFFF (byte off 0x1FFE)
        nop
        nop

        cmp/eq  r1, r8
        bf      _fail4

        ! --- case 5: MOV.B sign-extension: store 0x80, expect 0xFFFFFF80 ---
        mov.l   p_seed5, r1              ! r1 = 0x00000080
        mov.l   p_scratch_b3, r2         ! r2 = byte scratch addr

        mov.b   r1, @(0, r2)             ! store: byte, disp12=0
        nop
        nop
        mov.b   @(0, r2), r9             ! load: byte, disp12=0
        nop
        nop

        mov.l   p_expect5, r0            ! r0 = 0xFFFFFF80
        cmp/eq  r0, r9
        bf      _fail5

        ! --- case 6: MOV.W sign-extension: store 0x8000, expect 0xFFFF8000 ---
        mov.l   p_seed6, r1              ! r1 = 0x00008000
        mov.l   p_scratch_w3, r3         ! r3 = word scratch addr

        mov.w   r1, @(0, r3)             ! store: word, disp12=0
        nop
        nop
        mov.w   @(0, r3), r10            ! load: word, disp12=0
        nop
        nop

        mov.l   p_expect6, r0            ! r0 = 0xFFFF8000
        cmp/eq  r0, r10
        bf      _fail6

        bra     _done
        nop

        .align 4
p_seed1:        .long 0x00000045
p_scratch_b1:    .long scratch_b1
p_seed2:        .long 0x00001234
p_scratch_w1:    .long scratch_w1
p_seed3:        .long 0x00000067
p_scratch_b2:    .long scratch_b2_base
p_seed4:        .long 0x00001357
p_scratch_w2:    .long scratch_w2_base
p_seed5:        .long 0x00000080
p_scratch_b3:    .long scratch_b3
p_expect5:      .long 0xFFFFFF80
p_seed6:        .long 0x00008000
p_scratch_w3:    .long scratch_w3
p_expect6:      .long 0xFFFF8000

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail1:
        mov.l   p_test_result, r0
        mov     #1, r9          ! 1 = case 1 (byte, disp=0) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #2, r9          ! 2 = case 2 (word, disp=0) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #3, r9          ! 3 = case 3 (byte, disp=0xFFF) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail3
        nop
_fail4:
        mov.l   p_test_result, r0
        mov     #4, r9          ! 4 = case 4 (word, disp=0xFFF) round-trip mismatch
        mov.l   r9, @r0
        bra     _fail4
        nop
_fail5:
        mov.l   p_test_result, r0
        mov     #5, r9          ! 5 = case 5 (byte sign-extension) mismatch
        mov.l   r9, @r0
        bra     _fail5
        nop
_fail6:
        mov.l   p_test_result, r0
        mov     #6, r9          ! 6 = case 6 (word sign-extension) mismatch
        mov.l   r9, @r0
        bra     _fail6
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
scratch_b3: .long 0x33333333
scratch_w3: .long 0x44444444

        ! scratch2_base positioned so that scratch2_base + 0xFFF (byte, max
        ! disp) and scratch2_base + 0x1FFE (word, max disp*2) land well
        ! inside RAM; give generous headroom.
        .align 4
scratch_b2_base: .space 0x1010
        .align 4
scratch_w2_base: .space 0x2010
