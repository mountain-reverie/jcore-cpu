! SH-2A DIVU/DIVS R0,Rn: 32/32->32 division, SR (T/Q/M) UNAFFECTED.
!
! Task 2 guard. Exercises the 2-slot divu/divs rows in
! decode/gen-go/spec/sh2a/divide.toml, which wire the standalone sequential
! divider unit (core/divider.vhd, Task 1) into the CPU via cpu.vhd (u_div)
! and core/datapath.vhm (g_div/g_div_off + manip_sel DIV_READ), mirroring
! mult(seq)'s busy-stall (core/cpu.vhd combined_mac_busy/combined_mult_stall).
!
! sh2-elf-as (plain -m2) does not know the SH-2A DIVU/DIVS opcodes, so they
! are hand-encoded via .word. Encoding: nnnn = op.code(11:8) (Rn), R0 fixed
! divisor:
!   DIVU R0,Rn = 0100 nnnn 1000 0100
!   DIVS R0,Rn = 0100 nnnn 1001 0100
! All cases below use Rn=R2, so DIVU R0,R2 = 0x4284, DIVS R0,R2 = 0x4294.
!
! T-bit (and the rest of SR) must survive the divide untouched: SETT once up
! front, then re-check T=1 with MOVT after every case (a corrupted Q/M/T
! would show up here even though only T is directly asserted).
!
! Marker convention mirrors sim/tests/sh2a_mulr.S: 0 = pass at
! TEST_RESULT_ADDRESS, non-zero = fail (distinct codes below).

#include "sim_instr.h"

        .section .vect
        .long   start                  ! 0: power-on PC
        .long   0x00007000              ! 1: power-on SP (inside RAM)
        .long   start                  ! 2: manual reset PC
        .long   0x00007000              ! 3: manual reset SP
        .rept 60
        .long   0
        .endr
        .long   SIM_INSTR_MAGIC
        .long   _sim_instr_end
        .long   _done
        .long   _fail1
        .long   CMD_ENABLE_TEST_RESULT
_sim_instr_end:
        .long   0

        .text
        .global start
start:
        sett                            ! SR.T = 1 for the whole run

        ! =====================================================================
        ! case 1: divu 100 / 7 = 14
        ! =====================================================================
        mov     #7, r0
        mov     #100, r2
        .word   0x4284                  ! DIVU R0,R2
        mov     #14, r5
        cmp/eq  r2, r5
        bf      _fail1
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail1

        ! =====================================================================
        ! case 2: divu 0xFFFFFFFF / 2 = 0x7FFFFFFF
        ! =====================================================================
        mov     #2, r0
        mov     #-1, r2                 ! 0xFFFFFFFF
        .word   0x4284                  ! DIVU R0,R2
        mov.l   p_0x7FFFFFFF, r5
        cmp/eq  r2, r5
        bf      _fail2
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail2

        ! =====================================================================
        ! case 3: divu 12 / 1 = 12
        ! =====================================================================
        mov     #1, r0
        mov     #12, r2
        .word   0x4284                  ! DIVU R0,R2
        mov     #12, r5
        cmp/eq  r2, r5
        bf      _fail3
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail3

        ! =====================================================================
        ! case 4: divs -100 / 7 = -14
        ! =====================================================================
        mov     #7, r0
        mov     #-100, r2
        .word   0x4294                  ! DIVS R0,R2
        mov     #-14, r5
        cmp/eq  r2, r5
        bf      _fail4
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail4

        ! =====================================================================
        ! case 5: divs 100 / -7 = -14
        ! =====================================================================
        mov     #-7, r0
        mov     #100, r2
        .word   0x4294                  ! DIVS R0,R2
        mov     #-14, r5
        cmp/eq  r2, r5
        bf      _fail5
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail5

        ! =====================================================================
        ! case 6: divs -100 / -7 = 14
        ! =====================================================================
        mov     #-7, r0
        mov     #-100, r2
        .word   0x4294                  ! DIVS R0,R2
        mov     #14, r5
        cmp/eq  r2, r5
        bf      _fail6
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail6

        ! =====================================================================
        ! case 7: divs 42 / -1 = -42
        ! =====================================================================
        mov     #-1, r0
        mov     #42, r2
        .word   0x4294                  ! DIVS R0,R2
        mov     #-42, r5
        cmp/eq  r2, r5
        bf      _fail7
        movt    r9
        mov     #1, r8
        cmp/eq  r8, r9
        bf      _fail7

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

.global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0                 ! 0 = pass
        bra     _done
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_0x7FFFFFFF:  .long 0x7FFFFFFF
