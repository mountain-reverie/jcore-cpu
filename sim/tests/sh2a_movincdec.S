! SH-2A mov extras (Group 5) bring-up: post-inc STORE / pre-dec LOAD with R0
! fixed as the data register -- the two Rn-addressing combos base SH-2 lacks.
!   mov.b r0,@rn+  = 0100 nnnn 1000 1011   (R0 -> (Rn), Rn+1 -> Rn)
!   mov.w r0,@rn+  = 0100 nnnn 1001 1011   (R0 -> (Rn), Rn+2 -> Rn)
!   mov.l r0,@rn+  = 0100 nnnn 1010 1011   (R0 -> (Rn), Rn+4 -> Rn)
!   mov.b @-rm,r0  = 0100 mmmm 1100 1011   (Rm-1 -> Rm, (Rm) -> sign_ext -> R0)
!   mov.w @-rm,r0  = 0100 mmmm 1101 1011   (Rm-2 -> Rm, (Rm) -> sign_ext -> R0)
!   mov.l @-rm,r0  = 0100 mmmm 1110 1011   (Rm-4 -> Rm, (Rm) -> R0)
!
! sh2-elf-as (-m2) does not know these SH-2A opcodes, so they are hand-encoded
! with .word. Post-inc store instructions use Rn=r2; pre-dec load instructions
! use Rm=r3. All addressing operands are computed into registers at runtime
! (mov.l <label>,rk) so no relocations are needed against the .word opcodes.
!
! Marker convention: 0 = pass at TEST_RESULT_ADDRESS, non-zero = fail code.

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
        ! ---------------------------------------------------------------
        ! (1) mov.b r0,@r2+ : post-inc store, byte.
        ! ---------------------------------------------------------------
        mov.l   p_buf_b, r2
        mov     r2, r4          ! r4 = saved original address
        mov.l   p_val_b, r0     ! r0 = 0x0000007A
        .word   0x428B          ! mov.b r0,@r2+  (Rn=r2)
        nop

        mov.b   @r4, r8         ! read back (sign-extended) via base mov.b
        mov.l   p_valx_b, r7    ! sign-extended expected: 0x0000007A
        cmp/eq  r7, r8
        bf      _fail1

        mov.l   p_addr_b1, r7   ! expected r2 = buf_b + 1
        cmp/eq  r2, r7
        bf      _fail1a

        ! ---------------------------------------------------------------
        ! (2) mov.w r0,@r2+ : post-inc store, word.
        ! ---------------------------------------------------------------
        mov.l   p_buf_w, r2
        mov     r2, r4
        mov.l   p_val_w, r0     ! r0 = 0x00001234
        .word   0x429B          ! mov.w r0,@r2+  (Rn=r2)
        nop

        mov.w   @r4, r8
        mov.l   p_valx_w, r7    ! sign-extended expected: 0x00001234
        cmp/eq  r7, r8
        bf      _fail2

        mov.l   p_addr_w1, r7   ! expected r2 = buf_w + 2
        cmp/eq  r2, r7
        bf      _fail2a

        ! ---------------------------------------------------------------
        ! (3) mov.l r0,@r2+ : post-inc store, longword.
        ! ---------------------------------------------------------------
        mov.l   p_buf_l, r2
        mov     r2, r4
        mov.l   p_val_l, r0     ! r0 = 0x89ABCDEF
        .word   0x42AB          ! mov.l r0,@r2+  (Rn=r2)
        nop

        mov.l   @r4, r8
        mov.l   p_val_l, r7
        cmp/eq  r7, r8
        bf      _fail3

        mov.l   p_addr_l1, r7  ! expected r2 = buf_l + 4
        cmp/eq  r2, r7
        bf      _fail3a

        ! ---------------------------------------------------------------
        ! (4) mov.b @-r3,r0 : pre-dec load, byte. Value has sign bit set to
        ! prove sign-extension.
        ! ---------------------------------------------------------------
        mov.l   p_buf_lb, r4    ! r4 = target address
        mov.l   p_val_lb, r1    ! r1 = 0xFFFFFF80 (low byte 0x80)
        mov.b   r1, @r4         ! seed memory@r4 = 0x80 via base mov.b

        mov.l   p_addr_lb1, r3  ! r3 = buf_lb + 1
        mov     #0, r0
        .word   0x43CB          ! mov.b @-r3,r0  (Rm=r3)
        nop

        mov.l   p_valx_lb, r7   ! expected R0 = sign_extend(0x80) = 0xFFFFFF80
        cmp/eq  r7, r0
        bf      _fail4

        cmp/eq  r4, r3          ! expected r3 == buf_lb (original address)
        bf      _fail4a

        ! ---------------------------------------------------------------
        ! (5) mov.w @-r3,r0 : pre-dec load, word. Sign bit set.
        ! ---------------------------------------------------------------
        mov.l   p_buf_lw, r4
        mov.l   p_val_lw, r1    ! r1 = 0xFFFF8001 (low word 0x8001)
        mov.w   r1, @r4

        mov.l   p_addr_lw1, r3  ! r3 = buf_lw + 2
        mov     #0, r0
        .word   0x43DB          ! mov.w @-r3,r0  (Rm=r3)
        nop

        mov.l   p_valx_lw, r7   ! expected R0 = sign_extend(0x8001) = 0xFFFF8001
        cmp/eq  r7, r0
        bf      _fail5

        cmp/eq  r4, r3
        bf      _fail5a

        ! ---------------------------------------------------------------
        ! (6) mov.l @-r3,r0 : pre-dec load, longword (no sign-extension
        ! needed, full 32-bit passthrough).
        ! ---------------------------------------------------------------
        mov.l   p_buf_ll, r4
        mov.l   p_val_ll, r1    ! r1 = 0x80000001
        mov.l   r1, @r4

        mov.l   p_addr_ll1, r3  ! r3 = buf_ll + 4
        mov     #0, r0
        .word   0x43EB          ! mov.l @-r3,r0  (Rm=r3)
        nop

        mov.l   p_val_ll, r7
        cmp/eq  r7, r0
        bf      _fail6

        cmp/eq  r4, r3
        bf      _fail6a

        bra     _done
        nop

        .align 2
buf_b:  .long 0
buf_w:  .long 0
buf_l:  .long 0
buf_lb: .long 0
buf_lw: .long 0
buf_ll: .long 0

p_buf_b:    .long buf_b
p_buf_w:    .long buf_w
p_buf_l:    .long buf_l
p_buf_lb:   .long buf_lb
p_buf_lw:   .long buf_lw
p_buf_ll:   .long buf_ll

p_addr_b1:  .long buf_b+1
p_addr_w1:  .long buf_w+2
p_addr_l1:  .long buf_l+4
p_addr_lb1: .long buf_lb+1
p_addr_lw1: .long buf_lw+2
p_addr_ll1: .long buf_ll+4

p_val_b:    .long 0x0000007A
p_valx_b:   .long 0x0000007A
p_val_w:    .long 0x00001234
p_valx_w:   .long 0x00001234
p_val_l:    .long 0x89ABCDEF

p_val_lb:   .long 0xFFFFFF80
p_valx_lb:  .long 0xFFFFFF80
p_val_lw:   .long 0xFFFF8001
p_valx_lw:  .long 0xFFFF8001
p_val_ll:   .long 0x80000001

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0         ! 0 = pass
        bra     _done
        nop

! Distinct fail codes: N => value check for step N; N+50 => pointer-update
! check for step N (avoids collision with the 1..6 value-check codes).
_fail1:
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail1a:
        mov.l   p_test_result, r0
        mov     #51, r9
        mov.l   r9, @r0
        bra     _fail1a
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #2, r9
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail2a:
        mov.l   p_test_result, r0
        mov     #52, r9
        mov.l   r9, @r0
        bra     _fail2a
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #3, r9
        mov.l   r9, @r0
        bra     _fail3
        nop
_fail3a:
        mov.l   p_test_result, r0
        mov     #53, r9
        mov.l   r9, @r0
        bra     _fail3a
        nop
_fail4:
        mov.l   p_test_result, r0
        mov     #4, r9
        mov.l   r9, @r0
        bra     _fail4
        nop
_fail4a:
        mov.l   p_test_result, r0
        mov     #54, r9
        mov.l   r9, @r0
        bra     _fail4a
        nop
_fail5:
        mov.l   p_test_result, r0
        mov     #5, r9
        mov.l   r9, @r0
        bra     _fail5
        nop
_fail5a:
        mov.l   p_test_result, r0
        mov     #55, r9
        mov.l   r9, @r0
        bra     _fail5a
        nop
_fail6:
        mov.l   p_test_result, r0
        mov     #6, r9
        mov.l   r9, @r0
        bra     _fail6
        nop
_fail6a:
        mov.l   p_test_result, r0
        mov     #56, r9
        mov.l   r9, @r0
        bra     _fail6a
        nop
_fail:
        mov.l   p_test_result, r0
        mov     #7, r9
        mov.l   r9, @r0
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
