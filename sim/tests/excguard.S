! PM2 J1/J2-vs-J4 exception guard. Two-directional, in the spirit of banktest:
! the SAME code asserts OPPOSITE outcomes per build, so it fails if the register
! exception model is absent on J4 OR leaks into J1/J2.
!
! TRAPA #0 is the trigger because it raises an exception under BOTH models (it is
! not privileged, so it fires on J2 too). The handler inspects SR.MD on entry:
!   - J4 (PRIV_ARCH=1): the register-model entry sets MD=1, so the handler runs
!     PRIVILEGED -> MD must read 1. (If it reads 0, PM2's entry didn't engage.)
!   - J1/J2 (PRIV_ARCH=0): there is no register exception model and no MD bit, so
!     MD must read 0. (If it reads 1, PM2 leaked into a non-PRIV_ARCH build.)
! The handler then branches straight to _done, so the result does not depend on
! the exception-return path (RTE is exercised separately by exctest.S / rte.S).
!
! NOTE: unlike exctest.S this test runs on BOTH builds (no skip-pass), which is
! what makes it an inverse guard for J1/J2.

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

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
        .long _fail_loop
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
ENTRY(start)
        ! VBR -> direct handler table (every entry = the handler)
        mov.l   p_myvbr, r0
        ldc     r0, vbr
#if CONFIG_PRIV_ARCH
        ! J4: establish RB=0 and drop to user mode (clear MD) so the handler
        ! observes the entry's MD 0->1 transition rather than the reset MD=1.
        stc     sr, r3
        mov.l   p_rbclear, r4
        and     r4, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr
        nop
        nop
        nop
#endif
        trapa   #0
        bra     _fail_loop         ! TRAPA must vector to the handler; if we get
        nop                        ! here, no exception was taken -> fail.

ENTRY(exception_handler)
        stc     sr, r4
        mov.l   p_mdbit, r5        ! 0x40000000 (MD)
        and     r5, r4
#if CONFIG_PRIV_ARCH
        tst     r4, r4
        bt      _fail_loop         ! J4: register-model entry must have set MD=1
#else
        tst     r4, r4
        bf      _fail_loop         ! J1/J2: MD must read 0 (no register model)
#endif
        bra     _done
        nop

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail_loop)
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail_loop
        nop

        .align 2
p_myvbr:       .long _myvbr
p_mdmask:      .long 0xBFFFFFFF
p_rbclear:     .long 0xDFFFFFFF
p_mdbit:       .long 0x40000000
p_test_result: .long TEST_RESULT_ADDRESS

        ! direct vector table: every entry = the handler, so TRAPA lands on it
        ! regardless of its exact vector number.
        .align 2
ENTRY(_myvbr)
        .rept 64
        .long exception_handler
        .endr
