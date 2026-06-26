! MAC arithmetic non-regression guard (M8).
!
! The M8 accumulate-squash fix gates the MAC mach/macl commit on a faulting
! D-side TLB pass. This guard proves a NORMAL, fault-free MAC.L / MAC.W
! multiply-accumulate still produces the correct MACH:MACL -- i.e. the squash
! never fires on a clean MAC. No MMU/exception machinery is exercised; this is
! a pure datapath check that runs on J1/J2/J4 alike.
!
! MAC.L: clear MAC, then two products into the 64-bit accumulator:
!   0x00010000 * 0x00010000 = 0x0000000100000000   (exercises MACH carry)
!            2 *          3 = 0x0000000000000006
!   => MACH=0x00000001  MACL=0x00000006
!
! MAC.W: 16x16 signed accumulate into MACL (S=0):
!   100*7 + (-3)*5 = 700 - 15 = 685 = 0x000002AD
!   => MACL=0x000002AD

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
#if CONFIG_PRIV_ARCH
        ! reset leaves RB=1; establish RB=0 before using GPRs
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
#endif

        ! ---- MAC.L: two products ----
        mov     #0, r9
        lds     r9, mach
        lds     r9, macl
        mov.l   p_macl_a, r0          ! Rm -> {0x00010000, 2}
        mov.l   p_macl_b, r1          ! Rn -> {0x00010000, 3}
        mac.l   @r0+, @r1+
        mac.l   @r0+, @r1+

        sts     mach, r2
        mov.l   p_exp_mach, r3
        cmp/eq  r3, r2
        bf      _fail_loop
        sts     macl, r2
        mov.l   p_exp_macl, r3
        cmp/eq  r3, r2
        bf      _fail_loop

        ! ---- MAC.W: two products (signed 16x16, S=0) ----
        mov     #0, r9
        lds     r9, mach
        lds     r9, macl
        mov.l   p_macw_a, r0          ! Rm -> {100, -3}
        mov.l   p_macw_b, r1          ! Rn -> {7, 5}
        mac.w   @r0+, @r1+
        mac.w   @r0+, @r1+

        sts     macl, r2
        mov.l   p_exp_macw, r3
        cmp/eq  r3, r2
        bf      _fail_loop

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
#if CONFIG_PRIV_ARCH
p_rbclear:     .long 0xDFFFFFFF
#endif
p_test_result: .long TEST_RESULT_ADDRESS
p_macl_a:      .long macl_a
p_macl_b:      .long macl_b
p_macw_a:      .long macw_a
p_macw_b:      .long macw_b
p_exp_mach:    .long 0x00000001
p_exp_macl:    .long 0x00000006
p_exp_macw:    .long 0x000002AD

        .data
        .align 2
macl_a: .long 0x00010000, 2
macl_b: .long 0x00010000, 3
macw_a: .short 100, -3
macw_b: .short 7, 5
