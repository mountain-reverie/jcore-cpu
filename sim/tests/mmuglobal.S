! mmuglobal.S -- S-I7: a GLOBAL *user* TLB entry (G=1 && U=1) must be
!                unusable -- ANY access to it faults at lookup, for BOTH
!                ASID tags (global ignores the ASID match), fail-closed.
!
! Security property (MMU security review, S-I7): an entry with G=1 and U=1
! is a nonsensical/dangerous combination -- "global" means "matches under
! any ASID", and pairing that with "accessible to user mode" would let a
! single stray/malicious install grant every tenant (any ASID, including
! all future user processes) access to whatever physical page it maps,
! with no isolation lever left (G already defeats ASID isolation, and any
! MD=0 process gets U=1 access). The fix (core/tlb.vhd) rejects G=1&&U=1
! at the protection-check stage on BOTH the I-side and D-side prot blocks,
! so a mistakenly/maliciously installed such entry can never be used by
! anyone, kernel or user.
!
! This guard exercises the D-side path (DPROT_R on a load) since it is
! the more surprising case: prot fires even in KERNEL mode (MD=1), which
! is normally exempt from the plain "u=0 and md=0" user-page check --
! this is a NEW fail-closed rule, not a variant of the existing one.
!
! Construction:
!   - page 0 mapped GLOBAL kernel-only identity (code): W|X|C|G = 0xCC,
!     U cleared -- keeps fetching across the ASID switch below (as in
!     mmuasid.S), and is itself unaffected by the new rule (U=0).
!   - VPN 0x4 (VA 0x4000 -> PA 0x4000): G=1, U=1 (PTEL bit2=1, bit5=1),
!     W|X|C also set (0xEC) -- installed under ASID A.
!   - VPN 0x8 (VA 0x8000 -> PA 0x8000): G=1, U=0 (PTEL = 0xCC), a LEGIT
!     global kernel page -- negative control (non-vacuity): proves the
!     new rule is `G=1 AND U=1` specifically, not `G=1` alone breaking
!     all global hits.
!
!   Leg A (ASID A): load VA 0x4000 (the G=1,U=1 entry) -- must FAULT
!     (DPROT_R, VBR+0x420), even though we are in KERNEL mode (MD=1) and
!     the plain "u=0 and md=0" rule would never have fired here.
!   Leg B (ASID B): same entry, different ASID -- since G=1, the entry
!     still matches (ASID irrelevant to global lookup); must ALSO FAULT.
!     This is the point of the guard: G=1 does not rescue a U=1 global
!     entry into working "for everyone" -- it is unusable, period.
!   Negative control: VA 0x8000 (G=1,U=0) must HIT under BOTH ASID A and
!     ASID B, proving the fix is scoped to U=1 and does not break ordinary
!     global-kernel-page semantics.
!
! VBR = _v_load - 0x420 so the DMISS_R/DPROT_R vector (VBR+0x420) hits
! _v_load, mirroring mmuasid.S / mmufault.S conventions.
!
! PTEL flag bit layout (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C
!                                       bit2=G
!
! Result codes:
!   0  pass
!   1  Leg A: no exception (entry usable despite G=1&&U=1 -- the RED case)
!   2  Leg A: EXPEVT != 0x0C0 (DPROT_R)
!   3  Leg B: no exception (cross-ASID global-user hit -- worse RED case)
!   4  Leg B: EXPEVT != 0x0C0 (DPROT_R)
!   5  negative control: G=1,U=0 page did not HIT under ASID A
!   6  negative control: G=1,U=0 page did not HIT under ASID B (after
!      switching back to A -- see below, checked in the opposite order)

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

        ! ---- Seed PA 0x4000 = SENTINEL1, PA 0x8000 = SENTINEL2, via P1
        ! (untranslated, AT-independent). ----
        mov.l   p_sentinel1, r3
        mov.l   p_p1_4000, r2          ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2
        mov.l   p_sentinel2, r3
        mov.l   p_p1_8000, r2          ! 0x80008000 -> PA 0x8000
        mov.l   r3, @r2

        ! ---- ASIDR = A (0x0011). ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Map page 0 GLOBAL kernel-only identity (code): W|X|C|G = 0xCC,
        ! U cleared -- keeps executing across ASID switches, itself
        ! unaffected by the new rule. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0)
        mov.l   p_ptel_page0, r0       ! 0x000000CC (W|X|C|G, U=0)
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR (re-assert A; global ignores it)
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x4 (VA 0x4000 -> PA 0x4000): G=1,U=1 (PTEL=0xEC),
        ! under ASID A -- the entry under test. ----
        mov.l   p_pteh_p4, r0          ! VPN 0x4
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p4_global_user, r0  ! 0x000040EC (W|X|U|C|G)
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x8 (VA 0x8000 -> PA 0x8000): G=1,U=0 (PTEL=0xCC),
        ! a LEGIT global kernel page -- negative control. ----
        mov.l   p_pteh_p8, r0          ! VPN 0x8
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p8_global_kern, r0  ! 0x000080CC (W|X|C|G, U=0)
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Set up expected fault info for Leg A. ----
        mov.l   p_g_exp_expevt, r0
        mov.l   c_dprot_r, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x0C0 (DPROT_R)
        mov.l   p_g_bad_expevt, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 2
        mov.l   p_g_resume, r0
        mov.l   p_leg_a_after, r1
        mov.l   r1, @r0                 ! resume -> leg_a_after

        ! ---- Leg A (ASID A): load VA 0x4000 (G=1,U=1 entry) -- must FAULT. ----
        mov     #1, r9                  ! sentinel: no exception -> result 1
        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! FAULTS -> _v_load (VBR+0x420), DPROT_R
        bra     _fail                   ! reached only if the load did NOT fault
        nop
ENTRY(leg_a_after)

        ! ---- Switch ASIDR to B (0x0022). Code page is global -> keeps
        ! fetching. ----
        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Re-enable AT (handler disabled it) and set up expected fault
        ! info for Leg B. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        mov.l   p_g_exp_expevt, r0
        mov.l   c_dprot_r, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x0C0 (DPROT_R)
        mov.l   p_g_bad_expevt, r0
        mov     #4, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 4
        mov.l   p_g_resume, r0
        mov.l   p_leg_b_after, r1
        mov.l   r1, @r0                 ! resume -> leg_b_after

        ! ---- Leg B (ASID B): same G=1,U=1 entry -- must ALSO FAULT (global
        ! does not rescue it under a different ASID). ----
        mov     #3, r9                  ! sentinel: no exception -> result 3
        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! FAULTS -> _v_load (VBR+0x420), DPROT_R
        bra     _fail                   ! reached only if the load did NOT fault
        nop
ENTRY(leg_b_after)

        ! ---- Re-enable AT (handler disabled it). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Negative control, part 1: still ASID B. Load VA 0x8000
        ! (G=1,U=0 legit global page) -- must HIT (no fault), returning
        ! SENTINEL2. ----
        mov.l   c_va8, r2
        mov.l   @r2, r8
        mov.l   p_sentinel2, r0
        cmp/eq  r8, r0
        mov     #5, r9                 ! fail 5 = global-kernel page didn't hit under ASID B
        bf      _fail

        ! ---- Negative control, part 2: switch ASIDR back to A. Load VA
        ! 0x8000 again -- must STILL HIT. ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   c_va8, r2
        mov.l   @r2, r8
        mov.l   p_sentinel2, r0
        cmp/eq  r8, r0
        mov     #6, r9                 ! fail 6 = global-kernel page didn't hit under ASID A
        bf      _fail

        bra     _done
        nop

        .align 2
p_rbclear:              .long 0xDFFFFFFF
p_vbr_val:               .long _v_load - 0x420
p_mmucr:                  .long 0xFF000010
p_ptel_page0:             .long 0x000000CC        ! W|X|C|G, U=0 (kernel global code page)
p_pteh_p4:                .long 0x00004000
p_ptel_p4_global_user:    .long 0x000040EC        ! PA 0x4000 | W|X|U|C|G -- the entry under test
p_pteh_p8:                .long 0x00008000
p_ptel_p8_global_kern:    .long 0x000080CC        ! PA 0x8000 | W|X|C|G, U=0 -- negative control
p_asid_a:                 .long 0x00000011
p_asid_b:                 .long 0x00000022
p_sentinel1:              .long 0xA51DA51D
p_sentinel2:              .long 0xB33FB33F
p_p1_4000:                .long 0x80004000
p_p1_8000:                .long 0x80008000
c_va4:                    .long 0x00004000
c_va8:                    .long 0x00008000
c_dprot_r:                .long 0x000000C0        ! EXPEVT DPROT_R
p_g_exp_expevt:           .long _g_exp_expevt
p_g_bad_expevt:           .long _g_bad_expevt
p_g_resume:               .long _g_resume
p_leg_a_after:            .long leg_a_after
p_leg_b_after:            .long leg_b_after

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

        ! ---- DMISS_R/DPROT_R handler at VBR+0x420 (the ONLY pass path for
        ! Legs A and B). Disables AT, verifies EXPEVT == DPROT_R (0x0C0)
        ! -- distinguishing a real protection fault from a plain miss --
        ! then resumes at the caller-selected _g_resume label. ----
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x420
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Hresume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_expevt:
        mov.l   Hbad_expevt, r0
        mov.l   @r0, r9                 ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hexp_expevt:    .long _g_exp_expevt
Hresume:        .long _g_resume
Hbad_expevt:    .long _g_bad_expevt

        ! ---- Handler globals. ----
        .balign 4
_g_exp_expevt:  .long 0
_g_bad_expevt:  .long 0
_g_resume:      .long 0

        ! ---- Backing-page padding: VA 0x4000 and 0x8000. ----
_fault_pages:
        .space 0x8000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
