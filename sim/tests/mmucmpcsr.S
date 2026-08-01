! mmucmpcsr.S -- CMP/EQ.PTEH / CMP/EQ.ASID: the fused TLB-miss hot-path tag
! compares. Each reads an MMU CSR (PTEH / ASIDR) straight onto ybus (the same
! SEL_MMU source the matching STC uses) and compares it against Rn, setting T --
! replacing `STC <csr>,Rt; CMP/EQ Rn,Rt` (2 insns + scratch) with one.
!
! Verifies, at MD=1 (privileged): a MATCH sets T=1 and a MISMATCH sets T=0, for
! both PTEH and ASIDR. Non-vacuous by construction (both the T=1 and T=0 arms
! must hold; a no-op / always-same result fails one of them). On a base decoder
! without these opcodes the words are illegal -> the guard traps (RED).
!
! Encodings (jcore MMU space, tail 0011, compare-variant middle nibble):
!   CMP/EQ.PTEH r1 = 0000 0001 1101 0011 = 0x01D3
!   CMP/EQ.ASID r1 = 0000 0001 1111 0011 = 0x01F3
!   LDC r0,PTEH = 0x405E   LDC r0,ASIDR = 0x407E
!
! Result codes:
!   0  pass
!   1  CMP/EQ.PTEH match did NOT set T
!   2  CMP/EQ.PTEH mismatch WRONGLY set T
!   3  CMP/EQ.ASID match did NOT set T
!   4  CMP/EQ.ASID mismatch WRONGLY set T

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Load known CSR values (privileged; runs at MD=1). ----
        mov.l   p_pteh_val, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_asid_val, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- CMP/EQ.PTEH: match -> T=1. ----
        mov.l   p_pteh_val, r1
        .word   0x01D3                  ! CMP/EQ.PTEH r1  (r1 vs PTEH)
        mov     #1, r9
        bf      _fail                   ! T=0 => fail 1

        ! ---- CMP/EQ.PTEH: mismatch -> T=0. ----
        mov.l   p_pteh_bad, r1
        .word   0x01D3                  ! CMP/EQ.PTEH r1
        mov     #2, r9
        bt      _fail                   ! T=1 => fail 2

        ! ---- CMP/EQ.ASID: match -> T=1. ----
        mov.l   p_asid_val, r1
        .word   0x01F3                  ! CMP/EQ.ASID r1  (r1 vs ASIDR)
        mov     #3, r9
        bf      _fail                   ! T=0 => fail 3

        ! ---- CMP/EQ.ASID: mismatch -> T=0. ----
        mov.l   p_asid_bad, r1
        .word   0x01F3                  ! CMP/EQ.ASID r1
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
