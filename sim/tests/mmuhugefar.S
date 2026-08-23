! mmuhugefar.S -- Lane 2 (real linux@jcore objects) guard for contract
! obligation K7 / finding A5: A HUGE PAGE MUST BE USABLE PAST ITS FIRST
! PAGE_SIZE (16 KB), not just inside the one pte slot the huge pte occupies.
!
! See docs/mmu/pagemask-walker-contract.md §1.1, K7, A5 (in the A0 docs
! worktree). This is the case sim/tests/mmuhuge.S structurally CANNOT reach,
! and until this guard was written the defect had been reasoned about by
! three reviewers and simulated by nobody.
!
! ---------------------------------------------------------------------------
! THE DEFECT
! ---------------------------------------------------------------------------
! Linux stores a huge pte in exactly ONE pte slot:
!
!   arch/sh/mm/hugetlbpage.c  huge_pte_alloc() ends at pte_alloc_huge(mm, pmd,
!                             addr) -- the pte level;
!   arch/sh/include/asm/hugetlb.h  defines no __HAVE_ARCH_HUGE_SET_HUGE_PTE_AT,
!                             so include/asm-generic/hugetlb.h's single-slot
!                             set_pte_at() is what writes it;
!   include/linux/hugetlb.h   pte_offset_huge == pte_offset_kernel.
!
! Generic mm always aligns to huge_page_mask() before it touches a huge pte,
! so the pte lands at pte_index(huge-ALIGNED VA) and covers, as far as the
! page TABLE is concerned, exactly PAGE_SIZE (16 KB) of VA.
!
! But arch/sh/mm/tlb-jcore.c's __jcore_tlb_walk() indexes with the RAW
! faulting address. A first touch anywhere past the huge page's first 16 KB
! therefore indexes an EMPTY pte slot, returns -EFAULT, and drops into
! do_page_fault(). In a real kernel hugetlb_fault() then re-aligns, finds the
! pte already present, and returns success WITHOUT writing anything --
! update_mmu_cache() is called only when huge_ptep_set_access_flags() returns
! true (mm/hugetlb.c:6099-6101), and after the first pass the pte is already
! young -- so the access re-executes, misses again, and the loop repeats with
! no state to show for it.
!
! ---------------------------------------------------------------------------
! WHY mmuhuge.S CANNOT CATCH THIS, AND WHY THIS GUARD CAN
! ---------------------------------------------------------------------------
! mmuhuge.S touches VA_base FIRST -- installing the huge TLB entry -- and only
! then touches VA_base+0x4000, asserting (r9=4) that the walker did NOT re-run.
! It deliberately tests the RESIDENT-TLB path: the masked VPN compare of an
! already-installed huge entry. The empty-pte-slot case is unreachable from it
! by construction.
!
! This guard makes the touch past the first PAGE_SIZE the FIRST touch of the
! mapping, with the TLB flushed, so no resident entry can mask the defect.
! That is exactly the state a real kernel is in after the huge entry is
! evicted from the 16-entry DTLB (contract case B9), reached here without
! needing a >16-page eviction working set.
!
! mmuhuge.S also places its huge ptes at pte_index(VA_touched), which is NOT
! what Linux does. Every pte here is at pte_index(huge-ALIGNED VA), which is
! what huge_pte_alloc()/generic set_pte_at() actually produce.
!
! ---------------------------------------------------------------------------
! ISOLATION FROM THE A1a TAG DEFECT (contract K1) -- DELIBERATE
! ---------------------------------------------------------------------------
! Every VA this guard dereferences is 16 KB-ALIGNED, so VA[13:12] == 00 and
! `addr & PAGE_MASK` == `addr & JCORE_TSB_TAG_MASK`. The K1 tag defect (the
! kernel storing a 16 KB-granular tag against the walker's 4 KB-granular
! compare) is therefore INVISIBLE to this guard, and this guard's red/green
! state is a pure function of the K7 fix.
!
! This corrects contract case B3'-s, which specifies a first touch at
! VA_base + 0x4000 and claims it "fails for two reasons at once: the tag
! defect, and §1.1". VA_base + 0x4000 has VA[13:12] == 00, so the tag defect
! does not bite at that address at all; B3'-s as specified isolates K7, it
! does not compound it. Compounding needs an offset with VA[13:12] != 00.
! Isolation is the more useful property for a fix-verification guard, so it
! is kept and stated rather than "corrected".
!
! ---------------------------------------------------------------------------
! CONSTRUCTION (four phases, one huge mapping each)
! ---------------------------------------------------------------------------
! Per phase: MMUCR.TI (flush the TLB, so nothing is resident), write the huge
! pte at pte_index(huge-aligned VA) and NOWHERE else, enable AT, and take ONE
! load from the LAST 16 KB sub-page of the huge page. That address's own pte
! slot is zero (not present) -- as it is in a real kernel.
!
! P5 (contract §7.0): every VA dereferenced under AT=1 must itself lie in
! [0, 0x0100_0000), the cosim's backed window, because the raw untranslated VA
! is driven onto the bus during the miss. far_touch_VA is therefore
! min(VA_base + size - 0x1000, 0x00FFF000), rounded DOWN to 16 KB (see the
! isolation note above) and >= VA_base:
!
!  ph size    slot pm VA_base     far touch   PA(far)     pte index (aligned)
!  1  64 KB   1    2  0x00200000  0x0020C000  0x0010C000  0x080
!  2   1 MB   3    4  0x00400000  0x004FC000  0x005FC000  0x100
!  3  16 MB   5    6  0x00000000  0x00FFC000  0x00FFC000  0x000
!  4 256 MB   7    8  0x00000000  0x00FF8000  0x00FF8000  0x000
!
! Phases 3 and 4 are SOLO and VA == PA. A pm>=6 mapping spans at least the
! whole 16 MB backed window, so the only 16 MB-aligned VA below the window is
! 0 and it covers everything; and to keep the PA backed the PPN bits above the
! offset field must be zero, which degenerates the translation to identity
! (contract §7.1, "pm >= 6 is SOLO-ONLY"). The MMUCR.TI at the head of every
! phase is what makes solo true: phase 3's 16 MB entry would otherwise still
! be resident in phase 4 and would answer phase 4's access with the WRONG
! PageMask and no fault at all.
!
! The harness's own code, stack, pgd, pte table and TSB are all in P1, which
! seg_decode() routes untranslated, so the phase-3/4 P0 mappings cannot
! disturb them.
!
! Intermediate-size sanity, for the fix under test (which probes finest-first
! and requires the pte's OWN size slot to equal the size it probed at): every
! coarser-alignment pte index a phase's probe passes through before reaching
! its own is either zero or holds a pte with a DIFFERENT slot, so no probe can
! steal an unrelated pte. Phase 4 in particular walks straight over phase 3's
! own index 0 at s=5 and s=6 and is rejected by the slot check both times
! (phase 4 overwrote index 0 with a slot-7 pte, so the check is live).
!
! ---------------------------------------------------------------------------
! RESULT CODES (contract P1/P2; jcore-cpu CLAUDE.md "Writing a guard")
! ---------------------------------------------------------------------------
! DATA codes are (phase << 4) | check, phase 1..4, check 1..5:
!   0x?1  the load did not return the sentinel seeded at the translated PA
!         (no translation, or the wrong PA)
!   0x?2  the TSB row __jcore_tlb_walk() wrote does not carry the expected
!         PTEL image -- PPN | PageMask(pm) | V|C|U|W|D. This is what proves
!         the walker found the HUGE pte and not something else: a fix that
!         resolved the fault from a base-sized pte would land here.
!   0x?3  TSBCNT.hits moved by something other than exactly 1
!   0x?4  the walker-invocation counter moved by something other than
!         exactly 1 (strong jcore_tlb_walk_mark_accessed override below)
!   0x?5  do_page_fault() was entered during the phase (expected: never)
!   0xF0  TSBCNT.hits did not move AT ALL -- reserved anti-vacuity code
!         (contract P1). The access was resolved by software, or the counter
!         is dead; either way this guard has proved nothing.
!
! TRIP codes are 0xE0 | phase (contract §7.0 P2), i.e. 0xE1..0xE4:
!   the bounded repeat-fault counter in the do_page_fault() stub fired.
!   THIS IS THE PRE-FIX FAILURE. It must be a code, never a --stop-time
!   timeout, so that this defect cannot be conflated with a hang from any
!   other cause.
!   g_phase is initialised to 0x0F, not 0, so a fault before phase 1 reports
!   0xEF and never the reserved bare 0xE0 (which would mean the trip code was
!   computed from an uninitialised phase).
!
! Expected exact fault count: 0 (per phase and in total). Bound: 3.
! Expected exact TSBCNT.hits delta: +1 per phase.
! Expected exact walker-invocation delta: +1 per phase.
!
! Other codes:
!   0x7E  jcore_handle_exception() reached (a general exception this harness
!         never drives) -- a code rather than a silent spin, so it cannot
!         present as a timeout
!   0x7D  do_IRQ() reached
!   0x7F  _fail integrity net: r9 was 0, which sim/cpu_ctb.c's test_result()
!         would have accepted as PASS
!
! ---------------------------------------------------------------------------
! Memory map (P1 = 0x80000000 | physical offset)
! ---------------------------------------------------------------------------
!   0x00020000  PGD table        (P1 0x80020000)
!   0x00024000  PTE table        (P1 0x80024000) -- covers pgd[0]
!   0x00028000  TSB              (2 KB: TSBCFG 0x61 => 64 sets x 32 B)
!   0x00029000  scratch globals
!   0x0002A000  stack (SP near top)
!   0x0010C000 / 0x005FC000 / 0x00FFC000 / 0x00FF8000  the four sentinels
#include "sim_instr.h"
#include <asm/pgtable-bits-jcore.h>
#define ENTRY(name) .globl name; .balign 4; name:

        .section .vect,"a"
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

        .section .textlo,"ax"
ENTRY(start)
        mov.l   p_sp,    r15
        mov.l   p_kmain, r0
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x8002AF00
p_kmain: .long kmain

        .text
kmain:
        ! ---- Ensure RB=0 (keep MD=1). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        ! ---- Initialise PR (entry.S's JCORE_SAVE_REGS does `sts pr` into the
        ! pt_regs frame on the first fault; an undefined value there trips the
        ! GHDL SRAM model's undefined-write-data guard). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- Same for MACH/MACL and GBR, which JCORE_SAVE_REGS also stores.
        ! mmuhuge.S never reaches jcore_tlb_fault_entry so it only had to zero
        ! GBR; this harness DOES reach it, on purpose, so MACH/MACL matter. ----
        mov     #0, r0
        lds     r0, mach
        lds     r0, macl
        ldc     r0, gbr
        nop
        nop

        ! ---- Pre-zero the GPRs the fault handlers push on entry before
        ! defining them (same rationale as mmulinux.S/mmuhuge.S). Bank-1 r4-r7
        ! must be zeroed under RB=1 (exception entry sets SR.RB=1); r8-r14 are
        ! unbanked so one zero covers both banks. ----
        mov.l   p_rbset,  r8
        mov.l   p_rbclear, r9
        stc     sr, r0 ; or  r8, r0 ; ldc r0, sr    ! -> RB=1 (bank 1)
        nop ; nop
        mov     #0, r0 ; mov #0, r1 ; mov #0, r2 ; mov #0, r3
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7
        stc     sr, r0 ; and r9, r0 ; ldc r0, sr    ! -> RB=0 (bank 0)
        nop ; nop
        ! Bank-0 r0-r3 as well. mmuhuge.S/mmulinux.S can skip these because
        ! they never reach entry.S's jcore_tlb_fault_entry; this harness does,
        ! and JCORE_SAVE_REGS stores ALL of bank-0 r0..r7 through the r*_bank
        ! aliases. r3 in particular is not written anywhere in this harness
        ! before the first fault, and storing it undefined trips the GHDL SRAM
        ! model's invalid-write-data check -> bus exception -> stop-time
        ! timeout, i.e. a hang with no result code.
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        mov     #0, r5
        mov     #0, r6
        mov     #0, r7
        mov     #0, r8
        mov     #0, r9
        mov     #0, r10
        mov     #0, r11
        mov     #0, r12
        mov     #0, r13
        mov     #0, r14

        ! ---- ASIDR = 0 (single context; not exercised by this harness). ----
        mov     #0, r0
        ldc     r0, asidr
        nop
        nop

        ! ---- Scratch globals. g_phase starts at 0x0F so a trip code computed
        ! before phase 1 is 0xEF, never the reserved bare 0xE0. ----
        mov.l   k_wcnt, r0      ; mov #0,    r1 ; mov.l r1, @r0
        mov.l   k_faultcnt, r0  ; mov #0,    r1 ; mov.l r1, @r0
        mov.l   k_tea, r0       ; mov #0,    r1 ; mov.l r1, @r0
        mov.l   k_phase, r0     ; mov #0x0F, r1 ; mov.l r1, @r0

        ! ---- Build pgd[0] -> pte table (P1 pointer, page-aligned). ----
        mov.l   k_pgd,   r0
        mov.l   k_ptetbl, r1
        mov.l   r1, @r0

        ! ---- Zero the WHOLE TSB: TSBCFG 0x61 => v_shift 6 => 64 sets x 32 B
        ! == 2 KB == 512 words. (mmuhuge.S zeroes only 128 words and gets away
        ! with it because the cosim's anon backing is already zero.) ----
        mov.l   k_tsb,  r0
        mov.l   k_tsbwords, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed the four sentinels directly through P1 (untranslated). ----
        mov.l   k_seedp_1, r0 ; mov.l v_seed_1, r1 ; mov.l r1, @r0
        mov.l   k_seedp_2, r0 ; mov.l v_seed_2, r1 ; mov.l r1, @r0
        mov.l   k_seedp_3, r0 ; mov.l v_seed_3, r1 ; mov.l r1, @r0
        mov.l   k_seedp_4, r0 ; mov.l v_seed_4, r1 ; mov.l r1, @r0

        ! ---- Point MMU_TTB at our pgd. ----
        mov.l   k_ttb_a, r0 ; mov.l k_pgd, r1 ; mov.l r1, @r0

        ! ---- VBR = P1 alias of the REAL jcore_vbr_base (ex.o). ----
        mov.l   k_vbr, r0
        ldc     r0, vbr
        nop
        nop

        ! ---- TSB config registers via MMIO. ----
        mov.l   k_tsbbr_a,  r0 ; mov.l v_tsbbr,  r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ================= the four phases ==============================
        mov.l   k_pb1, r4 ; bsr run_phase ; nop
        mov.l   k_pb2, r4 ; bsr run_phase ; nop
        mov.l   k_pb3, r4 ; bsr run_phase ; nop
        mov.l   k_pb4, r4 ; bsr run_phase ; nop

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000        ! SR.RB bit (bank select)
k_pgd:          .long 0x80020000
k_ptetbl:       .long 0x80024000
k_tsb:          .long 0x80028000
k_tsbwords:     .long 512               ! 64 sets x 32 B / 4
k_wcnt:         .long 0x80029000
k_faultcnt:     .long 0x80029004
k_phase:        .long 0x80029008
k_tea:          .long 0x8002900C
k_ttb_a:        .long 0xFF000008        ! MMU_TTB
k_vbr:          .long jcore_vbr_base
k_tsbbr_a:      .long 0xFF000014        ! TSBBR
v_tsbbr:        .long 0x80028004
k_tsbcfg_a:     .long 0xFF000018        ! TSBCFG
v_tsbcfg:       .long 0x00000061
k_seedp_1:      .long 0x8010C000
k_seedp_2:      .long 0x805FC000
k_seedp_3:      .long 0x80FFC000
k_seedp_4:      .long 0x80FF8000
v_seed_1:       .long 0xC0FFEE64        ! 64 KB phase sentinel
v_seed_2:       .long 0xC0FFEE10        ! 1 MB
v_seed_3:       .long 0xC0FFEE16        ! 16 MB
v_seed_4:       .long 0xC0FFEE01        ! 256 MB
k_pb1:          .long pb1
k_pb2:          .long pb2
k_pb3:          .long pb3
k_pb4:          .long pb4

! ===========================================================================
! Phase parameter blocks
!
!   +0  phase number (1..4; also the low nibble of this phase's trip code)
!   +4  P1 address of the ONE pte slot to populate == k_ptetbl +
!       4*pte_index(huge-aligned VA). Nothing else in the pte table is
!       written, ever -- that is the defect's precondition.
!   +8  the Linux pte value: PFN | size-slot bits {10,12,13} | V|C|U|W|D
!       (0xB9). _PAGE_ACCESSED (0x100) is deliberately CLEAR so the walker
!       calls jcore_tlb_walk_mark_accessed() exactly once per phase.
!   +12 the VA to touch -- the last 16 KB sub-page of the huge page
!   +16 the sentinel that must come back
!   +20 the PTEL image the TSB row must carry:
!       PPN | PageMask(pm) << 8 | 0xB9. jcore_pte_to_ptel() strips the low
!       14 bits (so the size-slot AND the freshly-set _PAGE_ACCESSED vanish)
!       and substitutes jcore_pm_for_slot[slot] << 8.
! ===========================================================================
        .align 2
! ph1: 64 KB, slot 1 (0x400) -> jcore_pm_for_slot[1] == 2 -> pm=2 (0x200).
!      VA 0x00200000..0x0020FFFF -> PA 0x00100000..0x0010FFFF.
!      pte_index(0x00200000) = (0x00200000>>14)&0xFFF = 0x080 -> +0x200.
pb1:    .long 1
        .long 0x80024200
        .long 0x001004B9
        .long 0x0020C000
        .long 0xC0FFEE64
        .long 0x001002B9
! ph2: 1 MB, slot 3 (0x1400) -> pm=4 (0x400).
!      VA 0x00400000..0x004FFFFF -> PA 0x00500000..0x005FFFFF.
!      pte_index(0x00400000) = 0x100 -> +0x400.
pb2:    .long 2
        .long 0x80024400
        .long 0x005014B9
        .long 0x004FC000
        .long 0xC0FFEE10
        .long 0x005004B9
! ph3: 16 MB, slot 5 (0x2400) -> pm=6 (0x600). SOLO, VA == PA, base 0.
!      pte_index(0x00000000) = 0 -> +0x000.
pb3:    .long 3
        .long 0x80024000
        .long 0x000024B9
        .long 0x00FFC000
        .long 0xC0FFEE16
        .long 0x000006B9
! ph4: 256 MB, slot 7 (0x3400) -> pm=8 (0x800). SOLO, VA == PA, base 0.
!      At pm=8 page_offset_mask() gives n=16, so ALL of PPN[27:12] is
!      "in-page offset -> use VA" and the PTE's frame bits are inert: the PA
!      is VA & 0x0FFFFFFF whatever the pte names. Overwrites ph3's index 0.
pb4:    .long 4
        .long 0x80024000
        .long 0x000034B9
        .long 0x00FF8000
        .long 0xC0FFEE01
        .long 0x000008B9

! ===========================================================================
! run_phase(r4 = parameter block)
!
! Clobbers r0-r3, r9-r14. r14 holds the block across the fault window; every
! GPR survives a fault because entry.S's JCORE_SAVE_REGS/RESTORE_REGS_RTE
! saves and restores r0-r14 (r0-r7 through the r*_bank aliases).
! ===========================================================================
        .align 2
run_phase:
        sts.l   pr, @-r15
        mov     r4, r14

        ! ---- publish the phase for the trip code ----
        mov.l   @r14, r1
        mov.l   rp_phase, r0
        mov.l   r1, @r0

        ! ---- AT off, then MMUCR.TI (bit 2, self-clearing) to invalidate the
        ! whole TLB. This is what makes each phase SOLO: without it phase 3's
        ! 16 MB entry -- which covers the entire backed window -- would still
        ! be resident and would answer phase 4's access with the wrong
        ! PageMask and no fault, and this guard would pass vacuously via the
        ! 0xF0 path instead of testing anything. ----
        mov.l   rp_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        nop
        nop
        mov     #4, r1
        mov.l   r1, @r0
        nop
        nop

        ! ---- write the ONE huge pte, at pte_index(huge-aligned VA) ----
        mov.l   @(4, r14), r0
        mov.l   @(8, r14), r1
        mov.l   r1, @r0

        ! ---- baselines: TSBCNT.hits ([15:0]) and the walker-invocation
        ! counter. Both P4/P1 accesses, untranslated regardless of AT. ----
        mov.l   rp_tsbcnt, r0
        mov.l   @r0, r13
        extu.w  r13, r13
        mov.l   rp_wcnt, r0
        mov.l   @r0, r12

        ! ---- AT on ----
        mov.l   rp_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        nop
        nop

        ! ================= THE TOUCH =================
        ! First access to this mapping, in the LAST 16 KB sub-page of the huge
        ! page. Its own pte slot is zero. Nothing is resident in the TLB and
        ! the TSB holds no row for it, so this MUST go all the way to
        ! __jcore_tlb_walk(), which must resolve it AT THE FAULTING VA (K7).
        mov.l   @(12, r14), r0
        mov.l   @r0, r11

        ! ---- capture TSBPTR for that VA (still the last miss's set) ----
        mov.l   rp_tsbptr, r3
        mov.l   @r3, r3

        ! ---- TSBCNT.hits after ----
        mov.l   rp_tsbcnt, r0
        mov.l   @r0, r10
        extu.w  r10, r10

        ! ---- AT off for the readbacks ----
        mov.l   rp_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        nop
        nop

        ! ---- 2-way TSB: TSBPTR returns a 32-byte SET; select the way by
        ! matching tag_hi. Every VA here is 16 KB aligned, so tag_hi is the VA
        ! itself under either the old `addr & PAGE_MASK` or the canonical
        ! `addr & JCORE_TSB_TAG_MASK`. Selecting by tag_hi rather than by the
        ! PTEL the next check asserts keeps that assertion non-circular. ----
        mov.l   @(12, r14), r1
        mov.l   @r3, r2
        cmp/eq  r1, r2
        bt      1f
        add     #16, r3
1:

        ! ---- check 1: the sentinel came back ----
        mov.l   @(16, r14), r1
        cmp/eq  r1, r11
        bt      2f
        mov     #1, r9
        bra     rp_fail
        nop
2:
        ! ---- check 2: the TSB row carries the HUGE PTEL image ----
        mov.l   @(8, r3), r2
        mov.l   @(20, r14), r1
        cmp/eq  r1, r2
        bt      3f
        mov     #2, r9
        bra     rp_fail
        nop
3:
        ! ---- check 3 (contract P1, anti-vacuity): the hardware walker, not
        ! software, is what resolved the access. Exactly +1 hit. A zero delta
        ! gets the reserved 0xF0 -- it means either software resolved it or
        ! the counter is dead, and this guard would otherwise have proved
        ! nothing. Asserting an INCREASE is self-validating: a dead counter
        ! makes this fail, never pass. ----
        sub     r13, r10
        tst     r10, r10
        bf      4f
        mov.l   rp_code_f0, r9
        mov.l   rp_failp, r0
        jmp     @r0
        nop
4:      mov     #1, r1
        cmp/eq  r1, r10
        bt      5f
        mov     #3, r9
        bra     rp_fail
        nop
5:
        ! ---- check 4: __jcore_tlb_walk() ran exactly once and marked the pte
        ! accessed. Under the fix this is the walk that found the huge pte at
        ! its ALIGNED index; the counter also witnesses that the accessed bit
        ! was written back to the canonical slot. ----
        mov.l   rp_wcnt, r0
        mov.l   @r0, r1
        sub     r12, r1
        mov     #1, r2
        cmp/eq  r2, r1
        bt      6f
        mov     #4, r9
        bra     rp_fail
        nop
6:
        ! ---- check 5: do_page_fault() was never entered ----
        mov.l   rp_faultcnt, r0
        mov.l   @r0, r1
        tst     r1, r1
        bt      7f
        mov     #5, r9
        bra     rp_fail
        nop
7:
        lds.l   @r15+, pr
        rts
        nop

! Data failure code = (phase << 4) | r9, so phase and check are both legible
! in the single word test_result() prints.
rp_fail:
        mov.l   @r14, r1
        shll2   r1
        shll2   r1
        or      r1, r9
        mov.l   rp_failp, r0
        jmp     @r0
        nop

        .align 2
rp_phase:       .long 0x80029008        ! == k_phase
rp_wcnt:        .long 0x80029000        ! == k_wcnt
rp_faultcnt:    .long 0x80029004        ! == k_faultcnt
rp_mmucr:       .long 0xFF000010        ! MMUCR (bit0 AT, bit2 TI)
rp_tsbptr:      .long 0xFF00001C        ! read-only P4 TSBPTR alias
rp_tsbcnt:      .long 0xFF000054        ! [31:16]=cnt_walks [15:0]=cnt_hits
rp_code_f0:     .long 0x000000F0
rp_failp:       .long _fail

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

! ===========================================================================
! Stub set for the three real linux@jcore objects' cross-object undefined
! symbols (as in mmulinux.S / mmuhuge.S -- same real link, same needs).
! ===========================================================================

! do_page_fault(regs, error_code, address) -- reached ONLY when
! __jcore_tlb_walk() returned -EFAULT.  Unlike mmuhuge.S's stub, this one
! RETURNS, so entry.S's JCORE_RESTORE_REGS_RTE runs and the faulting access
! re-executes. That models a real kernel faithfully: for a huge mapping
! hugetlb_fault() re-aligns, finds the pte already present, and returns
! success without writing anything (update_mmu_cache() is skipped once the
! pte is young, mm/hugetlb.c:6099-6101), so the access simply retries.
!
! That is an UNBOUNDED loop, which would present as a --stop-time timeout --
! ruled out as a failure signal by CLAUDE.md's "Writing a guard". Hence the
! bound: after DPF_BOUND entries, write this phase's trip code (0xE0 | phase)
! and spin. Expected entries: 0. Bound: 3.
DPF_BOUND = 3
ENTRY(do_page_fault)
        mov.l   dpf_tea, r0
        mov.l   r6, @r0                 ! record the faulting address
        mov.l   dpf_faultcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov     #DPF_BOUND, r2
        cmp/gt  r2, r1                  ! T = (count > DPF_BOUND)
        bt      1f
        rts
        nop
1:      mov.l   dpf_phase, r0
        mov.l   @r0, r1
        mov.l   dpf_e0, r2
        or      r2, r1
        mov.l   dpf_result, r0
        mov.l   r1, @r0
2:      bra     2b
        nop
        .align 2
dpf_faultcnt:   .long 0x80029004        ! == k_faultcnt
dpf_tea:        .long 0x8002900C        ! == k_tea
dpf_phase:      .long 0x80029008        ! == k_phase
dpf_e0:         .long 0x000000E0
dpf_result:     .long TEST_RESULT_ADDRESS

! exception_handler -- generic (non-TLB) exception dispatch; never taken.
ENTRY(exception_handler)
        rts
        nop

! jcore_handle_exception(regs, expevt) / do_IRQ(irq, regs) -- referenced by
! entry.o. This harness drives neither. Reaching one means a fault took a
! vector this harness did not expect: report a distinct code rather than
! spinning, so it cannot present as a timeout.
ENTRY(jcore_handle_exception)
        mov.l   jhe_result, r0
        mov     #0x7E, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
jhe_result:     .long TEST_RESULT_ADDRESS
ENTRY(do_IRQ)
        mov.l   irq_result, r0
        mov     #0x7D, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
irq_result:     .long TEST_RESULT_ADDRESS

ENTRY(arch_local_irq_restore)
        rts
        nop
ENTRY(arch_local_save_flags)
        mov     #0, r0
        rts
        nop

! memset(s, c, n) / jcore_boot_tsb -- link-only stubs for tlb-jcore.o's
! jcore_tsb_flush_on_generation(); never actually invoked here.
ENTRY(memset)
        mov     r4, r3
1:      tst     r6, r6
        bt      2f
        mov.b   r5, @r4
        add     #1, r4
        add     #-1, r6
        bra     1b
        nop
2:      mov     r3, r0
        rts
        nop

        .bss
        .balign 16
        .globl  jcore_boot_tsb
        .type   jcore_boot_tsb, @object
        .size   jcore_boot_tsb, 4096
jcore_boot_tsb:
        .skip   4096
        .text

! jcore_tlb_walk_mark_accessed(pte_t *ptep, pte_t entry) -- STRONG definition
! shadowing tlb-jcore.o's __weak default (mmuhugefar.o links first, see
! sim/tests/Makefile) so this harness gets an unambiguous walker-invocation
! counter: __jcore_tlb_walk() calls it exactly when it finds a pte with
! _PAGE_ACCESSED clear, which every phase's fresh huge pte is.
! r4 = ptep, r5 = entry (32-bit scalar pte_t, non-PAE).
ENTRY(jcore_tlb_walk_mark_accessed)
        mov.l   p_wcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   r5, @r4                 ! set_pte(ptep, entry)
        rts
        nop
        .align 2
p_wcnt: .long 0x80029000                ! == k_wcnt (duplicated locally:
                                        ! mov.l is PC-relative-forward-only)
