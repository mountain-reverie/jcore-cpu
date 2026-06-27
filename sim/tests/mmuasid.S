! mmuasid.S -- ASID cross-tenant isolation + global-bit guard (J4 + MMU_ARCH).
!
! Security property (MMU security review, Family 5 / top risk #1): a TLB entry
! installed under ASID A must NOT be usable under ASID B (no cross-tenant hit),
! while a GLOBAL entry must be usable under any ASID.
!
! This is the first guard to exercise a NONZERO ASID and an ASID change; every
! prior guard ran with ASIDR=0, so cross-ASID isolation was untested.
!
! Construction (one test covers both properties):
!   - page 0 mapped GLOBAL identity (code) -> the code keeps fetching after the
!     ASID switch; its continued execution under ASID B is the global-positive
!     evidence (a global entry crosses ASIDs).
!   - VPN 0x4 (VA 0x4000 -> PA 0x4000) mapped NON-global, tagged ASID A, C=1.
!   - Leg A (ASID A): load VA 0x4000 must return the seeded sentinel (the entry
!     IS usable under its own ASID) -- else fail 1 (over-strict / bad install).
!   - Switch ASIDR to B.
!   - Leg B (ASID B): load VA 0x4000 must FAULT (DMISS_R, VBR+0x420) -> the
!     handler is the ONLY pass path. If the cross-ASID load instead completes
!     (isolation broken), the main path spins WITHOUT a result -> timeout -> RED.
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

        ! ---- Seed PA 0x4000 = SENTINEL via P1 (untranslated, AT-independent). ----
        mov.l   p_sentinel, r3
        mov.l   p_p1_4000, r2          ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2

        ! ---- ASIDR = A (0x0011). ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Map page 0 GLOBAL identity (code): W|X|U|C|G = 0xEC. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0)
        mov.l   p_ptel_page0, r0       ! 0x000000EC (global)
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR (re-assert A; global ignores it)
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x4 (VA 0x4000 -> PA 0x4000) NON-global, ASID A, C=1. ----
        mov.l   p_pteh_p4, r0          ! VPN 0x4
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p4, r0          ! 0x000040E8 (W|X|U|C, non-global)
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR (tag entry with ASID A)
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Leg A (ASID A): load VA 0x4000 must return SENTINEL. ----
        mov.l   c_va4, r2
        mov.l   @r2, r8
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = entry not usable under its OWN ASID
        bf      _fail

        ! ---- Switch ASIDR to B (0x0022). Code page is global -> keeps fetching. ----
        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Leg B (ASID B): load VA 0x4000 must FAULT (cross-ASID isolation). ----
        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! FAULTS -> _v_load (VBR+0x420), DMISS_R

        ! If the cross-ASID load completed (isolation broken), spin WITHOUT a
        ! result -> RED = timeout.
_silent_spin:
        bra     _silent_spin
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x420
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000EC        ! W|X|U|C|G (global code page)
p_pteh_p4:      .long 0x00004000
p_ptel_p4:      .long 0x000040E8        ! PA 0x4000 | W|X|U|C (non-global)
p_asid_a:       .long 0x00000011
p_asid_b:       .long 0x00000022
p_sentinel:     .long 0xA51DA51D
p_p1_4000:      .long 0x80004000
c_va4:          .long 0x00004000

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

        ! ---- DMISS_R handler at VBR+0x420 (the ONLY pass path). ----
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x420
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        ! The cross-ASID load faulted as required: write PASS (result 0).
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
