! PM3 cause-capture test (J4). TRAPA #5 takes the SH-4 fixed vector VBR+0x100;
! the handler (running MD=1) reads EXPEVT (must be 0x160) and TRA (must be
! imm<<2 = 5<<2 = 0x14) via the J4-overlay STC instructions and commits the
! verdict directly. Committing IN the handler (rather than relying on an RTE
! round-trip to an after-trap check) is deliberate: the fall-through-to-_done
! layout used by trapatest/exctest would mask a wrong capture, whereas here a
! mismatched code branches to _fail with a distinct nonzero result.
!   result 0 = pass; 2 = EXPEVT wrong; 3 = TRA wrong; 5 = TRAPA never trapped.
! RTE round-trip is covered separately by trapatest.S / exctest.S.
!
! J4-only for now (#if CONFIG_PRIV_ARCH). The J2 negative side (two-directional +
! cross-image) is added in Task D1. Requires the J4 decoder (generate-j4).
! STC EXPEVT,r0 = 0000 0000 0101 0010 = 0x0052; STC TRA,r1 = 0000 0001 0111 0010
! = 0x0172 (the assembler does not know these J4-overlay opcodes, so .word them).

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
#if CONFIG_PRIV_ARCH
        ! VBR so that VBR+0x100 == exception_handler (SH-4 fixed vector)
        mov.l   p_vbr_fixed, r0
        ldc     r0, vbr
        ! establish RB=0 and drop to user mode (clear MD)
        stc     sr, r3
        mov.l   p_rbclear, r4
        and     r4, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr
        nop
        nop
        nop
        trapa   #5
        ! TRAPA must vector to the handler; reaching here = no trap taken
        mov     #5, r9
        bra     _fail
        nop

ENTRY(exception_handler)
        ! EXPEVT must be 0x160
        .word   0x0052             ! STC EXPEVT, r0
        mov.l   p_expevt, r3
        cmp/eq  r3, r0
        mov     #2, r9             ! code 2 = EXPEVT wrong
        bf      _fail
        ! TRA must be imm<<2 = 0x14
        .word   0x0172             ! STC TRA, r1
        mov.l   p_tra, r3
        cmp/eq  r3, r1
        mov     #3, r9             ! code 3 = TRA wrong
        bf      _fail
        bra     _done
        nop

        .align 2
p_vbr_fixed:   .long exception_handler - 0x100
p_rbclear:     .long 0xDFFFFFFF
p_mdmask:      .long 0xBFFFFFFF
p_expevt:      .long 0x00000160
p_tra:         .long 0x00000014
#else
        ! J2: no fixed vectors / cause registers -> skip-pass for now (D1 negates)
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
        mov.l   r9, @r0            ! distinct nonzero code per failed assertion
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
