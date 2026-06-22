! rteredir.S -- proves the PRIV_ARCH RTE actually REDIRECTS PC to SPC.
!
! Regression guard for the RTE redirect-slot defect: the SH-4 (PRIV_ARCH) RTE
! microcode must fetch from SPC after the delay slot. Unlike exctest/trapatest --
! whose RTE delay-slot fall-through happens to land on their pass path, so they
! pass even if the RTE never redirects -- this test sets SPC to a FAR target
! (_pass) and routes the fall-through to a deterministic FAIL. Only a real
! redirect reaches _pass. Non-TLB (TRAPA entry) so it is independent of the
! separate TLB-entry skew that mmurte exercises.

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
        ! VBR so VBR+0x100 == exception_handler; drop to user (clear MD, RB=0).
        mov.l   p_vbr_fixed, r0
        ldc     r0, vbr
        stc     sr, r3
        mov.l   p_rbclear, r4
        and     r4, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr
        nop
        nop
        nop
        trapa   #0                      ! -> exception_handler (SPC = address after TRAPA)
        ! TRAPA returns to here ONLY if the handler did not overwrite SPC; the
        ! handler always overwrites SPC with _pass, so a working RTE never lands
        ! here. Spin as a fail backstop.
        bra     _fail
        nop

ENTRY(_pass)
        ! Reached iff the handler RTE redirected PC to SPC = _pass.
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _pass
        nop

ENTRY(exception_handler)
        ! Set SPC = _pass (a far target, NOT the RTE delay-slot fall-through), RTE.
        mov.l   p_pass, r0
        .word   0x404E                  ! LDC R0, SPC
        rte
        nop                             ! delay slot
        ! Fall-through (the defect): if the RTE fails to redirect, execution
        ! reaches here instead of _pass -> deterministic FAIL.
_redir_fail:
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _redir_fail
        nop

        .align 2
p_vbr_fixed:   .long exception_handler - 0x100
p_mdmask:      .long 0xBFFFFFFF
p_rbclear:     .long 0xDFFFFFFF
p_pass:        .long _pass
p_test_result: .long TEST_RESULT_ADDRESS

#else  ! CONFIG_PRIV_ARCH -- J1/J2 use the base (branch.toml) RTE; not under test here.
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   q_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   q_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
q_test_result: .long TEST_RESULT_ADDRESS
