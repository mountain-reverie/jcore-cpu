! mmuasid.S -- ASID cross-tenant isolation + global-bit guard (J4).
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
!   - Leg B (ASID B): load VA 0x4000 must FAULT (DMISS_R, VBR+0x400) -> the
!     handler is the ONLY pass path. If the cross-ASID load instead completes
!     (isolation broken), the main path spins WITHOUT a result -> timeout -> RED.
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
#include "mmuwalk_common.inc"
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

        ! ---- VBR = _v_load - 0x400 (so VBR+0x400 = _v_load). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed PA 0x4000 = SENTINEL via P1 (untranslated, AT-independent). ----
        mov.l   p_sentinel, r3
        mov.l   p_p1_4000, r2          ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2

        ! ---- ASIDR = A (0x0011). ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Configure the TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x
        ! ---- 32 bytes), HASH_SHIFT=6, HASH_MODE=1. Kept clear of the data page
        ! ---- at PA 0x4000. The image is zero-filled, so the fill loop below is
        ! ---- the only thing that populates it. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Both mappings that LDTLB used to install now come from the
        ! ---- (VA, ASID, PTEL) table below, filled by the walker on demand.
        ! ---- The set address for each row is asked of the P4 slot helper
        ! ---- (0xFF000048) UNDER THAT ROW'S ASID, so nothing hand-computes the
        ! ---- hash and the ASID-dependent part of it stays correct. AT is off,
        ! ---- so these are plain P0 stores. ----
        mov.l   p_tsbslot, r12
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
        mov.l   @r14+, r8               ! PTEL
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- Restore ASIDR = A for the run. ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

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

        ! ---- ARM the handler. The handler is the ONLY pass path, so a fault
        ! ---- taken BEFORE the cross-ASID load reports a spurious pass. That is
        ! ---- reachable now that the code page is walker-installed rather than
        ! ---- LDTLB-installed: a broken code-page row faults on the first fetch
        ! ---- under AT and lands in the handler. Measured on this guard.
        mov.l   c_armed_p, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Leg B (ASID B): load VA 0x4000 must FAULT (cross-ASID isolation). ----
        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! FAULTS -> _v_load (VBR+0x400), DMISS_R

        ! If the cross-ASID load completed, isolation is broken. The LDTLB
        ! version spun without a result here, so that defect showed up only as a
        ! timeout -- indistinguishable from a hang or a stop-time overrun. Report
        ! it with its own code instead. AT is dropped first so the P-region
        ! store is reliable.
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #2, r9                  ! 2 = cross-ASID isolation broken
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x400
p_mmucr:        .long 0xFF000010
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:          .long _tsb_tab
p_tab_end:      .long _tsb_tab_end
c_armed_p:      .long _g_armed
p_asid_a:       .long 0x00000011
p_asid_b:       .long 0x00000022
p_sentinel:     .long 0xA51DA51D
p_p1_4000:      .long 0x80004000
c_va4:          .long 0x00004000

        ! ---- The two entries, one row per covered 4 KB VPN. The walker's tag
        ! ---- compare is EXACT on the 4 KB VPN. Every PTEL sets V (bit 0) --
        ! ---- the walker rejects V=0 as "no entry" -- so the old 0xEC/0xE8
        ! ---- constants become 0xCD/0xE9.
        ! ---- Row 1: code page 0, GLOBAL (G), U=0 for SMEP. Global so that the
        ! ---- ASID switch to B below cannot unmap the executing page, which is
        ! ---- exactly what the LDTLB version relied on too.
        ! ---- Row 2: VA 0x4000 -> PA 0x4000, NON-global, tagged ASID A. This
        ! ---- is the entry under test: it must serve ASID A and NOT ASID B.
        .balign 4
_tsb_tab:
        .long 0x00000000, 0x00000011, 0x000000CD  ! code page 0, W|X|C|G|V
        .long 0x00004000, 0x00000011, 0x000040E9  ! PA 0x4000, W|X|U|C|V, ASID A
_tsb_tab_end:

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

        ! ---- DMISS_R handler at VBR+0x400 (the ONLY pass path). ----
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)

        ! ---- Was this the armed access? An unarmed fault is a setup error
        ! ---- (typically the code page failing to walk in) -> result 4.
        mov.l   Harmed, r0
        mov.l   @r0, r0
        tst     r0, r0
        bf      1f
        mov.l   Hresult, r0
        mov     #4, r1
        mov.l   r1, @r0
_h_unarmed: bra _h_unarmed
        nop
1:
        ! ---- Right fault kind? Cross-ASID isolation must present as DMISS_R
        ! ---- (EXPEVT 0x060), not as a protection or write fault. ----
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hdmiss_r, r1
        cmp/eq  r0, r1
        bt      1f
        mov.l   Hresult, r0
        mov     #3, r1
        mov.l   r1, @r0
_h_badexp: bra  _h_badexp
        nop
1:
        ! The cross-ASID load faulted as required: write PASS (result 0).
        mov.l   Hresult, r0
        mov.l   Hresult_pass, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Harmed:         .long _g_armed
Hdmiss_r:       .long 0x00000060        ! EXPEVT for DMISS_R
Hresult:        .long TEST_RESULT_ADDRESS
Hresult_pass:        .long   TEST_PASS_MAGIC

        .balign 4
_g_armed:       .long 0

        ! ---- Backing store: the data page at PA 0x4000 and the TSB at
        ! ---- PA 0x14000..0x15FFF. Zero-filled. ----
_fault_pages:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
