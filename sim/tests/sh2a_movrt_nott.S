! SH-2A single-word T-bit instructions: MOVRT Rn / NOTT (Group 7).
!
! Task 3 guard. MOVRT writes ~T into Rn (does not affect T). NOTT inverts
! T in place. Both reuse existing microcode vocabulary (ARITH carry-in for
! MOVRT; LOGIC ZERO-rule for NOTT) -- no new datapath/enum.
!
! Uses the native SH-2A movrt/nott mnemonics (requires -Wa,--isa=sh2a):
!   MOVRT Rn = 0000 nnnn 0011 1001   (nnnn = op.code(11:8) = Rn)
!   NOTT     = 0000 0000 0110 1000
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
        ! --- case 1: SETT (T=1), MOVRT R1 -> expect R1==0 ---
        sett
        movrt   r1
        mov     #0, r5
        cmp/eq  r1, r5
        bf      _fail1

        ! --- case 2: CLRT (T=0), MOVRT R1 -> expect R1==1 ---
        clrt
        movrt   r1
        mov     #1, r5
        cmp/eq  r1, r5
        bf      _fail2

        ! --- case 3: CLRT (T=0), NOTT -> expect T==1 (branch-on-T) ---
        clrt
        nott
        bf      _fail3          ! T should now be 1; bf taken means fail
        nop

        ! --- case 4: SETT (T=1), NOTT -> expect T==0 (branch-on-T) ---
        sett
        nott
        bt      _fail4          ! T should now be 0; bt taken means fail
        nop

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
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
