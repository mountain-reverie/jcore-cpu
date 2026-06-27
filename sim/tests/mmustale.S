! mmustale.S -- STALE-bit (PTEL[1]) revocation guard (J4 + MMU_ARCH).
!
! Security hardening (security-review H-I1): the STALE bit is loaded into the TLB
! at LDTLB time but the lookup never consults it, so an entry software marked
! STALE (soft-invalidate / revoked) is still matched and its old translation is
! granted -- a revoked mapping stays live. With enforcement (`entry.stale='0'`
! added to the TLB match), a STALE=1 entry must NOT match -> the access takes a
! TLB MISS and faults.
!
! Flow:
!   - map page 0 identity (W|X|U|C), STALE=0, for code fetch under AT
!   - install a STALE=1 entry for VPN 0x4 (VA 0x4000 -> PA 0x4000), then AT on
!   - LOAD from VA 0x4000 -> must raise DMISS_R (EXPEVT 0x060), vector VBR+0x420
!   - handler (the ONLY pass path): disable AT, write "Test Passed", spin
!   - if the STALE entry still matches (the defect): the load completes, main
!     path spins WITHOUT writing a result -> run times out -> RED.
!
! VBR = _v_load - 0x420 so the DMISS_R vector (VBR+0x420) hits _v_load.

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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_load - 0x420 (so VBR+0x420 = _v_load). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8, STALE=0. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Install a STALE=1 entry: VPN 0x4 (VA 0x4000) -> PA 0x4000. ----
        mov.l   p_pteh_p4, r0          ! VPN 0x4 (VA 0x4000)
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_stale, r0       ! PA 0x4000 | W|X|U|C|STALE = 0x40EA
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- LOAD from VA 0x4000: a STALE=1 entry must NOT match -> DMISS_R. ----
        mov.l   c_page4_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (VBR+0x420), DMISS_R

        ! If the STALE entry still matched (the defect), we reach here. Spin
        ! WITHOUT writing any result so RED = run times out (no "Test Passed").
_silent_spin:
        bra     _silent_spin
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x420
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000E8
p_pteh_p4:      .long 0x00004000
p_ptel_stale:   .long 0x000040EA        ! PA 0x4000 | W|X|U|C|STALE (bit1)
c_page4_va:     .long 0x00004000

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
        ! Pad so _v_load lands at >= 0x420.
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x420
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        ! The STALE entry faulted as required: write PASS (result 0). AT is now
        ! off so this P-region store is reliable. The ONLY path that writes a
        ! result -> reaching it == GREEN.
        mov.l   Hresult, r0
        mov     #0, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hresult:        .long TEST_RESULT_ADDRESS

        ! ---- Backing-page padding: VA 0x4000. ----
_fault_pages:
        .space 0x4000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
