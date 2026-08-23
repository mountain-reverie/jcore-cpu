! mmupmtlbmask.S -- CONTRACT LOCK C4 (docs/mmu/pagemask-walker-contract.md
! sections 2/C4 and 7.2). Lane 1, cpu_tb.
!
! WHAT THIS LOCKS
! ===============
! C4 says the entry's page size is carried EXACTLY ONCE, in `data` as
! `PTEL[11:8]`, and that it governs the `page_mask` field of the installed TLB
! entry, all subsequent `tlb_match()` / `vpn_compare_mask()` masking, and the
! `page_offset_mask()` relocation. A "fix" that hardwires the installed
! page_mask -- the "assume one page size" shortcut -- would keep every
! base-page guard green while silently turning every superpage into a 4 KB
! page. This guard pins the MIDDLE of the size range (pm=4, 1 MB); its sibling
! mmupmmixzero pins the FINEST end (pm=0) where the same shortcut also hides.
!
! CONSTRUCTION
!   VA 0x0020_0000 -> PA 0x0050_0000, pm=4, so the entry covers
!   VA [0x0020_0000, 0x0030_0000) and relocates PA = 0x0050_0000 + (VA & 0xFFFFF).
!   One TSB row only, for the BASE VA. Nothing else is mapped in that region,
!   so every later access can only be resolved by the installed entry's
!   page_mask.
!
!   phase 1  load VA 0x0020_0000       -> walk hit, installs. Data must be SA
!                                         at PA 0x0050_0000; cnt_hits +1 EXACTLY.
!   phase 2  load VA 0x002F_FFFC       -> the FAR end of the 1 MB page, one
!                                         megabyte minus four from the base.
!                                         Must return SB from PA 0x005F_FFFC,
!                                         must NOT fault, and must NOT walk
!                                         (cnt_walks and cnt_hits both
!                                         unchanged) -- only the page_mask term
!                                         can have translated it.
!   phase 3  load VA 0x0030_0000       -> ONE PAST the page. MUST fault
!                                         (DMISS_R, TEA = 0x0030_0000). This is
!                                         the half that stops the guard from
!                                         being satisfied by an over-wide mask.
!
! COUNTER TRUSTWORTHINESS (contract P1). Phase 2's pass condition is a
! NON-increment, which a dead counter satisfies perfectly. It is therefore
! paired, in the same run, with phase 1's assertion that cnt_hits moved by
! exactly 1. The guard is self-contained; it does not lean on any Group-B
! guard and P1g is not required.
!
! IDENTITY MAPPING. The page under test is NOT identity-mapped
! (VA 0x0020_0000 -> PA 0x0050_0000). The two untranslated addresses an inert
! MMU would reach, PA 0x0020_0000 and PA 0x002F_FFFC, are seeded with poison,
! so "the MMU was never on" fails checks 0x31 / 0x33 rather than passing. The
! frame moves by editing p_ptel_data alone -- identity was not forced.
! The CODE page (VA 0x1000 -> PA 0x1000) is identity, forced by the flat image
! load (README-identity-mapping.md category (b)); no assertion here depends on
! it.
!
! P5 (VA-backing). Every VA touched under AT=1 -- 0x0020_0000, 0x002F_FFFC,
! 0x0030_0000 and the code page -- is inside the cosim's 16 MB backed window.
! Phase 3 deliberately misses, so its raw VA reaches the bus during the miss
! window; 0x0030_0000 is backed.
!
! RESULT CODES (base 0x30)
!   0x31  phase 1: wrong data at VA 0x0020_0000 (translation absent or wrong)
!   0x32  phase 1: cnt_hits delta != 1 -- the entry was not installed by a walk
!   0x33  phase 2: wrong data at VA 0x002F_FFFC
!   0x34  phase 2: the counters MOVED -- the far access walked, so it was not
!                  translated by the installed entry's page_mask
!   0x35  UNEXPECTED fault during phase 1
!   0x36  UNEXPECTED fault during phase 2. THIS IS THE MUTATION CODE for
!         `ram(idx).page_mask <= "0000"`: the entry then covers only 4 KB, so
!         the far access misses and there is no row for it.
!   0x37  phase 3: NO fault at VA 0x0030_0000 -- the entry over-matched past
!         its own 1 MB span
!   0x38  phase 3: EXPEVT is not DMISS_R
!   0x39  phase 3: TEA is not 0x0030_0000
!   0xE6  TRIP: more than one fault in the run. Contract P2's band is
!         `0xE0 | phase`; this guard's data codes are too wide to embed, so it
!         allocates from the documented fallback range phase = 5..10 and uses
!         phase = 6 for its single bounded counter.
!   0xD1  unexpected GENERAL exception (VBR+0x100)
!
! MUTATION EVIDENCE
! =================
! M3 -- THE STATED MUTATION: `ram(idx).page_mask <= "0000";` in core/tlb.vhd's
!       install, i.e. the "assume one page size" fix.
!         mmupmtlbmask  RED, Result=54 (0x36)  <- ITS OWN CODE, "unexpected
!                       fault during phase 2": with the entry reduced to 4 KB
!                       the far end of the page is unmapped and there is no row
!                       for it. Note it is NOT 0x37 (phase 3's "no fault"), so
!                       the phase attribution in the handler is doing its job.
!       Every other Group-C lock also fails under M3 (Results 23 / 39 / 65 / 95
!       / 145) -- expected, since a hardwired page_mask breaks every size above
!       4 KB. M3 is the mutation this guard is FOR; the specificity evidence is
!       the reverse direction below.
!
! SPECIFICITY -- this guard stays GREEN under every mutation aimed elsewhere:
!       M1 (coarse tag accepted)                     PASS
!       M2 (MBZ term deleted)                        PASS
!       M4 (vpn_compare_mask("0000") off n=0)        PASS
!       M5a (tlb_vpn_mx masked by the entry's own mask) PASS
!       M7 (the two mask functions agree above pm=8)  PASS
!       M6 (data before tag_hi)  RED via p_walk_read_order, the global invariant
!
! RESTORED: pristine RTL, PASS.
! All runs: docker ghcr.io/mountain-reverie/jcore-cpu-ci:latest, CPU_VARIANT=j4,
! SIM_TOP=cpu_tb, --stop-time=120us. First measured 2026-08-22 on base 6475932;
! EVERY line above RE-MEASURED FROM SOURCE on 2026-08-23 after the rebase onto
! 9fdfaf6, which carries a68c765's I->D shadow fill. Every result code came out
! identical. Only run-time timings moved; those are A/B'd against the shadow
! fill in docs/mmu/group-c-locks.md section 4b. Every mutation run REBUILT the
! cosim (never `-n`, which skips the build and measures stale hardware). To
! re-apply any mutation you need BOTH halves of docs/mmu/group-c-locks.md:
! section 3 (the edits, one row per mutation) and section 9 (the run). That
! file also carries the full cross-table, which now has no unmeasured cell.
!
!
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

        ! ---- RB=0: core/cpu.vhd's walk_req is gated on dp_sr.rb = '0'.
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed physical memory with AT off (untranslated P0 stores).
        mov.l   p_pa_base, r2
        mov.l   p_sa, r3
        mov.l   r3, @r2                 ! PA 0x00500000 = SA
        mov.l   p_pa_far, r2
        mov.l   p_sb, r3
        mov.l   r3, @r2                 ! PA 0x005FFFFC = SB
        mov.l   p_poison, r3
        mov.l   p_va_base, r2
        mov.l   r3, @r2                 ! PA 0x00200000 = poison
        mov.l   p_va_far, r2
        mov.l   r3, @r2                 ! PA 0x002FFFFC = poison

        ! ---- TSB config. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR = 0
        nop
        nop

        ! ---- Code page -> WAY 1 of its set (never collides with way 0).
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- The ONE row under test: the 1 MB mapping, tagged and indexed at
        ! ---- its own base VA. No other row exists in the whole region, so
        ! ---- phases 2 and 3 can only be answered by the installed entry.
        mov.l   p_va_base, r6
        mov     #0, r7
        mov.l   p_ptel_data, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill r10, r6, r7, r8

        mov     #0, r10                 ! fault count   (unbanked)
        mov     #0, r14                 ! current phase (unbanked)
        bra     _run
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_gen - 0x100
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD ! identity code page, U=0 (SMEP), G=1
p_tsbslot_reg:  .long 0xFF000048
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
p_va_base:      .long 0x00200000
p_va_far:       .long 0x002FFFFC        ! V + 1 MB - 4
p_pa_base:      .long 0x00500000
p_pa_far:       .long 0x005FFFFC
p_ptel_data:    .long 0x005004E9        ! PA 0x00500000, pm=4 (1 MB), W|X|U|C|V
p_sa:           .long 0x51A0B10C
p_sb:           .long 0x5BFA4E5D
p_poison:       .long 0xDEAD0BAD

ENTRY(_run)
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on
        nop
        nop
        nop
        nop

        ! ---- Warm the DTLB for the code page: the I-side walk that resolved
        ! ---- the fetch populated the ITLB only, so the first literal-pool
        ! ---- load under AT still walks. Keeping it out of the phase deltas
        ! ---- is what lets them be exact.
        mov.l   q_warm, r11

        ! ================= PHASE 1: install the 1 MB entry ================
        mov     #1, r14
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13                ! snapshot BEFORE the access
        mov.l   q_va_base, r0
        mov.l   @r0, r4                 ! walk hit -> installs pm=4

        mov.l   q_sa, r0
        cmp/eq  r4, r0
        mov     #0x31, r9
        bf      _fail_at

        ! cnt_hits must have advanced by EXACTLY 1.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        sub     r2, r1
        mov     #1, r0
        cmp/eq  r1, r0
        mov     #0x32, r9
        bf      _fail_at

        ! ============ PHASE 2: the far end of the same 1 MB page ==========
        mov     #2, r14
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13                ! fresh snapshot
        mov.l   q_va_far, r0
        mov.l   @r0, r5                 ! must be answered by page_mask alone

        mov.l   q_sb, r0
        cmp/eq  r5, r0
        mov     #0x33, r9
        bf      _fail_at

        ! Neither counter may have moved: no walk resolved this access.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x34, r9
        bf      _fail_at

        ! ============ PHASE 3: one past the page -- must FAULT ============
        mov     #3, r14
        mov.l   q_va_past, r0
        mov.l   @r0, r6                 ! <-- must FAULT

        mov     #0x37, r9               ! fell through: the entry over-matched
        bra     _fail_at
        nop

_final:
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        bra     _done
        nop

_fail_at:
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
q_mmucr:        .long 0xFF000010
q_warm:         .long 0x00000000
q_walkcnt:      .long 0xFF000054
q_va_base:      .long 0x00200000
q_va_far:       .long 0x002FFFFC
q_va_past:      .long 0x00300000
q_sa:           .long 0x51A0B10C
q_sb:           .long 0x5BFA4E5D

#else
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ---- Vector block: VBR = _v_gen - 0x100. ----
        .balign 0x100
_v_gen:
        mov.l   Hg_code, r9
        bra     _fail
        nop
        .align 2
Hg_code:        .long 0x000000D1

        .space  0x300 - (. - _v_gen)
_v_fault:                               ! = VBR + 0x400
        add     #1, r10
        mov     r10, r0
        cmp/eq  #1, r0
        bt      _first_fault
        mov.l   H_trip, r9              ! bounded: a second fault is a TRIP
        bra     _fail_at
        nop

_first_fault:
        ! Only phase 3 is allowed to fault. Attributing the fault to its phase
        ! is what keeps a broken page_mask (which faults in phase 2) from being
        ! mistaken for the phase-3 fault this guard requires.
        mov     r14, r0
        cmp/eq  #3, r0
        bt      _p3_fault
        mov     r14, r0
        cmp/eq  #1, r0
        bt      _p1_fault
        mov     #0x36, r9               ! unexpected fault in phase 2
        bra     _fail_at
        nop
_p1_fault:
        mov     #0x35, r9               ! unexpected fault in phase 1
        bra     _fail_at
        nop

_p3_fault:
        mov.l   H_expevt, r0
        mov.l   @r0, r1
        mov.l   H_dmiss_r, r2
        cmp/eq  r1, r2
        mov     #0x38, r9
        bf      _fail_at

        mov.l   H_tea, r0
        mov.l   @r0, r1
        mov.l   H_va_past, r2
        cmp/eq  r1, r2
        mov     #0x39, r9
        bf      _fail_at

        ! Deliberately NOT an RTE: the mapping is absent by design, so
        ! restarting the access would re-fault forever. Jump to the exit.
        bra     _final
        nop

        .align 2
H_trip:         .long 0x000000E6
H_expevt:       .long 0xFF000024
H_dmiss_r:      .long 0x00000060
H_tea:          .long 0xFF00000C
H_va_past:      .long 0x00300000

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
