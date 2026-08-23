! mmupmreservedpm.S -- CONTRACT LOCK C6g, pinning C8
! (docs/mmu/pagemask-walker-contract.md sections 2/C8 and 7.2). Lane 1, cpu_tb.
!
! WHAT THIS PINS -- A HAZARD, NOT A FEATURE
! =========================================
! C8 says `data[11:8]` (PageMask) MUST be in 0..8; 9..15 are RESERVED. The
! walker installs PageMask VERBATIM AND UNVALIDATED (core/tlb.vhd:398) and the
! two mask functions DISAGREE above pm=8 (core/components_pkg.vhd):
! `page_offset_mask()` saturates at n=16 (`when others`), while
! `vpn_compare_mask()` continues to n=18 at pm=9 and n=20 at pm>=10.
!
! The consequences, which this guard MEASURES rather than infers -- assumption
! A8 in the contract records that they were read from source and never
! executed:
!
!   pm >= 10  the VPN compare mask is ALL ZEROS, so the entry is a WILDCARD:
!             it matches EVERY VA in the ASID, in every 256 MB region, and
!             relocates as if it were 256 MB (PA = VA & 0x0FFF_FFFF, since
!             cpu.vhd forces PA[31:28] = 0).
!   pm = 9    incoherent in a different way: the compare ignores VA[29:12] --
!             so it matches everything below 1 GB -- while the relocation still
!             substitutes only PA[27:12], i.e. still behaves as 256 MB.
!
! The guard ASSERTS EXACTLY THAT, so the hazard is pinned in a running test
! rather than discovered later by someone who mistakes the wildcard for an
! intended 1 GB / 4 GB page. Nothing in hardware enforces C8 -- that is why C8
! is a software obligation and this is a documentation lock.
!
! CONSTRUCTION -- how a "different 256 MB region" is reachable at all
! ------------------------------------------------------------------
! pm=9 and pm=10 are behaviourally IDENTICAL to pm=8 everywhere inside the
! cosim's 16 MB backed window, so the difference is only observable at a VA
! >= 0x1000_0000. That looks like it collides with contract P5 (every VA
! dereferenced under AT=1 must itself be backed) -- and it would, if the access
! MISSED, because the raw VA is driven onto the bus during the miss window.
! It does not, and the arithmetic is worth stating:
!
!   * core/cpu.vhd's relocation arm forces `db_o.a(31 downto 28) <= "0000"` on
!     every translated hit and splices only PA[27:12]. So VA 0x1060_0000
!     resolves to PA 0x0060_0000 -- inside the backed window -- even though the
!     VA is not.
!   * On this RTL the probe VA HITS the resident wildcard, so there is no miss
!     window and the raw VA never reaches the bus. P5 is satisfied for every
!     access this guard actually performs.
!   * The probe VA is nonetheless given its OWN TSB row, pointing at a
!     DIFFERENT frame. That row is PROVABLY NEVER READ on this RTL (the counter
!     assertion is exactly that claim) -- it exists so that under the mutation,
!     where the probe does miss, the walk RESOLVES instead of stranding an
!     unbacked raw VA on the bus. Without it the mutation would wedge the
!     machine instead of turning this guard red, which
!     jcore-cpu/CLAUDE.md rules out. Because the row's frame differs, the
!     mutation fails the DATA check too, not only the counter check.
!
! THE FOUR PHASES
!   1  touch V1 = 0x0080_0000, whose row carries pm=10. Walk hit, cnt_hits +1
!      exactly. Data = the sentinel at PA 0x0080_0000.
!   2  touch V2 = 0x1060_0000 -- a DIFFERENT 256 MB region. It must return the
!      sentinel at PA 0x0060_0000 (the wildcard's relocation) and NEITHER
!      counter may move: the wildcard, not V2's own row, answered it.
!   3  MMUCR = TI|AT to evict the wildcard (the TSB survives a TI flush), then
!      touch V3 = 0x0090_0000, whose row carries pm=9. Walk hit, cnt_hits +1.
!   4  touch V4 = 0x1070_0000: same shape, proving the pm=9 compare ignores
!      VA[29:12] while the relocation still substitutes only PA[27:12].
!
! Phase 3 needs the TI flush because a resident wildcard matches V3 too, so
! without it V3 would never miss and the pm=9 row would never install.
!
! IDENTITY MAPPING (CLAUDE.md "Never identity-map the page under test")
! -------------------------------------------------------------------
! V1 and V3 ARE identity-mapped, and identity is FORCED here by arithmetic, not
! chosen: at pm >= 6 `page_offset_mask()` marks PA bits 12..23 (12..27 at the
! saturated value these entries use) as in-page offset sourced from the VA, so
! every PPN bit that survives must be zero to keep the PA backed, and the
! translation degenerates to identity inside the window. This is category (a)
! of sim/tests/README-identity-mapping.md. The witnesses are:
!   * an exact cnt_hits delta of +1 taken ACROSS each of those two accesses,
!     so the walk is attributed to the access under test rather than to the
!     run as a whole; and
!   * phases 2 and 4, which are NOT identity (VA 0x1060_0000 -> PA 0x0060_0000
!     and VA 0x1070_0000 -> PA 0x0070_0000) and are the phases carrying the
!     assertions this guard exists for.
! Every VA-as-physical address is additionally seeded with poison, so an inert
! MMU fails phase 1 immediately.
! The CODE page (VA 0x0000 -> PA 0x0000) is identity, forced by the flat image
! load (category (b)); no assertion depends on it.
!
! A NOTE ON WHAT THE WILDCARD DOES TO THIS HARNESS. Once installed, the
! wildcard matches the guard's own literal-pool loads and REPLACES the code
! page's DTLB entry under core/tlb.vhd's install-time dedup (the intersection
! of an all-zero mask with anything is all-zero, so everything overlaps). The
! guard keeps working only because the code page is identity, so the wildcard
! relocates it to the same physical address. That is a real property of a
! wildcard entry and is worth seeing stated: a stray pm >= 9 PTE does not fault,
! it silently swallows the whole address space.
!
! RESULT CODES (base 0x90)
!   0x91  phase 1: wrong data at V1 -- the pm=10 row did not install, or the
!         relocation is not PA = VA & 0x0FFF_FFFF
!   0x92  phase 1: cnt_hits delta != 1
!   0x93  phase 2: wrong data at V2 -- got V2's OWN frame, so the wildcard did
!         not cover a different 256 MB region.  MUTATION CODE.
!   0x94  phase 2: the counters MOVED -- V2 was resolved by a fresh walk of its
!         own row rather than by the resident wildcard.  MUTATION CODE.
!   0x95  phase 3: wrong data at V3 (pm=9)
!   0x96  phase 3: cnt_hits delta != 1
!   0x97  phase 4: wrong data at V4.  MUTATION CODE (pm=9 arm).
!   0x98  phase 4: the counters MOVED.  MUTATION CODE (pm=9 arm).
!   0x9F  any fault; no access in this guard may fault
!   0xEA  TRIP: a second fault (contract P2 fallback range, phase = 10)
!   0xD1  unexpected GENERAL exception (VBR+0x100); a MULTI_HIT lands here
!
! MUTATION EVIDENCE
! =================
!   (see the block at the end of this header)
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

        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        mov.l   p_seed, r14
        mov.l   p_seed_end, r5
1:      mov.l   @r14+, r0
        mov.l   @r14+, r1
        mov.l   r1, @r0
        cmp/hs  r5, r14
        bf      1b

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

        ! ---- Code page -> WAY 1 of set 0. VA 0x0000 -> PA 0x0000, the whole
        ! ---- image; identity is forced by the flat image load.
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- The four rows. Sets 0x20 / 0x18 / 0x24 / 0x1C, all distinct and
        ! ---- distinct from the code page's set 0x00.
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6              ! VA
        mov.l   @r14+, r7              ! ASID
        mov.l   @r14+, r8              ! PTEL
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        mov     #0, r10                 ! fault count
        bra     _run
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_gen - 0x100
p_pteh_code:    .long 0x00000000
p_ptel_code:    .long 0x000000CD        ! identity code page, U=0 (SMEP), G=1
p_tsbslot_reg:  .long 0xFF000048
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
p_seed:         .long _seed_tab
p_seed_end:     .long _seed_tab_end
p_tab:          .long _tsb_tab
p_tab_end:      .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00800000, 0x00000000, 0x00000AE9  ! V1  pm=10 RESERVED wildcard
        .long 0x10600000, 0x00000000, 0x006500E9  ! V2  own row, NEVER READ
        .long 0x00900000, 0x00000000, 0x000009E9  ! V3  pm=9  RESERVED
        .long 0x10700000, 0x00000000, 0x007500E9  ! V4  own row, NEVER READ
_tsb_tab_end:

        .balign 4
_seed_tab:
        .long 0x00800000, 0xC1000001    ! V1 relocates here (identity, forced)
        .long 0x00600000, 0xC2000002    ! V2 relocates here VIA THE WILDCARD
        .long 0x00650000, 0xBAD00002    ! V2's OWN row's frame -- must NOT be
        .long 0x00900000, 0xC3000003    ! V3 relocates here (identity, forced)
        .long 0x00700000, 0xC4000004    ! V4 relocates here VIA the pm=9 entry
        .long 0x00750000, 0xBAD00004    ! V4's OWN row's frame -- must NOT be
_seed_tab_end:

ENTRY(_run)
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on
        nop
        nop
        nop
        nop

        mov.l   q_warm, r7              ! warm the DTLB for the code page

        ! ============== PHASE 1: install the pm=10 wildcard ==============
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_v1, r0
        mov.l   @r0, r4

        mov.l   q_c1, r0
        cmp/eq  r4, r0
        mov     #0x91, r9
        bf      _fail_at

        bsr     _delta1                 ! cnt_hits must be exactly +1
        mov     #0x92, r12

        ! ====== PHASE 2: a VA in a DIFFERENT 256 MB region hits it =======
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_v2, r0
        mov.l   @r0, r5

        mov.l   q_c2, r0
        cmp/eq  r5, r0
        mov     #0x93, r9
        bf      _fail_at

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x94, r9
        bf      _fail_at

        ! ====== PHASE 3: flush the TLB, then install the pm=9 entry ======
        ! MMUCR = TI|AT. TI is a self-clearing strobe over the TLB only -- the
        ! TSB deliberately survives it -- so the rows written above are still
        ! there and V3 can now miss and walk.
        mov.l   q_mmucr, r0
        mov     #5, r1
        mov.l   r1, @r0
        nop
        nop
        nop
        nop
        mov.l   q_warm, r7              ! re-warm the DTLB (and, implicitly,
                                        ! the ITLB via this very fetch)
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_v3, r0
        mov.l   @r0, r6

        mov.l   q_c3, r0
        cmp/eq  r6, r0
        mov     #0x95, r9
        bf      _fail_at

        bsr     _delta1
        mov     #0x96, r12

        ! ====== PHASE 4: pm=9 matches below 1 GB, relocates as 256 MB =====
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_v4, r0
        mov.l   @r0, r8

        mov.l   q_c4, r0
        cmp/eq  r8, r0
        mov     #0x97, r9
        bf      _fail_at

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x98, r9
        bf      _fail_at

        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

        ! ---- _delta1: cnt_hits must have advanced by exactly 1 past r13.
        ! ---- r12 carries the fail code (set in the bsr delay slot).
_delta1:
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        sub     r2, r1
        mov     #1, r0
        cmp/eq  r1, r0
        bf      _delta_bad
        rts
        nop
_delta_bad:
        mov     r12, r9
        bra     _fail_at
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
q_v1:           .long 0x00800000
q_v2:           .long 0x10600000
q_v3:           .long 0x00900000
q_v4:           .long 0x10700000
q_c1:           .long 0xC1000001
q_c2:           .long 0xC2000002
q_c3:           .long 0xC3000003
q_c4:           .long 0xC4000004

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
        ! `mov #imm, Rn` SIGN-EXTENDS 8 bits, and this guard's codes reach into
        ! the 0x80/0x90 band, so 0x85 would otherwise be reported as
        ! 0xFFFFFF85. Normalise here rather than at every use site; every code
        ! this file can emit fits in a byte.
        extu.b  r9, r9
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
        .balign 0x100
_v_gen:
        mov.l   Hg_code, r9             ! 0xD1 -- a MULTI_HIT lands here too
        bra     _fail
        nop
        .align 2
Hg_code:        .long 0x000000D1

        .space  0x300 - (. - _v_gen)
_v_fault:                               ! = VBR + 0x400
        add     #1, r10
        mov     r10, r0
        cmp/eq  #1, r0
        bt      1f
        mov.l   H_trip, r9
        bra     _fail_at
        nop
1:
        mov     #0x9F, r9
        bra     _fail_at
        nop

        .align 2
H_trip:         .long 0x000000EA

#endif  ! CONFIG_PRIV_ARCH
