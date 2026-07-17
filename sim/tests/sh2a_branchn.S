! SH-2A delay-slot-less branches: RTS/N, JSR/N @Rm, RTV/N Rm (Group 9).
!
! RTS/N = PR -> PC like RTS, but executes NO delay slot. This establishes
! the delay-slot-suppression slot structure that later Group 9 branches
! reuse.
!
! JSR/N @Rm = PC -> PR, Rm -> PC, no delay slot (like JSR but no delay slot).
! RTV/N Rm  = Rm -> R0, PR -> PC, no delay slot.
!
! sh2-elf-as (plain -m2) does not know these SH-2A opcodes, so they are
! hand-encoded via .word:
!   RTS/N     = 0000 0000 0110 1011  (0x006B)
!   JSR/N @Rm = 0100 mmmm 0100 1011
!   RTV/N Rm  = 0000 mmmm 0111 1011
!   LDS Rm,PR = 0100 mmmm 0010 1010  (base SH-2, used to load PR)
!   STS PR,Rn = 0000 nnnn 0010 1010  (base SH-2, used to read back PR)
!
! Test: set r10 = sentinel (0x5A). Load PR = address of _rts_target.
! Execute RTS/N. Immediately after it, place a POISON instruction that
! would clobber r10 to 0xFF if it executed as a (non-existent) delay
! slot. At _rts_target, verify r10 is still 0x5A (poison did NOT run)
! and that we actually arrived there (proves PC reached the PR target).
! Then chain into a JSR/N @Rm case and an RTV/N Rm case, each with their
! own POISON + fallthrough guard.
!
! Marker convention mirrors sim/tests/sh2a_bitreg.S: 0 = pass at
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
        mov     #0x5A, r10      ! sentinel: must survive if no delay slot

        mov.l   p_rts_target, r1
        .word   0x412A          ! LDS R1,PR

        .word   0x006B          ! RTS/N: PR -> PC, no delay slot
        mov     #0xFF, r10      ! POISON: must NOT execute (no delay slot)
        bra     _fail2          ! must NOT execute either (fell through)
        nop

        .align 2
p_rts_target: .long _rts_target

_rts_target:
        mov     #0x5A, r5
        cmp/eq  r10, r5
        bf      _fail1          ! r10 != 0x5A -> poison ran -> fail

        bra     _jsrn_test
        nop

! --- JSR/N @Rm ---------------------------------------------------------
! r1 = target address. r10 = sentinel. JSR/N must save PC+2 (address of
! the POISON instruction) into PR and jump to Rm, with no delay slot.
_jsrn_test:
        mov     #0x5A, r10      ! sentinel: must survive if no delay slot

        mov.l   p_jsrn_target, r1
        .word   0x414B          ! JSR/N @R1

        mov     #0xFF, r10      ! POISON: must NOT execute (no delay slot)
p_jsrn_return:
        bra     _fail4          ! must NOT execute either (fell through)
        nop

        .align 2
p_jsrn_target: .long _jsrn_target

_jsrn_target:
        mov     #0x5A, r5
        cmp/eq  r10, r5
        bf      _fail3          ! r10 != 0x5A -> poison ran -> fail

        .word   0x062A          ! STS PR,R6
        mov.l   p_jsrn_return_val, r5
        cmp/eq  r5, r6
        bf      _fail5          ! PR != addr right after the POISON -> fail

        bra     _rtvn_test
        nop

        .align 2
p_jsrn_return_val: .long p_jsrn_return

! --- RTV/N Rm ------------------------------------------------------------
! r2 = known value (0x33). PR = address of _rtvn_target. r0 = different
! sentinel. RTV/N must move Rm -> R0 AND jump to PR, with no delay slot.
_rtvn_test:
        mov     #0x33, r2       ! Rm value to be moved into R0
        mov     #0x77, r0       ! sentinel: must be overwritten by Rm

        mov.l   p_rtvn_target, r1
        .word   0x412A          ! LDS R1,PR

        .word   0x027B          ! RTV/N R2: R2 -> R0, PR -> PC, no delay slot
        mov     #0xFF, r0       ! POISON: must NOT execute (no delay slot)
        bra     _fail6          ! must NOT execute either (fell through)
        nop

        .align 2
p_rtvn_target: .long _rtvn_target

_rtvn_target:
        mov     #0x33, r5
        cmp/eq  r0, r5
        bf      _fail7          ! r0 != 0x33 -> poison ran or R0 not set

        bra     _done
        nop

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
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
