! mmutsb.S -- M5 guard for the TSB hardware pointer assist.
!
! Proves that on a TLB miss, hardware computes the TSB slot pointer
! (hardware-spec.md §2.6-2.8, §3.2) and exposes it via the new read-only
! STC TSBPTR,Rn:
!
!   vpn   = faulting_VA[31:12]
!   hash  = (TSBCFG.HASH_MODE==1) ? vpn ^ (vpn >> TSBCFG.HASH_SHIFT) : vpn
!   mask  = (1 << TSBBR.TSB_SIZE_LOG) - 1
!   TSBPTR = (TSBBR & ~0xF) | ((hash & mask) << 4)
!
! Config (written via MMIO before AT is enabled):
!   TSBBR  = 0x00010006   base=0x00010000, TSB_SIZE_LOG=6 (64 entries, mask=0x3F)
!   TSBCFG = 0x00000061   HASH_SHIFT=6, HASH_MODE=1
!
! Faulting load VA = 0x00042000  ->  vpn = 0x42
!   hash  = 0x42 ^ (0x42 >> 6) = 0x42 ^ 0x01 = 0x43
!   index = 0x43 & 0x3F        = 0x03
!   TSBPTR = 0x00010000 | (0x03 << 4) = 0x00010030
!
! Flow: map code page identity, enable AT, configure TSBBR/TSBCFG, take a
! DMISS_R on VA 0x42000; the handler reads TSBPTR (STC), compares to the
! expected 0x00010030, disables AT and writes the test result, then spins.
!
! RED before M5: STC TSBPTR (0x0043) is undefined -> garbage compare -> the
! handler writes FAIL (or, if it traps, times out). GREEN: TSBPTR == expected.
!
! VBR = _v_load - 0x420 so the DMISS_R vector (VBR+0x420) hits _v_load.

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define EXPECTED_TSBPTR 0x00010030

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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_load - 0x420. ----
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
p_vbr_val:      .long _v_load - 0x420
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000E8
p_mmucr:        .long 0xFF000010
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
c_fault_va:     .long 0x00042000

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- DMISS_R handler at VBR+0x420 ----
        .balign 4
        .space 0x600, 0
        .balign 4
_v_load:                                ! = VBR + 0x420
        ! Read hardware-computed TSBPTR and compare to the expected value.
        .word   0x0043                  ! STC TSBPTR, r0   (read-only, new in M5)
        mov.l   He_tsbptr, r1
        cmp/eq  r0, r1
        bf      _h_bad                  ! TSBPTR mismatch

        ! PASS: disable AT, write result 0, spin.
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        mov.l   Hresult, r0
        mov     #0, r1
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
He_tsbptr:      .long EXPECTED_TSBPTR

        ! Force .text section alignment to 4 KB so `start` is page-aligned
        ! (mapped as one identity page above). The faulting VA 0x42000 is never
        ! backed -- the TLB miss fires before any bus access.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
