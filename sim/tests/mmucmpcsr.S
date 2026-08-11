! mmucmpcsr.S -- TLB-miss hot-path tag compares against the MMU CSRs.
!
! This guard used to exercise the fused CMP/EQ.PTEH / CMP/EQ.ASID opcodes.
! Phase 3 retires them (they occupied encodings SH-4A already defines), so the
! comparison is now expressed the way every user now expresses it: read the CSR
! through its read-only P4 alias (PTEH 0xFF000000, ASIDR 0xFF000038) and
! CMP/EQ against Rn.
!
! The assertions are UNCHANGED: at MD=1 (privileged), a MATCH must set T=1 and
! a MISMATCH must set T=0, for both PTEH and ASIDR. Non-vacuous by construction
! (both the T=1 and T=0 arms must hold; a no-op / always-same result fails one
! of them), and each alias read must return the exact value the preceding LDC
! wrote, so a dead alias fails the match arm.
!
! Encodings (assembler does not know the J4 LDC write side):
!   LDC r0,PTEH = 0x405E   LDC r0,ASIDR = 0x407E
!
! Result codes:
!   0  pass
!   1  PTEH match did NOT set T
!   2  PTEH mismatch WRONGLY set T
!   3  ASIDR match did NOT set T
!   4  ASIDR mismatch WRONGLY set T

!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS. Since the per-sub-test fail-code globals
! start at 0 until a sub-test sets them, a fault reaching _fail BEFORE the first
! sub-test runs would otherwise silently report PASS. _fail now clamps r9==0 to
! 0x7F before the store so 0 can never leave through the fail path. Fail-code
! globals below use loud sentinels (_g_exp_* = 0xFFFFFFFF, _g_bad_* = small
! distinct values) so an early exit still names its cause.
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

        ! ---- Load known CSR values (privileged; runs at MD=1). ----
        mov.l   p_pteh_val, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_asid_val, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- PTEH compare: match -> T=1. ----
        mov.l   p_pteh_val, r1
        mov.l   p_pteh_a, r2
        mov.l   @r2, r2                 ! r2 = PTEH (P4 alias)
        cmp/eq  r1, r2
        mov     #1, r9
        bf      _fail                   ! T=0 => fail 1

        ! ---- PTEH compare: mismatch -> T=0. ----
        mov.l   p_pteh_bad, r1
        mov.l   p_pteh_a, r2
        mov.l   @r2, r2                 ! r2 = PTEH (P4 alias)
        cmp/eq  r1, r2
        mov     #2, r9
        bt      _fail                   ! T=1 => fail 2

        ! ---- ASIDR compare: match -> T=1. ----
        mov.l   p_asid_val, r1
        mov.l   p_asidr_a, r2
        mov.l   @r2, r2                 ! r2 = ASIDR (P4 alias)
        cmp/eq  r1, r2
        mov     #3, r9
        bf      _fail                   ! T=0 => fail 3

        ! ---- ASIDR compare: mismatch -> T=0. ----
        mov.l   p_asid_bad, r1
        mov.l   p_asidr_a, r2
        mov.l   @r2, r2                 ! r2 = ASIDR (P4 alias)
        cmp/eq  r1, r2
        mov     #4, r9
        bt      _fail                   ! T=1 => fail 4

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_pteh_val: .long 0x00ABC000            ! a plausible VPN-tag value
p_pteh_bad: .long 0x00ABD000            ! differs in one VPN bit
p_asid_val: .long 0x00005678            ! a plausible ASID_TAG value
p_asid_bad: .long 0x00005679
p_pteh_a:   .long 0xFF000000
p_asidr_a:  .long 0xFF000038
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC
