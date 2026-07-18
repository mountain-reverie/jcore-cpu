! mmumultihit.S -- S-I5: a duplicate TLB install (two VALID entries that
!                  both match the same VPN+ASID on a single lookup) is a
!                  DEFINED, non-recoverable fault -- never a silent
!                  last-match-wins pick of one of the matching PAs.
!
! Security property (MMU security review, S-I5): before this fix, tlb.vhd's
! lookup loop let the LAST (highest-index) matching entry silently win a
! multi-hit. A duplicate VPN+ASID install is a kernel bug (e.g. a stale
! entry never invalidated before a fresh LDTLB, or a TLB-management race),
! and "pick one of N candidate PAs, unspecified which" is exactly the kind
! of undefined behavior that turns a software bug into an exploitable
! address-confusion primitive (attacker-influenced choice of which PA a VA
! resolves to). The fix (core/tlb.vhd i_multihit/d_multihit, priority over
! hit_found) makes a multi-hit a defined, non-recoverable fault instead:
! it is routed (core/cpu.vhd, decode/decode_core.vhm) to the EXISTING
! General Illegal register-model exception (EXPEVT=0x180, PC<-VBR+0x100)
! rather than minting a new dedicated EXPEVT/vector pair -- the decoder's
! system-plane immediate-value field was already at capacity (32/32
! distinct constants); see components_pkg.vhd's tlb_exc_kind_t comment.
!
! Construction:
!   - page 0 mapped identity, kernel-only (non-global, non-duplicate):
!     W|X|C = 0xC8 -- keeps fetching, itself unaffected by the new rule.
!   - VPN 0x4 (VA 0x4000): installed TWICE under the SAME ASID with
!     DIFFERENT PPNs (PA 0x4000 then PA 0x9000) via two separate LDTLBs.
!     tlb.vhd's LDTLB has no duplicate-detection, so both entries land in
!     distinct (different) valid slots -- exactly the "duplicate install"
!     scenario under test.
!   - VPN 0x5 (VA 0x5000 -> PA 0x5000): installed ONCE -- negative control.
!
!   Test 1: load VA 0x4000 (the duplicate-installed VPN) -- must FAULT
!     (General Illegal, EXPEVT=0x180 at VBR+0x100), and the destination
!     register must be left holding its PRE-FAULT sentinel value (proving
!     neither PPN 0x4000's nor PPN 0x9000's data was silently returned --
!     the precise-exception writeback squash applies here too).
!   Negative control: load VA 0x5000 (single install) -- must HIT normally,
!     returning the correct PA 0x5000 data, no exception.
!
! VBR = _v_gi - 0x100 so the General Illegal vector (VBR+0x100) hits _v_gi.
!
! PTEL flag bit layout (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C
!                                       bit2=G bit1=STALE bit0=V
!
! Result codes:
!   0  pass
!   1  duplicate-install load: no exception (multi-hit silently resolved
!      -- the RED case this guard exists to catch)
!   2  duplicate-install load: EXPEVT != 0x180 (General Illegal)
!   3  duplicate-install load: destination register was NOT left at the
!      pre-fault sentinel (a PPN's data leaked through despite the fault)
!   4  negative control: single-install load did not HIT (unexpected
!      exception)
!   5  negative control: single-install load returned wrong data

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

        ! ---- VBR = _v_gi - 0x100 (so VBR+0x100 = _v_gi, the General
        ! Illegal vector). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed PA 0x4000 = SENTINEL_A, PA 0x9000 = SENTINEL_B,
        ! PA 0x5000 = SENTINEL_C, via P1 (untranslated, AT-independent). ----
        mov.l   p_sentinel_a, r3
        mov.l   p_p1_4000, r2          ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2
        mov.l   p_sentinel_b, r3
        mov.l   p_p1_9000, r2          ! 0x80009000 -> PA 0x9000
        mov.l   r3, @r2
        mov.l   p_sentinel_c, r3
        mov.l   p_p1_5000, r2          ! 0x80005000 -> PA 0x5000
        mov.l   r3, @r2

        ! ---- ASIDR = A. ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Map page 0 identity, kernel-only: W|X|C = 0xC8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0)
        mov.l   p_ptel_page0, r0       ! 0x000000C8 (W|X|C)
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x4 (VA 0x4000 -> PA 0x4000) under ASID A --
        ! FIRST install. ----
        mov.l   p_pteh_p4, r0          ! VPN 0x4
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p4_a, r0        ! PA 0x4000 | W|C
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x4 AGAIN (VA 0x4000 -> PA 0x9000), SAME ASID --
        ! SECOND (duplicate) install: two valid entries now match VPN
        ! 0x4 + ASID A simultaneously. ----
        mov.l   p_pteh_p4, r0          ! VPN 0x4 (same as above)
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p4_b, r0        ! PA 0x9000 | W|C (different PPN)
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x5 (VA 0x5000 -> PA 0x5000) under ASID A --
        ! single install, negative control. ----
        mov.l   p_pteh_p5, r0          ! VPN 0x5
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p5, r0          ! PA 0x5000 | W|C
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Set up expected fault info for the duplicate-install load. ----
        mov.l   p_g_exp_expevt, r0
        mov.l   c_general_illegal, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x180 (General Illegal)
        mov.l   p_g_bad_expevt, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 2
        mov.l   p_g_resume, r0
        mov.l   p_after_multihit, r1
        mov.l   r1, @r0                 ! resume -> after_multihit

        ! ---- Duplicate-install load: read VA 0x4000 (matches BOTH the
        ! PA-0x4000 and PA-0x9000 entries under ASID A) -- must FAULT. ----
        mov.l   p_sentinel_pre, r0
        mov     r0, r8                  ! r8 = pre-fault sentinel
        mov     #1, r9                  ! sentinel: no exception -> result 1
        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! FAULTS -> _v_gi (VBR+0x100), General Illegal
        bra     _fail                   ! reached only if the load did NOT fault
        nop
ENTRY(after_multihit)

        ! ---- r8 must still hold the pre-fault sentinel: neither PPN's
        ! data (SENTINEL_A nor SENTINEL_B) was silently returned. ----
        mov.l   p_sentinel_pre, r0
        cmp/eq  r8, r0
        mov     #3, r9                  ! fail 3 = a PPN's data leaked through
        bf      _fail

        ! ---- Re-enable AT (handler disabled it). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Negative control: load VA 0x5000 (single install) -- must
        ! HIT normally, returning PA 0x5000's data. ----
        mov.l   c_va5, r2
        mov.l   @r2, r8
        mov.l   p_sentinel_c, r0
        cmp/eq  r8, r0
        mov     #5, r9                  ! fail 5 = wrong data on single-install hit
        bf      _fail

        bra     _done
        nop

        .align 2
p_rbclear:              .long 0xDFFFFFFF
p_vbr_val:               .long _v_gi - 0x100
p_mmucr:                  .long 0xFF000010
p_ptel_page0:             .long 0x000000C8        ! W|X|C, kernel-only identity code page
p_pteh_p4:                .long 0x00004000
p_ptel_p4_a:              .long 0x000040C8        ! PA 0x4000 | W|C -- first (duplicate) install
p_ptel_p4_b:              .long 0x000090C8        ! PA 0x9000 | W|C -- second (duplicate) install
p_pteh_p5:                .long 0x00005000
p_ptel_p5:                .long 0x000050C8        ! PA 0x5000 | W|C -- negative control, single install
p_asid_a:                 .long 0x00000011
p_sentinel_a:              .long 0xA51DA51D        ! at PA 0x4000
p_sentinel_b:              .long 0xB33FB33F        ! at PA 0x9000
p_sentinel_c:              .long 0xC0FFEE00        ! at PA 0x5000
p_sentinel_pre:            .long 0xDEAD0BAD        ! pre-fault r8 value; must survive the fault
p_p1_4000:                .long 0x80004000
p_p1_9000:                .long 0x80009000
p_p1_5000:                .long 0x80005000
c_va4:                    .long 0x00004000
c_va5:                    .long 0x00005000
c_general_illegal:        .long 0x00000180        ! EXPEVT General Illegal
p_g_exp_expevt:           .long _g_exp_expevt
p_g_bad_expevt:           .long _g_bad_expevt
p_g_resume:               .long _g_resume
p_after_multihit:         .long after_multihit

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

        ! ---- General Illegal handler at VBR+0x100 (the ONLY pass path for
        ! the duplicate-install load). Disables AT, verifies EXPEVT == 0x180
        ! (General Illegal) -- distinguishing S-I5's multi-hit dispatch from
        ! any other trap -- then resumes at the caller-selected _g_resume
        ! label. ----
        .balign 4
        .space 0x100, 0
        .balign 4
_v_gi:                                   ! = VBR + 0x100
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

        ! ---- Backing-page padding: VA 0x4000, 0x5000, 0x9000. ----
_fault_pages:
        .space 0x9000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
