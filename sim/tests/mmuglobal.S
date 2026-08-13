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
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). SAME strength -- every leg,
! every result code and the negative control are unchanged. The three entries
! now come from TSB rows filed under ASID A and are installed by the walker on
! first touch. Two points that matter:
!
!   * The G=1,U=1 entry is REJECTED AT THE PROTECTION STAGE, not at the tag
!     compare, so the walker installs it happily and the access then takes
!     DPROT_R. That is the intended shape: the fail-closed rule must hold
!     against an entry that really is resident, which is exactly what the
!     walker produces.
!   * HASH_MODE=1 puts the ASID in the TSB index, so a row filed under ASID A
!     is NOT found under ASID B. The negative-control page is therefore made
!     resident under ASID A during setup (fail 7 if it does not read back);
!     from then on G=1 is what carries it across the ASID switch -- which is
!     the property the negative control is there to check. The entry under
!     test is likewise resident from leg A onward, so leg B genuinely re-uses
!     one global entry under a second ASID rather than walking a second row in.
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
!     (DPROT_R, VBR+0x400), even though we are in KERNEL mode (MD=1) and
!     the plain "u=0 and md=0" rule would never have fired here.
!   Leg B (ASID B): same entry, different ASID -- since G=1, the entry
!     still matches (ASID irrelevant to global lookup); must ALSO FAULT.
!     This is the point of the guard: G=1 does not rescue a U=1 global
!     entry into working "for everyone" -- it is unusable, period.
!   Negative control: VA 0x8000 (G=1,U=0) must HIT under BOTH ASID A and
!     ASID B, proving the fix is scoped to U=1 and does not break ordinary
!     global-kernel-page semantics.
!
! VBR = _v_load - 0x400 so the DMISS_R/DPROT_R vector (VBR+0x400) hits
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
!   7  setup/warm-up: the G=1,U=0 negative-control page did not read back
!      under ASID A, so it never became resident and legs 5/6 would be
!      testing nothing

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

        ! ---- Seed PA 0x4000 = SENTINEL1, PA 0x8000 = SENTINEL2, via P1
        ! (untranslated, AT-independent). ----
        mov.l   p_sentinel1, r3
        mov.l   p_p1_4000, r2          ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2
        mov.l   p_sentinel2, r3
        mov.l   p_p1_8000, r2          ! 0x80008000 -> PA 0x8000
        mov.l   r3, @r2

        ! ---- Configure the TSB (base 0x00014000, TSB_SIZE_LOG=8 -> 256 sets
        ! ---- x 32 bytes; HASH_SHIFT=6, HASH_MODE=1) and publish the three
        ! ---- rows. Each row's set address is asked of the P4 helper
        ! ---- (0xFF000048) UNDER THAT ROW'S ASID, because HASH_MODE=1 folds
        ! ---- the ASID into the index. AT is off: plain P0 stores.
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
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
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- ASIDR = A (0x0011) for the run. ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- SETUP CHECK / warm-up: make the G=1,U=0 negative-control page
        ! ---- resident under ASID A. Its row is filed under A only, so this is
        ! ---- the one chance the walker gets to install it; legs 5 and 6 then
        ! ---- test whether G=1 carries the RESIDENT entry across the ASID
        ! ---- switch, which is the property they name.
        mov.l   c_va8, r2
        mov.l   @r2, r8
        mov.l   p_sentinel2, r0
        cmp/eq  r8, r0
        bt      1f
        mov.l   p_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov     #7, r9
        bra     _fail
        nop
1:

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
        mov.l   @r2, r8                 ! FAULTS -> _v_load (VBR+0x400), DPROT_R
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
        mov.l   @r2, r8                 ! FAULTS -> _v_load (VBR+0x400), DPROT_R
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
p_vbr_val:               .long _vbase
p_mmucr:                  .long 0xFF000010
p_tsbbr_addr:             .long 0xFF000014
p_tsbbr_val:              .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:            .long 0xFF000018
p_tsbcfg_val:             .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:                .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:                    .long _tsb_tab
p_tab_end:                .long _tsb_tab_end
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

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000011, 0x000000CD  ! page 0 W|X|C|G|V, U=0 (code)
        .long 0x00004000, 0x00000011, 0x000040ED  ! PA 0x4000 W|X|U|C|G|V -- under test
        .long 0x00008000, 0x00000011, 0x000080CD  ! PA 0x8000 W|X|C|G|V, U=0 -- control
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

        ! ---- DMISS_R/DPROT_R handler at VBR+0x400 (the ONLY pass path for
        ! Legs A and B). Disables AT, verifies EXPEVT == DPROT_R (0x0C0)
        ! -- distinguishing a real protection fault from a plain miss --
        ! then resumes at the caller-selected _g_resume label. ----
        .balign 4
        .space 0x620, 0
        .balign 4
! ---- Vector page (VBR = _vbase) ----
! Since TLB protection faults were split off the miss vector to VBR+0x100
! (matching SH-4: misses H'400, protection H'100), a guard that only places
! code at +0x400 sends every IPROT/DPROT_R/DPROT_W into whatever happens to
! sit 0x300 bytes before its handler. The old `VBR = _v_load - 0x400` idiom had
! no valid +0x100 at all. Both vectors now land on the same EXPEVT-driven
! handler, so every assertion below is unchanged; only the arrival path is.
        .balign 4
_vbase:
        .org    _vbase + 0x100
_v_prot:                                ! VBR+0x100: IPROT / DPROT_R / DPROT_W
        bra     _v_load
        nop
        .org    _vbase + 0x400
_v_load:                                ! = VBR + 0x400
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
_g_exp_expevt:  .long 0xFFFFFFFF        ! sentinel: unset (a real sub-test always overwrites)
_g_bad_expevt:  .long 0x5A              ! loud fail-code sentinel: names an early fault
_g_resume:      .long 0

        ! ---- Backing store: the mapped pages (PA 0x4000, 0x8000) and the TSB
        ! ---- at PA 0x14000..0x15FFF. The walker reads the TSB by PHYSICAL
        ! ---- address and a physical alias is backed by SRAM only within the
        ! ---- loaded image extent, so the image must reach past the TSB end.
_fault_pages:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
