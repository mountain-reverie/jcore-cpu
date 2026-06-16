! TRAPA -> handler -> RTE round-trip, with a store immediately before TRAPA
! (the fetch-stalling case). Verifies RTE returns to the instruction after TRAPA.
! The return target is a PLAIN label (no .balign) right after TRAPA, so the test
! does not depend on alignment padding. J4 uses the register exception model
! (SPC/SSR); J2 uses the SH-2 stack model. Both must round-trip.
! Requires the J4 decoder for the J4 build (make -C decode generate-j4).

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
        mov.l   p_myvbr, r0
        ldc     r0, vbr
#if CONFIG_PRIV_ARCH
        ! J4: establish RB=0, drop to user mode (clear MD bit 30)
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
        ! sentinel = 0 — also the store that stalls the fetch right before TRAPA
        mov.l   p_sentinel, r1
        mov     #0, r2
        mov.l   r2, @r1
        trapa   #0
after_trapa:                        ! plain label = TRAPA+2 (the RTE return target)
        mov.l   p_sentinel, r1
        mov.l   @r1, r2
        mov     #1, r5
        cmp/eq  r5, r2
        bf      _fail_loop
        bra     _done
        nop

ENTRY(exception_handler)
        ! set sentinel and return via RTE (J4: SR<-SSR, PC<-SPC; J2: pop stack)
        mov.l   p_sentinel, r1
        mov     #1, r2
        mov.l   r2, @r1
        rte
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
p_sentinel:    .long 0x00007800
p_test_result: .long TEST_RESULT_ADDRESS

        .align 2
ENTRY(_myvbr)
        .rept 64
        .long exception_handler
        .endr
