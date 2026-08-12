! mmuimiss.S -- isolated RED guard for the IMISS TEA-capture defect (Defect 2).
!
! Reproduces, in isolation, the defect described in
! docs/superpowers/handover-mmu-m3-datapath-defects.md: on an instruction-fetch
! TLB miss (IMISS) taken via a jmp to an unmapped VA, TEA captures 0 instead of
! the faulting VA. The D-side (DMISS_R, mmurte.S) captures TEA correctly, so this
! test isolates the I-side faulting-VA capture path.
!
! Flow:
!   - map page 0 identity (W|X|U|C), enable AT
!   - jmp to VA 0x1000 (page 1, unmapped) -> IMISS TLB exception
!   - handler (VBR+0x400): disable AT, read TEA, compare to 0x1000
!       * TEA correct -> set SPC=_resume, RTE -> _resume -> result 0 (PASS)
!       * TEA wrong   -> result 9 (the Defect-2 symptom: TEA=0)
!       * no exception / fall-through -> times out, no "Test Passed" (RED)
!
! VBR = _v_ifetch - 0x400 so the IMISS vector (VBR+0x400) hits _v_ifetch.

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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_ifetch - 0x400 (so VBR+0x400 = _v_ifetch). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB: base 0x00004000, TSB_SIZE_LOG=6 (64 sets x
        ! ---- 32 bytes = 0x4000..0x47FF), HASH_SHIFT=6, HASH_MODE=1. The image
        ! ---- is zero-filled, so the TSB starts empty and the fill below is the
        ! ---- only thing that populates it. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Map page 0 (VA 0x0000-0x0FFF) identity, W|X|C|G|V, U=0 (SMEP).
        ! ---- This used to be an LDTLB; it is now a TSB entry the walker
        ! ---- installs on demand -- I-side on the first fetch after AT goes
        ! ---- on, D-side on the first literal load. GLOBAL, so no ASID change
        ! ---- can perturb it. The set address is asked of the P4 slot helper
        ! ---- (0xFF000048); nothing here hand-computes the hash. ----
        mov.l   p_tsbslot_reg, r12
        mov     #0, r6                  ! VA 0x00000000
        mov     #0, r7                  ! ASID 0
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_page0, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        mov.l   r8, @(8, r10)           ! way 0 data = PTEL
        mov.l   r7, @(4, r10)           ! way 0 tag_lo = ASID_TAG
        mov.l   r6, @(0, r10)           ! way 0 tag_hi = VPN (commit point)

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Take an IMISS: jump to VA 0x1000 (page 1, unmapped). ----
        mov.l   c_page1_va, r0
        jmp     @r0                     ! FAULTS -> _v_ifetch (VBR+0x400), IMISS
        nop

        ! If the IMISS does not fire, we fall here only after running page-1
        ! zeros; in practice we never reach this. Deterministic fail anyway.
        mov     #7, r9
        bra     _fail
        nop

ENTRY(_resume)
        ! RTE redirected after a correct TEA: write result 0 (PASS). AT is off
        ! (the handler disabled it) so this P-region store is reliable.
        mov.l   pr_test_result, r0
        mov.l   pr_test_result_pass, r1
        mov.l   r1, @r0
        bra     _resume
        nop
        .align 2
pr_test_result: .long TEST_RESULT_ADDRESS
pr_test_result_pass: .long   TEST_PASS_MAGIC

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_ifetch - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000CD        ! identity PPN 0 | W|X|C|G|V, U=0
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00004006        ! base=0x00004000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
c_page1_va:     .long 0x00001000

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

        ! ---- IMISS handler at VBR+0x400 ----
        ! Pad so _v_ifetch lands at >= 0x400 (kept clear of page 0's code and
        ! within page 0 so the handler fetch itself is mapped).
        .balign 4
        .space 0x600, 0
        .balign 4
_v_ifetch:                              ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        mov.l   Htea_addr, r0
        mov.l   @r0, r2                 ! r2 = TEA (faulting VA)
        mov.l   Hexp_tea, r3           ! r3 = 0x1000 (expected)
        cmp/eq  r3, r2
        bf      _h_tea_bad             ! TEA wrong -> Defect 2 symptom
        mov.l   Ph_resume, r0          ! r0 = _resume address
        .word   0x404E                 ! LDC r0, SPC
        rte
        nop
_h_tea_bad:
        mov     #9, r9                 ! fail code 9: IMISS TEA != 0x1000
        mov.l   Hres_addr, r0
        mov.l   r9, @r0
_h_bad_spin:
        bra     _h_bad_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Htea_addr:      .long 0xFF00000C
Hexp_tea:       .long 0x00001000
Ph_resume:      .long _resume
Hres_addr:      .long TEST_RESULT_ADDRESS

        ! ---- Fault-page padding: VA 0x1000. ----
_fault_pages:
        .space 0x5000, 0

#endif  ! CONFIG_PRIV_ARCH
