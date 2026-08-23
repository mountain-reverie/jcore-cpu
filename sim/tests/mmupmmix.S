! mmupmmix.S -- Group-B case B4 of the TSB PageMask / tag-granularity contract
! (docs/mmu/pagemask-walker-contract.md §7.1, hardware-spec.md §7.0a,
! linux-spec.md §4.3a): FOUR page sizes simultaneously resident in ONE ASID,
! every one of them first touched at a non-base 4 KB sub-page, then
! interleaved.
!
! LANE 2: links the REAL linux@jcore objects (arch/sh/mm/tlb-jcore.o,
! arch/sh/kernel/cpu/jcore/{ex,entry}.o), so every TSB row under test is
! written by the REAL __jcore_tlb_walk(). Run by sim/linux_sim.sh and by
! .github/workflows/full-regression.yml, NOT by sim/mmu_sim.sh.
!
! The 4 KB (pm=0) arm of the simultaneous-residency requirement is NOT here:
! no correct Linux build can emit pm=0 (jcore_pm_for_slot[] starts at 1, and
! the pte layout hardwires PAGE_SHIFT=14 -- obligation K3), so it is covered
! against the HARDWARE contract by the Lane-1 case C7g instead. See the
! contract's §7.4 coverage argument for why the split is deliberate.
!
! ---------------------------------------------------------------------------
! CONSTRUCTION
! ---------------------------------------------------------------------------
!   M0   16 KB  slot 0 -> pm=1   VA 0x00400000 -> PA 0x00A00000
!   M1   64 KB  slot 1 -> pm=2   VA 0x00500000 -> PA 0x00B00000
!   M2  256 KB  slot 2 -> pm=3   VA 0x00600000 -> PA 0x00C00000
!   M3    1 MB  slot 3 -> pm=4   VA 0x00700000 -> PA 0x00D00000
!
! DISJOINT VA REGIONS ARE LOAD-BEARING, not tidiness. core/tlb.vhd's
! install-time dedup (:355-365) picks a resident entry to REPLACE IN PLACE
! whenever the new VPN matches it under `vpn_compare_mask(resident.page_mask)
! AND vpn_compare_mask(new.page_mask)` -- the intersection of the two masks,
! i.e. the COARSER page's compare. Putting the 16 KB page inside the 1 MB
! page's range would therefore make them evict each other, and the case would
! silently degrade into testing one entry at a time. Each mapping lives in its
! own 1 MB VA region, the coarsest granularity in play.
!
! WHY 1 MB IS THE LARGEST SIZE HERE AND NOT THE CONTRACT'S 16 MB. The contract
! (§7.1 B4) names 16 K / 64 K / 1 M / 16 M. A 16 MB page cannot take part in a
! simultaneous-residency case under this cosim, for a harness reason rather
! than a hardware one:
!
!   Every VA a guard translates must ITSELF be a backed physical address.
!   While a translated load's TLB miss is being walked, the core keeps the
!   request asserted and only withholds the ack, so the access reaches the
!   uncached bypass, "which would read the raw untranslated VA off the bus"
!   (core/cpu.vhd, the mmu_o.i_hit comment). sim/cpu_ctb.c backs only
!   [image_size, 0x1000000) -- 16 MB -- so a VA at or above 16 MB makes
!   sim/mem_bus.c report `SRAM: invalid read addr` and raise a Bus exception,
!   and the guard wedges before it ever faults. MEASURED, not assumed: VA
!   0x01802000 bus-errors here, where VA 0x00F02000 under the identical
!   mapping translates correctly.
!
! Four mappings that must be disjoint at 16 MB granularity cannot all fit
! below 16 MB, so 1 MB is the coarsest size a four-way simultaneous-residency
! case can carry. 256 KB takes 16 MB's place, which keeps FOUR DISTINCT
! PageMask values (pm = 1, 2, 3, 4) live at once -- what the case is actually
! for. The 16 MB and 256 MB sizes are exercised singly by sim/tests/mmuhuge.S,
! and per-size by the contract's B3-s (task A1c).
!
! Phase 1  first touch of each mapping, at +0x1000/+0x2000/+0x3000/+0x1000 --
!          all non-base 4 KB sub-pages, all INSIDE the first 16 KB so they
!          index the mapping's one populated pte slot. That isolates the tag
!          defect from the separate huge-pte-slot defect of contract §1.1
!          (which is task A1b, not A1a).
! Phase 2  8 interleaved rounds M0,M1,M2,M3 on distinct 4 KB sub-pages; for
!          M1/M2/M3 the offsets cross 16 KB (pte-slot) boundaries, so they are
!          reachable ONLY through the installed entry's widened page-mask
!          compare and never through a pte lookup.
! Phase 3  re-read the four phase-1 addresses.
!
! Every touched physical word is seeded with 0xB1000000 + PA. That is strictly
! stronger than the contract's "a distinct sentinel per mapping": it catches a
! read that returned another mapping's data AND a read that returned the right
! mapping at the wrong offset.
!
! ---------------------------------------------------------------------------
! WHAT MAKES IT NON-VACUOUS (contract §7.0 P1/P2)
! ---------------------------------------------------------------------------
! P2: VBR points at this harness's own vector page; the +0x400 shim counts
! faults and reports 0xE0|phase past FAULT_BOUND before jumping to the real
! jcore_tlb_miss. Pre-fix the very first touch livelocks, and without this the
! only symptom would be a --stop-time timeout, which jcore-cpu CLAUDE.md rules
! out as a failure signal. Expected total faults: 4. FAULT_BOUND: 10.
! (0xE0|phase rather than the contract's flat 0xFE -- see mmupmsub4k.S.)
!
! Phases must stay <= 15: 0xE0|16 is 0xF0, the reserved P1 code below.
!
! P1: each phase-1 touch must move cnt_hits (P4_TSBCNT [15:0]) by EXACTLY 1,
! and phases 2 and 3 must move it by ZERO -- the four entries stay resident in
! the 16-entry DTLB and every later access is a plain TLB hit. Zero hits in
! phase 1 means software resolved the access and the case proved nothing
! (0xF0). A NON-zero delta in phase 2/3 would mean an entry was evicted or
! never really covered its whole page.
!
! Finally cnt_walks - cnt_hits over the whole guard must be <= 4: one
! unresolved (software) walk per mapping and no more.
!
! MULTI_HIT, protection faults and illegal instructions all vector to
! VBR+0x100, which this harness turns into result 0xF1 -- so the contract's
! "no MULTI_HIT ever" is a named failure here, not a hang.
!
! ---------------------------------------------------------------------------
! Memory map (P1 = 0x80000000 | physical)
! ---------------------------------------------------------------------------
!   0x00020000  PGD table       (16 KB, P1 0x80020000)
!   0x00024000  PTE table       (16 KB, P1 0x80024000) -- covers pgd[0]
!   0x00028000  TSB             (512 B, P1 0x80028000, TSB_SIZE_LOG=4)
!   0x00029000  scratch globals
!   0x0002A000  stack           (P1 0x8002AF00)
!   0x00A00000..0x00DE3FFF   the four mappings' physical windows (disjoint)
!
! ---------------------------------------------------------------------------
! Result codes (printed by sim/cpu_ctb.c as unsigned DECIMAL)
! ---------------------------------------------------------------------------
!   0x10..0x13 (16..19) phase 1, mapping M0..M3: the non-base sub-page load
!                       did not return 0xB1000000 + its own PA
!   0x14..0x17 (20..23) phase 1, M0..M3: TLB-miss fault count != 1
!   0x18..0x1B (24..27) phase 1, M0..M3: cnt_hits delta != 1 (but != 0)
!   0x20+n     (32..63) phase 2, interleave row n (0..31): wrong value --
!                       cross-size mistranslation
!   0x40..0x43 (64..67) phase 3, M0..M3: wrong value on the final re-read
!   0x50       (80)     phase 2 took a TLB-miss fault (an entry did not stay
!                       resident, or did not cover its whole page)
!   0x51       (81)     phase 3 took a TLB-miss fault
!   0x52       (82)     phase 2+3 moved cnt_hits -- the walker re-resolved
!                       something that should have been a plain TLB hit
!   0x53       (83)     total TLB-miss faults over the guard != 4
!   0x54       (84)     cnt_walks - cnt_hits over the guard > 4
!   0xE5..0xEA (229..234) P2: repeat-fault bound exceeded in phase 5..10
!                       (5..8 = first touch of M0..M3, 9 = interleave,
!                       10 = final re-read). THIS IS THE PRE-FIX FAILURE.
!   0xF0       (240)    P1: cnt_hits did not move on a phase-1 touch
!   0xF1       (241)    unexpected general exception at VBR+0x100 -- this is
!                       where a MULTI_HIT lands
!   0xF2       (242)    unexpected interrupt at VBR+0x600
!   0xF3       (243)    do_page_fault() reached (every pte here is present)
!   0xFE       (254)    P2 bound exceeded with phase == 0
!   0x7F       (127)    _fail integrity net (a fail code of 0 names nothing)
!
! ---------------------------------------------------------------------------
! MUTATION RECORD (contract §7.0 P4) -- measured, not asserted
! ---------------------------------------------------------------------------
!   the defect itself: revert arch/sh/mm/tlb-jcore.c to `addr & PAGE_MASK`
!                      -> FAIL Result=229 (0xE5), M0's first touch livelocks
!   the data assertion: interleave row n=6's PA 0x00C09000 -> 0x00C0A000
!                      -> FAIL Result=38 (0x26), naming that exact row
!   unmutated          -> Test Passed

#include "sim_instr.h"
#include <asm/pgtable-bits-jcore.h>
#define ENTRY(name) .globl name; .balign 4; name:

! ---- Page-table / TSB layout, and the pte flag word. Size-slot bits are pte
! ---- {10,12,13} (_PAGE_JCORE_SZ_BITS); slot -> PageMask via
! ---- jcore_pm_for_slot[] = {1,2,3,4,5,6,7,8}. D is set so jcore_pte_to_ptel()
! ---- does not take its clean-page W-withholding arm.
#define PGD_TBL   0x80020000
#define PTE_TBL   0x80024000
#define TSB_BASE  0x80028000
#define PTE_FLAGS 0xB9                  /* V|C|D|U|W                     */
#define SZ_SLOT0  0x0000                /* -> pm=1,  16 KB               */
#define SZ_SLOT1  0x0400                /* bit10      -> pm=2,  64 KB    */
#define SZ_SLOT2  0x1000                /* bit12      -> pm=3, 256 KB    */
#define SZ_SLOT3  0x1400                /* bits10,12  -> pm=4,   1 MB    */

! ---- Scratch globals. `mov.l @(disp,PC)` reaches FORWARDS only, so several
! ---- literal pools in this file each need their own copy of these addresses;
! ---- naming them here is what stops those copies drifting apart.
! ----
! ---- K_SCRATCH_WORDS must cover EVERY global below. It read 8 and the last
! ---- global is word 8 (K_G_C0), so K_G_C0 was outside the range the boot
! ---- loop zeroes while a comment two lines away claimed it was zeroed. Safe
! ---- only because K_G_F0/K_G_C0 are both written before any read -- the next
! ---- person to add a word would have inherited uninitialised memory.
#define K_SCRATCH       0x80029000
#define K_SCRATCH_WORDS 12              /* zeroes K_SCRATCH .. K_SCRATCH+0x2C */
#define K_FAULTCNT      0x80029004      /* do_page_fault() count              */
#define K_TLBFAULTS     0x80029014      /* P2 bounded repeat-fault counter    */
#define K_PHASE         0x80029018      /* phase id, named by the P2 trip     */
#define K_G_F0          0x8002901C      /* whole-guard fault baseline         */
#define K_G_C0          0x80029020      /* whole-guard P4_TSBCNT baseline     */

! ---- The workload: four mappings, four DISTINCT PageMask values, live at
! ---- once. Each lives in its own 1 MB VA region -- the coarsest granularity
! ---- in play -- so core/tlb.vhd's install-time dedup cannot make one evict
! ---- another. P1() is the untranslated kernel alias used to seed by PHYSICAL
! ---- address.
#define P1(x)     ((x) | 0x80000000)
#define VA_M0     0x00400000
#define PA_M0     0x00A00000
#define VA_M1     0x00500000
#define PA_M1     0x00B00000
#define VA_M2     0x00600000
#define PA_M2     0x00C00000
#define VA_M3     0x00700000
#define PA_M3     0x00D00000

! Bounded repeat-fault limit (contract §7.0 P2). Expected total is 4.
#define FAULT_BOUND 10

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

! ===========================================================================
! Harness vector page -- see mmupmsub4k.S's header for the full rationale.
! ===========================================================================
        .balign 0x100
ENTRY(harness_vbr_base)
0:      bra     0b
        nop

        .org    harness_vbr_base + 0x100
        ! MULTI_HIT, protection, illegal, TRAPA. None is expected here.
        mov.l   g_res, r0
        mov.l   g_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
g_res:  .long TEST_RESULT_ADDRESS
g_code: .long 0x000000F1

        .org    harness_vbr_base + 0x400
        mov.l   t_cnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov     #FAULT_BOUND, r2
        cmp/hi  r2, r1
        bt      9f
        mov.l   t_real, r0
        jmp     @r0                     ! jcore_tlb_miss
        nop
9:      mov.l   t_phase, r0
        mov.l   @r0, r1
        tst     r1, r1
        bt      6f
        mov.l   t_e0, r2
        or      r2, r1
        bra     8f
        nop
6:      mov.l   t_fe, r1
8:      mov.l   t_res, r0
        mov.l   r1, @r0
7:      bra     7b
        nop
        .align 2
t_cnt:   .long K_TLBFAULTS
t_phase: .long K_PHASE
t_real:  .long jcore_tlb_miss
t_e0:    .long 0x000000E0
t_fe:    .long 0x000000FE
t_res:   .long TEST_RESULT_ADDRESS

        .org    harness_vbr_base + 0x600
        mov.l   i_res, r0
        mov.l   i_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
i_res:  .long TEST_RESULT_ADDRESS
i_code: .long 0x000000F2

        .org    harness_vbr_base + 0x700

! ===========================================================================
kmain:
        ! ---- RB=0 (core/cpu.vhd gates walk_req on dp_sr.rb = '0'). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        mov     #0, r0
        lds     r0, pr

        ! ---- Pre-zero the GPRs the fault handlers push, in BOTH banks. ----
        mov.l   p_rbset,  r8
        mov.l   p_rbclear, r9
        stc     sr, r0 ; or  r8, r0 ; ldc r0, sr
        nop ; nop
        mov     #0, r0 ; mov #0, r1 ; mov #0, r2 ; mov #0, r3
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7
        stc     sr, r0 ; and r9, r0 ; ldc r0, sr
        nop ; nop
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

        ! ---- ONE ASID for the whole guard (the contract's B4 is explicitly
        ! ---- single-ASID; cross-ASID behaviour is case B8). ----
        mov     #0, r0
        ldc     r0, asidr
        nop
        nop
        mov     #0, r0
        ldc     r0, gbr
        nop
        nop

        ! ---- Zero the scratch globals. ----
        mov.l   k_scratch, r0
        mov     #K_SCRATCH_WORDS, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- pgd[0] -> pte table, then the four ptes. ----
        mov.l   k_pgd,   r0
        mov.l   k_ptetbl, r1
        mov.l   r1, @r0
        mov.l   k_pte_m0, r0 ; mov.l v_pte_m0, r1 ; mov.l r1, @r0
        mov.l   k_pte_m1, r0 ; mov.l v_pte_m1, r1 ; mov.l r1, @r0
        mov.l   k_pte_m2, r0 ; mov.l v_pte_m2, r1 ; mov.l r1, @r0
        mov.l   k_pte_m3, r0 ; mov.l v_pte_m3, r1 ; mov.l r1, @r0

        ! ---- Zero the TSB (16 sets x 32 bytes => 128 words). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        shll    r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed every touched physical word with 0xB1000000 + PA, written
        ! ---- through its P1 alias while AT is still off. ----
        mov.l   k_tab,     r14
        mov.l   k_tab_end, r13
        mov.l   k_p1_base, r12          ! 0x80000000
        mov.l   k_sent_base, r11        ! 0xB1000000
1:      mov.l   @r14+, r0               ! VA (unused while seeding)
        mov.l   @r14+, r1               ! PA
        mov     r1, r2
        or      r12, r2                 ! P1 alias of PA
        add     r11, r1                 ! 0xB1000000 + PA
        mov.l   r1, @r2
        cmp/hs  r13, r14
        bf      1b

        ! ---- MMU_TTB -> our pgd; VBR -> the harness vector page. ----
        mov.l   k_ttb_a, r0 ; mov.l k_pgd, r1 ; mov.l r1, @r0
        mov.l   k_vbr, r0
        ldc     r0, vbr
        nop
        nop

        ! ---- TSB config, then enable AT. ----
        mov.l   k_tsbbr_a,  r0 ; mov.l v_tsbbr,  r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0
        nop
        nop

        ! ---- Whole-guard baselines (used by the 0x53 / 0x54 checks). ----
        mov.l   k_tlbfaults, r0
        mov.l   @r0, r0
        mov.l   k_g_f0, r1
        mov.l   r0, @r1
        mov.l   k_walkcnt, r0
        mov.l   @r0, r0
        mov.l   k_g_c0, r1
        mov.l   r0, @r1

        ! `mov.l @(disp,PC)` reaches only FORWARDS and only +1020 bytes, so
        ! kmain's literal pool has to sit here, between the setup and phase 1,
        ! rather than at the end of the file. Branch over it.
        bra     _p1
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000
k_pgd:          .long PGD_TBL
k_ptetbl:       .long PTE_TBL
k_tsb:          .long TSB_BASE
k_scratch:      .long K_SCRATCH
k_tlbfaults:    .long K_TLBFAULTS
k_g_f0:         .long K_G_F0
k_g_c0:         .long K_G_C0
k_walkcnt:      .long 0xFF000054
k_ttb_a:        .long 0xFF000008
k_vbr:          .long harness_vbr_base
k_tsbbr_a:      .long 0xFF000014
v_tsbbr:        .long TSB_BASE | 4     ! TSB_SIZE_LOG=4 -> 16 sets
k_tsbcfg_a:     .long 0xFF000018
v_tsbcfg:       .long 0x00000061
k_mmucr:        .long 0xFF000010
k_p1_base:      .long P1(0)
k_sent_base:    .long 0xB1000000
k_tab:          .long _tab
k_tab_end:      .long _tab_end

! ---- The four ptes, addressed the way the walker indexes them: pte_index =
! ---- (VA >> 14) & 0xFFF, and pgd_index = VA >> 26 == 0 for all four, so one
! ---- pte table under pgd[0] covers them. Computing the index from the VA
! ---- rather than hardcoding it means a VA edit cannot leave a pte behind at
! ---- a stale slot.
k_pte_m0:       .long PTE_TBL + ((VA_M0 >> 14) & 0xFFF) * 4
v_pte_m0:       .long PA_M0 | SZ_SLOT0 | PTE_FLAGS
k_pte_m1:       .long PTE_TBL + ((VA_M1 >> 14) & 0xFFF) * 4
v_pte_m1:       .long PA_M1 | SZ_SLOT1 | PTE_FLAGS
k_pte_m2:       .long PTE_TBL + ((VA_M2 >> 14) & 0xFFF) * 4
v_pte_m2:       .long PA_M2 | SZ_SLOT2 | PTE_FLAGS
k_pte_m3:       .long PTE_TBL + ((VA_M3 >> 14) & 0xFFF) * 4
v_pte_m3:       .long PA_M3 | SZ_SLOT3 | PTE_FLAGS

! ======================= PHASE 1: the four first touches ===================
_p1:
        mov.l   s_tab,       r14
        mov.l   s_tab_inter, r13
        mov     #0, r10                 ! mapping index 0..3
_p1_loop:
        ! phase id = 5 + index, so a bound trip reports 0xE5..0xE8
        mov.l   s_phase, r0
        mov     r10, r1
        add     #5, r1
        mov.l   r1, @r0

        mov.l   s_tlbfaults, r0
        mov.l   @r0, r8                 ! f0
        mov.l   s_walkcnt, r0
        mov.l   @r0, r7
        extu.w  r7, r7                  ! hits0

        mov.l   @r14+, r1               ! VA
        mov.l   @r14+, r2               ! PA
        mov.l   s_sent_base, r0
        add     r0, r2                  ! expected value

        ! ---- THE FIRST TOUCH, at a non-base 4 KB sub-page. ----
        mov.l   @r1, r5

        mov.l   s_tlbfaults, r0
        mov.l   @r0, r6
        sub     r8, r6                  ! fault delta
        mov.l   s_walkcnt, r0
        mov.l   @r0, r4
        extu.w  r4, r4
        sub     r7, r4                  ! cnt_hits delta

        cmp/eq  r2, r5
        bt      1f
        mov     r10, r9
        add     #0x10, r9               ! 0x10..0x13
        bra     _fail
        nop
1:      mov     #1, r0
        cmp/eq  r0, r6
        bt      2f
        mov     r10, r9
        add     #0x14, r9               ! 0x14..0x17
        bra     _fail
        nop
2:      tst     r4, r4
        bf      3f
        mov.l   s_f0code, r9            ! 0xF0: software resolved it, not the
        bra     _fail                   ! walker -- the case would be vacuous
        nop
3:      mov     #1, r0
        cmp/eq  r0, r4
        bt      4f
        mov     r10, r9
        add     #0x18, r9               ! 0x18..0x1B
        bra     _fail
        nop
4:      add     #1, r10
        cmp/hs  r13, r14
        bt      _p2
        bra     _p1_loop
        nop

        .align 2
s_phase:      .long K_PHASE
s_tlbfaults:  .long K_TLBFAULTS
s_walkcnt:    .long 0xFF000054          ! [31:16]=cnt_walks [15:0]=cnt_hits
s_sent_base:  .long 0xB1000000
s_f0code:     .long 0x000000F0
s_tab:        .long _tab
s_tab_inter:  .long _tab_inter

! ============ PHASE 2: 8 interleaved rounds, zero further faults ===========
_p2:
        mov.l   u_phase, r0
        mov     #9, r1
        mov.l   r1, @r0

        mov.l   u_tlbfaults, r0
        mov.l   @r0, r8                 ! f0 for phases 2+3
        mov.l   u_walkcnt, r0
        mov.l   @r0, r7
        extu.w  r7, r7                  ! hits0 for phases 2+3

        mov.l   u_tab_inter, r14
        mov.l   u_tab_end,   r13
        mov     #0, r10                 ! interleave row index
_p2_loop:
        mov.l   @r14+, r1               ! VA
        mov.l   @r14+, r2               ! PA
        mov.l   u_sent_base, r0
        add     r0, r2
        mov.l   @r1, r5
        cmp/eq  r2, r5
        bt      1f
        mov     r10, r9
        add     #0x20, r9               ! 0x20 + row
        bra     _fail
        nop
1:      add     #1, r10
        cmp/hs  r13, r14
        bt      _p2_done
        bra     _p2_loop
        nop
_p2_done:
        mov.l   u_tlbfaults, r0
        mov.l   @r0, r6
        sub     r8, r6
        tst     r6, r6
        bt      2f
        mov     #0x50, r9               ! phase 2 faulted: an entry did not
        bra     _fail                   ! stay resident / did not cover its page
        nop
2:

! ================== PHASE 3: re-read the four first-touch VAs =============
        mov.l   u_phase, r0
        mov     #10, r1
        mov.l   r1, @r0

        mov.l   u_tab,       r14
        mov.l   u_tab_inter, r13
        mov     #0, r10
_p3_loop:
        mov.l   @r14+, r1
        mov.l   @r14+, r2
        mov.l   u_sent_base, r0
        add     r0, r2
        mov.l   @r1, r5
        cmp/eq  r2, r5
        bt      1f
        mov     r10, r9
        add     #0x40, r9               ! 0x40..0x43
        bra     _fail
        nop
1:      add     #1, r10
        cmp/hs  r13, r14
        bt      _p3_done
        bra     _p3_loop
        nop
_p3_done:
        ! ---- The four final reads must take NO additional fault at all
        ! ---- (contract B4: the four TLB entries coexist). ----
        mov.l   u_tlbfaults, r0
        mov.l   @r0, r6
        sub     r8, r6
        tst     r6, r6
        bt      2f
        mov     #0x51, r9
        bra     _fail
        nop
2:      ! ---- ...and must not have moved cnt_hits either: a walk hit here
        ! ---- would mean the entry had been evicted and re-installed. ----
        mov.l   u_walkcnt, r0
        mov.l   @r0, r4
        extu.w  r4, r4
        sub     r7, r4
        tst     r4, r4
        bt      3f
        mov     #0x52, r9
        bra     _fail
        nop
3:      ! `mov.l @(disp,PC)` reaches forwards only, so phases 2/3 need their
        ! literal pool HERE. Branch over it -- falling through would execute
        ! the .long words as instructions.
        bra     _totals
        nop

        .align 2
u_phase:      .long K_PHASE
u_tlbfaults:  .long K_TLBFAULTS
u_walkcnt:    .long 0xFF000054
u_sent_base:  .long 0xB1000000
u_tab:        .long _tab
u_tab_inter:  .long _tab_inter
u_tab_end:    .long _tab_end

! ============================ whole-guard totals ==========================
_totals:
        mov.l   w_tlbfaults, r0
        mov.l   @r0, r1
        mov.l   w_g_f0, r0
        mov.l   @r0, r0
        sub     r0, r1                  ! total TLB-miss faults
        mov     #4, r0
        cmp/eq  r0, r1
        bt      1f
        mov     #0x53, r9
        bra     _fail
        nop
1:      ! cnt_walks - cnt_hits over the whole guard must be <= 4: one
        ! software-resolved walk per mapping and no more.
        mov.l   w_walkcnt, r0
        mov.l   @r0, r1
        mov.l   w_g_c0, r0
        mov.l   @r0, r0
        mov     r1, r2
        shlr16  r2                      ! walks now
        mov     r0, r3
        shlr16  r3                      ! walks then
        sub     r3, r2                  ! walks delta
        extu.w  r1, r1
        extu.w  r0, r0
        sub     r0, r1                  ! hits delta
        sub     r1, r2                  ! walks - hits
        mov     #4, r0
        cmp/hi  r0, r2                  ! (walks-hits) > 4 ?
        bf      2f
        mov     #0x54, r9
        bra     _fail
        nop
2:
        mov     #0, r9
        bra     _done
        nop

        .align 2
w_tlbfaults:  .long K_TLBFAULTS
w_walkcnt:    .long 0xFF000054
w_g_f0:       .long K_G_F0
w_g_c0:       .long K_G_C0

        .balign 4
_tab:
        ! VA                 PA
        ! ---- first touches: one per mapping, each at a NON-BASE 4 KB
        ! ---- sub-page INSIDE the first 16 KB (so the same pte slot --
        ! ---- this case isolates the tag defect from the huge-pte-slot
        ! ---- defect of contract §1.1, which is task A1b, not A1a).
        .long VA_M0 + 0x01000,   PA_M0 + 0x01000    ! M0  16 KB pm=1
        .long VA_M1 + 0x02000,   PA_M1 + 0x02000    ! M1  64 KB pm=2
        .long VA_M2 + 0x03000,   PA_M2 + 0x03000    ! M2  256 KB pm=3
        .long VA_M3 + 0x01000,   PA_M3 + 0x01000    ! M3  1 MB pm=4
_tab_inter:
        ! ---- 8 interleaved rounds over M0..M3. Offsets land on distinct
        ! ---- 4 KB sub-pages, and for M1/M2/M3 they cross 16 KB (pte-slot)
        ! ---- boundaries -- reachable only through the installed entry's
        ! ---- widened page-mask compare, never through a pte lookup.
        ! round 0
        .long VA_M0 + 0x01000,   PA_M0 + 0x01000    ! n= 0
        .long VA_M1 + 0x01000,   PA_M1 + 0x01000    ! n= 1
        .long VA_M2 + 0x01000,   PA_M2 + 0x01000    ! n= 2
        .long VA_M3 + 0x02000,   PA_M3 + 0x02000    ! n= 3
        ! round 1
        .long VA_M0 + 0x02000,   PA_M0 + 0x02000    ! n= 4
        .long VA_M1 + 0x03000,   PA_M1 + 0x03000    ! n= 5
        .long VA_M2 + 0x09000,   PA_M2 + 0x09000    ! n= 6
        .long VA_M3 + 0x22000,   PA_M3 + 0x22000    ! n= 7
        ! round 2
        .long VA_M0 + 0x03000,   PA_M0 + 0x03000    ! n= 8
        .long VA_M1 + 0x05000,   PA_M1 + 0x05000    ! n= 9
        .long VA_M2 + 0x11000,   PA_M2 + 0x11000    ! n=10
        .long VA_M3 + 0x42000,   PA_M3 + 0x42000    ! n=11
        ! round 3
        .long VA_M0,             PA_M0              ! n=12
        .long VA_M1 + 0x07000,   PA_M1 + 0x07000    ! n=13
        .long VA_M2 + 0x19000,   PA_M2 + 0x19000    ! n=14
        .long VA_M3 + 0x62000,   PA_M3 + 0x62000    ! n=15
        ! round 4
        .long VA_M0 + 0x01000,   PA_M0 + 0x01000    ! n=16
        .long VA_M1 + 0x09000,   PA_M1 + 0x09000    ! n=17
        .long VA_M2 + 0x21000,   PA_M2 + 0x21000    ! n=18
        .long VA_M3 + 0x82000,   PA_M3 + 0x82000    ! n=19
        ! round 5
        .long VA_M0 + 0x02000,   PA_M0 + 0x02000    ! n=20
        .long VA_M1 + 0x0B000,   PA_M1 + 0x0B000    ! n=21
        .long VA_M2 + 0x29000,   PA_M2 + 0x29000    ! n=22
        .long VA_M3 + 0xA2000,   PA_M3 + 0xA2000    ! n=23
        ! round 6
        .long VA_M0 + 0x03000,   PA_M0 + 0x03000    ! n=24
        .long VA_M1 + 0x0D000,   PA_M1 + 0x0D000    ! n=25
        .long VA_M2 + 0x31000,   PA_M2 + 0x31000    ! n=26
        .long VA_M3 + 0xC2000,   PA_M3 + 0xC2000    ! n=27
        ! round 7
        .long VA_M0,             PA_M0              ! n=28
        .long VA_M1 + 0x0F000,   PA_M1 + 0x0F000    ! n=29
        .long VA_M2 + 0x39000,   PA_M2 + 0x39000    ! n=30
        .long VA_M3 + 0xE2000,   PA_M3 + 0xE2000    ! n=31
_tab_end:

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
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

! ===========================================================================
! Stub set for the real linux@jcore objects' cross-object undefined symbols
! (same set as sim/tests/mmuhuge.S).
! ===========================================================================
ENTRY(do_page_fault)
        mov.l   dpf_faultcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   dpf_res, r0
        mov.l   dpf_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
dpf_faultcnt:   .long K_FAULTCNT
dpf_res:        .long TEST_RESULT_ADDRESS
dpf_code:       .long 0x000000F3

ENTRY(exception_handler)
        rts
        nop
ENTRY(jcore_handle_exception)
1:      bra     1b
        nop
ENTRY(do_IRQ)
1:      bra     1b
        nop
ENTRY(arch_local_irq_restore)
        rts
        nop
ENTRY(arch_local_save_flags)
        mov     #0, r0
        rts
        nop

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
