! mmupmmixzero.S -- CONTRACT LOCK C7g (docs/mmu/pagemask-walker-contract.md
! section 7.2 and its C7g note). Lane 1, cpu_tb.
!
! WHAT THIS LOCKS
! ===============
! C7g is the pm=0 (4 KB) arm of the contract's "base + several huge sizes
! simultaneously resident, interleaved" requirement. It lives in Group C, not
! Group B, because it PASSES on today's RTL -- the RTL is correct, which is
! what the whole contract argues -- so its non-vacuity comes from the stated
! mutations (P4), not from a red/green transition.
!
! pm=0 is a genuinely supported HARDWARE page size even though no correct Linux
! build can emit it (K3 pins PAGE_SHIFT=14 and jcore_pm_for_slot[] starts at 1).
! It is the exact opposite extreme from pm=8: `page_offset_mask("0000")` is
! all-zero, so EVERY PPN[27:12] bit is live, and `vpn_compare_mask("0000")` is
! all-ones, so the WHOLE VPN[31:12] is compared. Hand-built PTELs reach it
! perfectly well; a Linux build cannot, which is why B7 was retired and this
! guard is where 4 KB coverage lives.
!
! CONSTRUCTION -- five mappings, one ASID, live at once
!   V0  0x0010_0000  pm=0  4 KB   -> PA 0x0070_0000
!   V0b 0x0010_1000  pm=0  4 KB   -> PA 0x0081_0000   <- ADJACENT to V0
!   V1  0x0020_0000  pm=1  16 KB  -> PA 0x0090_0000
!   V2  0x0030_0000  pm=2  64 KB  -> PA 0x00A0_0000
!   V3  0x0040_0000  pm=4  1 MB   -> PA 0x00B0_0000
!
! THE ADJACENT 4 KB PAIR IS THE SHARPEST PART. V0 and V0b are 4 KB apart, so
! they are distinguishable ONLY because pm=0 compares the full VPN[31:12]. If
! `vpn_compare_mask("0000")` moved off n=0 -- or if the installed page_mask were
! hardwired to anything wider -- the two would alias and V0b would read V0's
! frame. They relocate to frames 0x11_0000 bytes apart, so the aliasing shows up
! as a wrong sentinel, not as a subtle offset.
!
! DISJOINTNESS (the construction constraint that makes this case non-vacuous).
! `core/tlb.vhd`'s install-time dedup (:357-365) replaces IN PLACE whenever a
! new entry overlaps a resident one under the INTERSECTION of the two page
! masks -- i.e. under the COARSER mask. The five mappings are therefore placed
! one per 1 MB region (the coarsest granularity present, pm=4), so no install
! evicts another and the case cannot silently degrade into testing one entry at
! a time. The V0 / V0b pair is the ONE deliberate exception the contract allows:
! at pm=0 on both sides the intersection is the full VPN compare, so they do
! not overlap and both stay resident.
!
! THE ROUNDS
!   round 0  first touch of each mapping, in a deliberately MIXED size order
!            (16 KB, 1 MB, 4 KB, 64 KB, 4 KB): each must return its own
!            sentinel, and cnt_hits must advance by EXACTLY 5 -- five walks,
!            five installs, nothing evicted.
!   round 1  interleaved OFF-BASE reads: V0+0x100, V1+0x2000 (a different 4 KB
!            sub-page, so only pm=1 can cover it), V0b+0x100, V2+0x5000 (pm=2),
!            V3+0x30000 (pm=4). Each must return its own sentinel and NEITHER
!            counter may move -- every one of the five is answered by a
!            resident entry's own page_mask at its own granularity, at the same
!            time.
!   round 2  re-read all five base words in yet another order: the five entries
!            are still resident and still distinct, and again nothing walks.
!
! COUNTER TRUSTWORTHINESS (contract P1). Rounds 1 and 2 assert NON-increments,
! which a dead counter satisfies. They are paired, in the same run, with round
! 0's exact +5 cnt_hits assertion. The guard is self-contained: it does not
! lean on any Group-B guard, and P1g is not required.
!
! MULTI_HIT. A TLB multi-hit vectors to VBR+0x100, which this guard's general
! stub reports as 0xD1. So "no MULTI_HIT ever" is asserted by construction --
! any multi-hit ends the run with a distinct code rather than being absorbed.
!
! IDENTITY MAPPING. None of the five pages is identity-mapped, and every
! untranslated address the guard would reach with the MMU inert is seeded with
! poison, so an inert MMU fails the very first data check. The frames all move
! by editing the PTEL table alone. The CODE page (VA 0x1000 -> PA 0x1000) is
! identity, forced by the flat image load (README-identity-mapping.md category
! (b)); no assertion depends on it.
!
! P5 (VA-backing). Every VA touched under AT=1 is below 0x0010_0000 + 4 MB and
! so inside the cosim's 16 MB backed window. Round 0's five first touches miss,
! so their raw VAs reach the bus during the miss window; all are backed.
!
! RESULT CODES
!   0x50..0x54  round 0: wrong data, one code per touch in order
!               (V1, V3, V0, V2, V0b)
!   0x58        round 0: cnt_hits delta != 5
!   0x60..0x64  round 1: wrong data, one code per touch in order
!               (V0+0x100, V1+0x2000, V0b+0x100, V2+0x5000, V3+0x30000).
!               0x62 is the ADJACENT-4 KB code: V0b returned V0's frame.
!   0x68        round 1: the counters MOVED -- some access was resolved by a
!               fresh walk instead of by a resident entry's page_mask
!   0x70..0x74  round 2: wrong data (V0b, V2, V0, V3, V1)
!   0x78        round 2: the counters MOVED -- an entry had been evicted
!   0x5F        a TLB fault fired; no access in this guard may fault
!   0xE8        TRIP: a second fault (contract P2 fallback range, phase = 8)
!   0xD1        VBR+0x100: general exception -- a MULTI_HIT lands here
!
! MUTATION EVIDENCE
! =================
! M4 -- THE STATED MUTATION (ii): `vpn_compare_mask("0000")` moved off n=0
!       (n := 2), which is precisely "merge the two adjacent 4 KB pages".
!         mmupmmixzero  RED, Result=84 (0x54)  <- ITS OWN CODE
!         mmuwalkcoarsetag PASS   mmuwalktagmbz PASS
!         mmupmtlbmask     PASS   mmupmrawvpn   PASS
!         mmuwalkreadorder PASS   mmupmreservedpm PASS
!       So M4 is caught HERE and nowhere else -- the pm=0 arm of the matrix is
!       load-bearing, not decorative.
!
!       WHERE it fails is more informative than the code alone. 0x54 is round
!       0's FIFTH touch, V0b's own first touch -- not round 1 as one might
!       expect. With the compare widened, V0b's access MATCHES the already
!       resident V0 entry, so it never misses, never walks, and relocates
!       through V0's frame: it reads 0xA0000000 where 0xA0B0000B is planted.
!       The two adjacent 4 KB pages have merged, exactly as C7g says they must
!       not, and the guard sees it at the earliest possible instant.
!
! M3 -- THE STATED MUTATION (i): `ram(idx).page_mask <= "0000"` on install.
!       RED, Result=95 (0x5F), "a fault fired": with every entry reduced to
!       4 KB, round 1's V1+0x2000 has no coverage and no row of its own.
!
! SPECIFICITY: M1 PASS, M2 PASS, M5a PASS, M7 (masks agree above pm=8) PASS.
! M6 (data before tag_hi) RED via p_walk_read_order, the global invariant.
!
! RESTORED: pristine RTL, PASS.
! All runs: docker ghcr.io/mountain-reverie/jcore-cpu-ci:latest, CPU_VARIANT=j4,
! SIM_TOP=cpu_tb, --stop-time=120us, measured 2026-08-22. Every mutation run
! REBUILT the cosim (never `-n`, which skips the build and measures stale
! hardware). Mutations are applied and reverted by
! /scratch/mut.py in the session log; the full cross-table is in
! docs/mmu/group-c-locks.md.
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

        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed physical memory from the (PA, value) table, AT off. The
        ! ---- table carries BOTH the sentinels at the relocated PAs and poison
        ! ---- at every address an untranslated access would reach.
        mov.l   p_seed, r14
        mov.l   p_seed_end, r5
1:      mov.l   @r14+, r0
        mov.l   @r14+, r1
        mov.l   r1, @r0
        cmp/hs  r5, r14
        bf      1b

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

        ! ---- Code page -> WAY 1 (cannot collide with the five data rows,
        ! ---- which all go to way 0 of five distinct sets).
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- The five rows, from the (VA, ASID, PTEL) table. Each row's set
        ! ---- comes from the P4 slot helper, so no hash is hand-computed.
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
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD
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
        .long 0x00100000, 0x00000000, 0x007000E9  ! V0  4 KB  -> PA 0x00700000
        .long 0x00101000, 0x00000000, 0x008100E9  ! V0b 4 KB  -> PA 0x00810000
        .long 0x00200000, 0x00000000, 0x009001E9  ! V1  16 KB -> PA 0x00900000
        .long 0x00300000, 0x00000000, 0x00A002E9  ! V2  64 KB -> PA 0x00A00000
        .long 0x00400000, 0x00000000, 0x00B004E9  ! V3  1 MB  -> PA 0x00B00000
_tsb_tab_end:

        .balign 4
_seed_tab:
        ! ---- sentinels at the RELOCATED physical addresses ----
        .long 0x00700000, 0xA0000000    ! V0  + 0
        .long 0x00700100, 0xB0000100    ! V0  + 0x100
        .long 0x00810000, 0xA0B0000B    ! V0b + 0
        .long 0x00810100, 0xB0B00100    ! V0b + 0x100
        .long 0x00900000, 0xA1000001    ! V1  + 0
        .long 0x00902000, 0xB1002000    ! V1  + 0x2000
        .long 0x00A00000, 0xA2000002    ! V2  + 0
        .long 0x00A05000, 0xB2005000    ! V2  + 0x5000
        .long 0x00B00000, 0xA3000003    ! V3  + 0
        .long 0x00B30000, 0xB3030000    ! V3  + 0x30000
        ! ---- poison at every VA-as-physical address: with the MMU inert
        ! ---- every data check below reads poison and fails.
        .long 0x00100000, 0xDEAD0BAD
        .long 0x00100100, 0xDEAD0BAD
        .long 0x00101000, 0xDEAD0BAD
        .long 0x00101100, 0xDEAD0BAD
        .long 0x00200000, 0xDEAD0BAD
        .long 0x00202000, 0xDEAD0BAD
        .long 0x00300000, 0xDEAD0BAD
        .long 0x00305000, 0xDEAD0BAD
        .long 0x00400000, 0xDEAD0BAD
        .long 0x00430000, 0xDEAD0BAD
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

        ! ================== ROUND 0: five first touches ==================
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_r0_tab, r14
        mov     #5, r11
        mov     #0x50, r12
        bsr     _chk
        nop

        ! cnt_hits must have advanced by EXACTLY 5 -- five walks, five
        ! installs, no eviction and no extra walk.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        sub     r2, r1
        mov     #5, r0
        cmp/eq  r1, r0
        mov     #0x58, r9
        bf      _fail_at

        ! ============ ROUND 1: interleaved off-base reads ============
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_r1_tab, r14
        mov     #5, r11
        mov     #0x60, r12
        bsr     _chk
        nop

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x68, r9
        bf      _fail_at

        ! ============ ROUND 2: all five still resident, still distinct ====
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_r2_tab, r14
        mov     #5, r11
        mov     #0x70, r12
        bsr     _chk
        nop

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x78, r9
        bf      _fail_at

        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

        ! ---- _chk: r14 = (VA, expected) table, r11 = entry count,
        ! ---- r12 = the result code of the FIRST entry (one per entry after).
_chk:
1:      mov.l   @r14+, r0
        mov.l   @r14+, r3
        mov.l   @r0, r1                 ! <-- the access under test
        cmp/eq  r1, r3
        bf      _chk_bad
        add     #1, r12
        dt      r11
        bf      1b
        rts
        nop
_chk_bad:
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
q_r0_tab:       .long _r0_tab
q_r1_tab:       .long _r1_tab
q_r2_tab:       .long _r2_tab

        .balign 4
        ! Round 0 -- first touch, mixed size order: 16 KB, 1 MB, 4 KB, 64 KB,
        ! 4 KB. The order is deliberately not size-sorted: install order is
        ! access order under a walker-only install path.
_r0_tab:
        .long 0x00200000, 0xA1000001    ! 0x50  V1
        .long 0x00400000, 0xA3000003    ! 0x51  V3
        .long 0x00100000, 0xA0000000    ! 0x52  V0
        .long 0x00300000, 0xA2000002    ! 0x53  V2
        .long 0x00101000, 0xA0B0000B    ! 0x54  V0b
        ! Round 1 -- off-base, interleaved. Each is covered only by its own
        ! entry's page_mask at its own granularity.
_r1_tab:
        .long 0x00100100, 0xB0000100    ! 0x60  V0  + 0x100   (pm=0)
        .long 0x00202000, 0xB1002000    ! 0x61  V1  + 0x2000  (pm=1 covers it)
        .long 0x00101100, 0xB0B00100    ! 0x62  V0b + 0x100   ADJACENT 4 KB
        .long 0x00305000, 0xB2005000    ! 0x63  V2  + 0x5000  (pm=2)
        .long 0x00430000, 0xB3030000    ! 0x64  V3  + 0x30000 (pm=4)
        ! Round 2 -- the bases again, in a third order.
_r2_tab:
        .long 0x00101000, 0xA0B0000B    ! 0x70  V0b
        .long 0x00300000, 0xA2000002    ! 0x71  V2
        .long 0x00100000, 0xA0000000    ! 0x72  V0
        .long 0x00400000, 0xA3000003    ! 0x73  V3
        .long 0x00200000, 0xA1000001    ! 0x74  V1

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
        mov     #0x5F, r9               ! no access in this guard may fault
        bra     _fail_at
        nop

        .align 2
H_trip:         .long 0x000000E8

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
