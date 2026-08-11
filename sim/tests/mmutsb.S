! mmutsb.S -- M5 guard for the TSB hardware pointer assist.
!
! Proves that on a TLB miss, hardware computes the TSB slot pointer
! (hardware-spec.md §2.6-2.8, §3.2) and exposes it via the read-only
! P4 register TSBPTR (0xFF00001C):
!
!   vpn   = faulting_VA[31:12]
!   hash  = (TSBCFG.HASH_MODE==1) ? vpn ^ (vpn >> TSBCFG.HASH_SHIFT) : vpn
!   mask  = (1 << TSBBR.TSB_SIZE_LOG) - 1
!   TSBPTR = (TSBBR & ~0x1F) | ((hash & mask) << 5)
!
! Config (written via MMIO before AT is enabled):
!   TSBBR  = 0x00010006   base=0x00010000, TSB_SIZE_LOG=6 (64 entries, mask=0x3F)
!   TSBCFG = 0x00000061   HASH_SHIFT=6, HASH_MODE=1
!
! Faulting load VA = 0x00042000  ->  vpn = 0x42
!   hash  = 0x42 ^ (0x42 >> 6) = 0x42 ^ 0x01 = 0x43
!   index = 0x43 & 0x3F        = 0x03
!   TSBPTR = 0x00010000 | (0x03 << 5) = 0x00010060
!
! Flow: map code page identity, enable AT, configure TSBBR/TSBCFG, take a
! DMISS_R on VA 0x42000; the handler reads TSBPTR (STC), compares to the
! expected 0x00010060, disables AT and writes the test result, then spins.
!
! RED before M5: the hardware TSBPTR (0xFF00001C) is undefined -> garbage compare -> the
! handler writes FAIL (or, if it traps, times out). GREEN: TSBPTR == expected.
!
! VBR = _v_load - 0x400 so the DMISS_R vector (VBR+0x400) hits _v_load.

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

#define EXPECTED_TSBPTR 0x00010060

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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_load - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page identity (W+X+U+C = 0xE8). ----
        ! `start` is forced 4 KB-aligned (the .balign 0x1000 on _fault_page
        ! raises the .text section alignment), so all code lives in one page.
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Configure the TSB via MMIO (cold-path config registers). ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR  = 0x00010006
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG = 0x00000061

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Take a DMISS_R: load from VA 0x00042000 (unmapped). ----
        mov     #3, r9                 ! sentinel: if no fault, fail code 3
        mov.l   c_fault_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (DMISS_R)

        bra     _fail                  ! handler writes result + spins; never here
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x400
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C8        ! U cleared: kernel code, SMEP
p_mmucr:        .long 0xFF000010
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
c_fault_va:     .long 0x00042000

#endif  ! CONFIG_PRIV_ARCH

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

#if CONFIG_PRIV_ARCH

        ! ---- DMISS_R handler at VBR+0x400 ----
        .balign 4
        .space 0x600, 0
        .balign 4
_v_load:                                ! = VBR + 0x400
        ! Read hardware-computed TSBPTR and compare to the expected value.
        mov.l   Htsbptr_a, r0
        mov.l   @r0, r0                 ! r0 = TSBPTR (read-only P4 alias)
        mov.l   He_tsbptr, r1
        cmp/eq  r0, r1
        bf      _h_bad                  ! TSBPTR mismatch

        ! PASS: disable AT, write result 0, spin.
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        mov.l   Hresult, r0
        mov.l   Hresult_pass, r1
        mov.l   r1, @r0                 ! TEST_RESULT = 0 (PASS)
_h_pass_spin:
        bra     _h_pass_spin
        nop

_h_bad:
        ! FAIL: disable AT, write result 4, spin.
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   Hresult, r0
        mov     #4, r1
        mov.l   r1, @r0                 ! TEST_RESULT = 4 (FAIL: wrong TSBPTR)
_h_bad_spin:
        bra     _h_bad_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hresult:        .long TEST_RESULT_ADDRESS
Hresult_pass:        .long   TEST_PASS_MAGIC
He_tsbptr:      .long EXPECTED_TSBPTR
Htsbptr_a:      .long 0xFF00001C

        ! Force .text section alignment to 4 KB so `start` is page-aligned
        ! (mapped as one identity page above). The faulting VA 0x42000 is never
        ! backed -- the TLB miss fires before any bus access.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
