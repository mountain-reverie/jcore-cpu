! SH-2A delay-slot-less RTS: RTS/N (Group 9, Task 1).
!
! RTS/N = PR -> PC like RTS, but executes NO delay slot. This establishes
! the delay-slot-suppression slot structure that later Group 9 branches
! reuse.
!
! sh2-elf-as (plain -m2) does not know this SH-2A opcode, so it is
! hand-encoded via .word:
!   RTS/N     = 0000 0000 0110 1011  (0x006B)
!   LDS Rm,PR = 0100 mmmm 0010 1010  (base SH-2, used to load PR)
!
! Test: set r10 = sentinel (0x5A). Load PR = address of _rts_target.
! Execute RTS/N. Immediately after it, place a POISON instruction that
! would clobber r10 to 0xFF if it executed as a (non-existent) delay
! slot. At _rts_target, verify r10 is still 0x5A (poison did NOT run)
! and that we actually arrived there (proves PC reached the PR target).
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
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
