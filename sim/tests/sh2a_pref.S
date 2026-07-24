! SH-2A PREF @Rn: operand-cache prefetch hint, implemented as a NOP.
!
! PREF has no architectural effect (touches only optional cache state; never a
! register/memory/T). This test proves the J2A decode is a true no-op: it must
! NOT alter any register or T, must NOT trap/hang, and the instruction after it
! must run normally. PREF @R1 = 0000 0001 1000 0011 = 0x0183 (native mnemonic,
! requires -Wa,--isa=sh2a).
!
! Marker: 0 = pass at TEST_RESULT_ADDRESS, non-zero = distinct fail code.

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
        .long _fail1
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
        .global start
start:
        mov     #0x5A, r10       ! sentinel that must survive
        mov     #0x33, r2        ! second sentinel
        mov.l   p_ram, r1        ! a valid address (PREF ignores it anyway)
        sett                     ! T = 1, must survive

        pref    @r1               ! must be a pure NOP
        mov     #0x77, r3        ! the instruction after PREF must run (r3=0x77)
        movt    r6               ! capture T IMMEDIATELY (before any cmp clobbers it)

        ! --- verify nothing changed (cmp/eq clobbers T, so the T check used r6) ---
        mov     #1, r5
        cmp/eq  r6, r5
        bf      _fail3           ! T (=1 from sett) was not preserved across PREF
        mov     #0x5A, r5
        cmp/eq  r10, r5
        bf      _fail1           ! r10 clobbered
        mov     #0x33, r5
        cmp/eq  r2, r5
        bf      _fail2           ! r2 clobbered
        mov     #0x77, r5
        cmp/eq  r3, r5
        bf      _fail4           ! instruction after PREF did not run

        bra     _done
        nop

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail1: mov.l p_test_result,r0
        mov #1,r9
        mov.l r9,@r0
        bra _fail1
        nop
_fail2: mov.l p_test_result,r0
        mov #2,r9
        mov.l r9,@r0
        bra _fail2
        nop
_fail3: mov.l p_test_result,r0
        mov #3,r9
        mov.l r9,@r0
        bra _fail3
        nop
_fail4: mov.l p_test_result,r0
        mov #4,r9
        mov.l r9,@r0
        bra _fail4
        nop
        .align 2
p_ram:          .long 0x00006000
p_test_result:  .long TEST_RESULT_ADDRESS
