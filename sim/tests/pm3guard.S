! PM3 J4-vs-J1/J2 guard (excguard pattern, two-directional + cross-image).
! The SAME source asserts OPPOSITE outcomes per build, and the J4 image MUST FAIL
! on J2 hardware — proving J2 lacks SH-4 fixed-vectoring.
!
!   - J4 (PRIV_ARCH=1): TRAPA #5 takes the SH-4 FIXED vector PC<-VBR+0x100 ->
!     fixed_handler, which reads EXPEVT (must be 0x160) and passes. If the SH-2
!     indirect table fires instead (i.e. we are really on J2 HW), table_handler
!     FAILS (code 7) — this is the cross-image guard biting.
!   - J2 (PRIV_ARCH=0): TRAPA #5 takes the SH-2 indirect vector mem[VBR+5*4] ->
!     table_handler, which passes. The fixed region is never reached.
!
! Matrix (recorded in docs/priv-arch/pm3-negative-test-matrix.md):
!   J4 image / J4 HW -> Pass ; J2 image / J2 HW -> Pass ; J4 image / J2 HW -> Fail.
! Result codes: 0 pass; 5 TRAPA never trapped; 6 fixed region hit on J2 image;
! 7 SH-2 table fired under a J4 image (cross-image guard bit).

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
        .long _fail
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
ENTRY(start)
        mov.l   p_vbr_base, r0
        ldc     r0, vbr
#if CONFIG_PRIV_ARCH
        ! J4: establish RB=0 and drop to user mode (clear MD) so the register-
        ! model fixed-vector entry engages.
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
        trapa   #5
        ! reaching here = no trap taken at all
        mov     #5, r9
        bra     _fail
        nop

        ! ---- VBR layout: SH-2 indirect table (used by J2 HW) with vec 5 at
        !      +0x14 -> table_handler; the SH-4 fixed general vector at +0x100. ----
        .balign 4
ENTRY(vbr_base)
        .long 0                    ! +0x00 vec 0
        .long 0                    ! +0x04 vec 1
        .long 0                    ! +0x08 vec 2
        .long 0                    ! +0x0c vec 3
        .long 0                    ! +0x10 vec 4
        .long table_handler        ! +0x14 vec 5 (TRAPA #5 on SH-2)
        .space 0x100 - 0x18        ! pad to +0x100
fixed_handler:                     ! vbr_base + 0x100 (SH-4 fixed general vector)
#if CONFIG_PRIV_ARCH
        ! J4 fixed vector taken (correct). Verify EXPEVT == 0x160, then pass.
        .word   0x0052             ! STC EXPEVT, r0
        mov.l   p_expevt, r3
        cmp/eq  r3, r0
        mov     #2, r9             ! code 2 = EXPEVT wrong
        bf      _fail
        bra     _done
        nop
#else
        ! On a J2 image the fixed region must never be reached.
        mov     #6, r9
        bra     _fail
        nop
#endif

ENTRY(table_handler)
#if CONFIG_PRIV_ARCH
        ! J4 image but the SH-2 indirect table fired -> we are on J2 HW which
        ! lacks SH-4 fixed-vectoring -> the guard bites.
        mov     #7, r9
        bra     _fail
        nop
#else
        ! J2: SH-2 indirect table taken (correct) -> pass.
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop

        .balign 4
p_vbr_base:    .long vbr_base
p_rbclear:     .long 0xDFFFFFFF
p_mdmask:      .long 0xBFFFFFFF
p_expevt:      .long 0x00000160
p_test_result: .long TEST_RESULT_ADDRESS
