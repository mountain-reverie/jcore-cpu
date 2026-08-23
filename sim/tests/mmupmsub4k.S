! mmupmsub4k.S -- Group-B case B1a/b/c of the TSB PageMask / tag-granularity
! contract (docs/mmu/pagemask-walker-contract.md §7.1, hardware-spec.md §7.0a,
! linux-spec.md §4.3a).
!
! LANE 2: this harness links the REAL linux@jcore objects (arch/sh/mm/
! tlb-jcore.o, arch/sh/kernel/cpu/jcore/{ex,entry}.o), so the TSB row under
! test is written by the REAL __jcore_tlb_walk(). That is the whole point: the
! defect is in WHAT THE KERNEL WRITES into tag_hi, so a Lane-1 (hand-built TSB
! row) mirror of this case would test nothing about it. Built/run by
! sim/linux_sim.sh and by .github/workflows/full-regression.yml, NOT by
! sim/mmu_sim.sh (which cannot see $(LINUX_SRC)).
!
! ---------------------------------------------------------------------------
! WHAT IT PINS
! ---------------------------------------------------------------------------
! The hardware walker compares tag_hi against the faulting VA with an EXACT
! 32-bit equality at 4 KB granularity (core/tlb_walk.vhd, st_tag_hi):
!
!     bus_d(31 downto 12) = va_reg(31 downto 12) and bus_d(11 downto 0) = x"000"
!
! and va_reg is the RAW, unmasked faulting VA. Linux runs a 16 KB base page
! (PAGE_SHIFT = 14). If the kernel writes `addr & PAGE_MASK` as tag_hi, then
! for any access whose FIRST TOUCH of a page is not in that page's base 4 KB
! sub-page -- i.e. VA[13:12] != 0 -- the stored tag has those two bits zero,
! the exact compare can never match, the walker misses, the miss exception
! fires, __jcore_tlb_walk() succeeds against the page table and rewrites the
! SAME non-matching tag, and the access re-faults. ex.S deliberately has no
! retry counter, so that is an UNBOUNDED FAULT LOOP.
!
! The contract's resolution (C1/C2): the RTL is right and the kernel is wrong.
! tag_hi is `VA & JCORE_TSB_TAG_MASK` == `VA & 0xFFFFF000` for EVERY page size
! and every CONFIG_PAGE_SIZE_*, because the TSB set INDEX is already 4 KB
! granular (tsb_ptr() hashes VA[31:12]) and index and tag granularity must be
! the same architectural constant.
!
! Three scenarios, one 16 KB base mapping each (page-size slot 0 -> PageMask
! pm=1), first touch at a DIFFERENT non-base 4 KB sub-page so all three
! VA[13:12] values are covered:
!
!   A  VA 0x00200000 -> PA 0x00100000, first touch at +0x1000  (VA[13:12]=01)
!   B  VA 0x00280000 -> PA 0x00140000, first touch at +0x2000  (VA[13:12]=10)
!   C  VA 0x00300000 -> PA 0x00180000, first touch at +0x3000  (VA[13:12]=11)
!
! Every VA sits in its own 16 KB region, so core/tlb.vhd's install-time dedup
! (which replaces in place on overlap under the INTERSECTION of the two page
! masks, :355-365) cannot make one mapping evict another.
!
! ---------------------------------------------------------------------------
! MANDATORY INSTRUMENTATION (contract §7.0 P1/P2) -- why this guard is not
! just "does it hang?"
! ---------------------------------------------------------------------------
! P2, bounded repeat-fault counter. An unbounded fault loop presents to the
! cosim only as a --stop-time timeout, and jcore-cpu CLAUDE.md ("Writing a
! guard") rules a timeout out as a failure signal: a guard must fail with its
! OWN result code so it cannot be conflated with a wedge from any other cause.
! So this harness does NOT point VBR at the real jcore_vbr_base. It points VBR
! at its own vector page (harness_vbr_base below), whose VBR+0x400 shim
! increments a counter, checks it against FAULT_BOUND, and only then jumps to
! the real jcore_tlb_miss. The shim is pure harness code -- the kernel objects
! under test are unmodified, and every fault still runs the real handler.
!
!   Expected total TLB-miss faults for the whole guard: 3 (one per scenario).
!   FAULT_BOUND: 8. Tripping it reports 0xE0 | phase and spins.
!
!   Phases must stay <= 15: 0xE0|16 is 0xF0, the reserved P1 code below.
!
!   DELIBERATE REFINEMENT OF THE CONTRACT. §7.0 P2 says the trip code is a
!   flat 0xFE. This guard reports 0xE0|phase (0xE1/0xE2/0xE3) instead, and
!   keeps 0xFE for a repeat fault taken before any scenario has started
!   (phase 0). Reason: CLAUDE.md requires "distinct failure IDs to distinct
!   defects so they cannot be conflated", and a flat 0xFE cannot say WHICH of
!   the three sub-cases livelocked. It is a strict refinement -- the code is
!   still the guard's own, still not a timeout -- not a relaxation.
!
! P1, anti-vacuity. Every scenario snapshots P4_TSBCNT (0xFF000054,
! [31:16] = cnt_walks, [15:0] = cnt_hits) around its touch and asserts the
! EXACT hits delta. A scenario that read the right data with cnt_hits
! unchanged proves only that software resolved the access -- the walk-hit is
! the thing under test -- and reports 0xF0.
!
! Expected per scenario: exactly 1 fault, cnt_hits +1. (Miss -> exception ->
! __jcore_tlb_walk() writes the row -> rte -> the access re-executes, misses
! the TLB again, and THIS time the walker's tag compare matches, so it
! installs with no second exception.)
!
! ---------------------------------------------------------------------------
! Memory map (P1 = 0x80000000 | physical; P0 addresses are genuine VAs the
! walker must translate). Modelled on sim/tests/mmuhuge.S.
! ---------------------------------------------------------------------------
!   0x00020000  PGD table       (16 KB, P1 0x80020000)
!   0x00024000  PTE table       (16 KB, P1 0x80024000) -- covers pgd[0]
!   0x00028000  TSB             (512 B, P1 0x80028000, TSB_SIZE_LOG=4)
!   0x00029000  scratch globals (see k_* below)
!   0x0002A000  stack           (P1 0x8002AF00)
!   0x00100000  PA_A  0x00140000  PA_B  0x00180000  PA_C
!
! ---------------------------------------------------------------------------
! Result codes (printed by sim/cpu_ctb.c as unsigned DECIMAL)
! ---------------------------------------------------------------------------
!   0x01/0x02/0x03 ( 1/ 2/ 3) scenario A/B/C: the non-base sub-page load did
!                             not return the sentinel seeded at PA_base+delta
!   0x11/0x12/0x13 (17/18/19) scenario A/B/C: TLB-miss fault count != 1
!   0x21/0x22/0x23 (33/34/35) scenario A/B/C: cnt_hits delta != 1 (but != 0)
!   0x31/0x32/0x33 (49/50/51) scenario A/B/C: the store through VA+delta did
!                             not land at PA_base+delta
!   0x41/0x42/0x43 (65/66/67) scenario A/B/C: PA_base+0 was disturbed -- the
!                             access aliased to the page's BASE sub-page
!   0xE1/0xE2/0xE3 (225/226/227) P2: repeat-fault bound exceeded during
!                             scenario A/B/C. THIS IS THE PRE-FIX FAILURE.
!   0xF0           (240)      P1: cnt_hits did not move at all -- the walker
!                             never resolved it, software did (vacuous case)
!   0xF1           (241)      unexpected general exception at VBR+0x100
!                             (MULTI_HIT, protection, illegal, TRAPA, ...)
!   0xF2           (242)      unexpected interrupt at VBR+0x600
!   0xF3           (243)      do_page_fault() reached -- no scenario here has
!                             an absent or protected pte, so this is a defect
!   0xFE           (254)      P2 bound exceeded with phase == 0
!   0x7F           (127)      _fail integrity net (see below)
!
! ---------------------------------------------------------------------------
! MUTATION RECORD (contract §7.0 P4) -- measured, not asserted
! ---------------------------------------------------------------------------
!   the defect itself: revert arch/sh/mm/tlb-jcore.c to `addr & PAGE_MASK`
!                      -> FAIL Result=225 (0xE1), scenario A livelocks
!   the data assertion: _chk_tab row 1 expected 0x57000001 -> 0x57000009
!                      -> FAIL Result=49 (0x31), a code of this guard's own
!   unmutated          -> Test Passed
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS. TEST_PASS_MAGIC is a
! non-zero token, but r9 == 0 is still a meaningless "failure", so _fail
! clamps r9 == 0 to 0x7F rather than reporting a code that names nothing.

#include "sim_instr.h"
#include <asm/pgtable-bits-jcore.h>
#define ENTRY(name) .globl name; .balign 4; name:

! ---- Page-table / TSB layout, and the pte flag word. Size slot 0 is "base",
! ---- which jcore_pm_for_slot[] maps to hardware PageMask 1 == 16 KB. D is set
! ---- so jcore_pte_to_ptel() does not take its clean-page W-withholding arm.
#define PGD_TBL   0x80020000
#define PTE_TBL   0x80024000
#define TSB_BASE  0x80028000
#define PTE_FLAGS 0xB9                  /* V|C|D|U|W, size slot 0 */

! ---- Scratch globals. `mov.l @(disp,PC)` reaches FORWARDS only, so several
! ---- literal pools in this file each need their own copy of these addresses;
! ---- naming them here is what stops those copies drifting apart.
#define K_SCRATCH       0x80029000
#define K_SCRATCH_WORDS 8               /* zeroes K_SCRATCH .. K_SCRATCH+0x1C */
#define K_FAULTCNT      0x80029004      /* do_page_fault() count             */
#define K_TLBFAULTS     0x80029014      /* P2 bounded repeat-fault counter   */
#define K_PHASE         0x80029018      /* scenario id, named by the P2 trip */

! ---- The workload. Each mapping is one 16 KB page (size slot 0 -> PageMask
! ---- pm=1) whose FIRST touch is at a different non-base 4 KB sub-page, so
! ---- all three VA[13:12] values are covered. Every VA sits in its own 16 KB
! ---- region, so core/tlb.vhd's install-time dedup cannot make one mapping
! ---- evict another. P1() is the untranslated kernel alias used to seed and
! ---- to read back by PHYSICAL address.
#define P1(x)     ((x) | 0x80000000)
#define VA_A      0x00200000
#define PA_A      0x00100000
#define D_A       0x1000                /* VA[13:12] = 01 */
#define VA_B      0x00280000
#define PA_B      0x00140000
#define D_B       0x2000                /* VA[13:12] = 10 */
#define VA_C      0x00300000
#define PA_C      0x00180000
#define D_C       0x3000                /* VA[13:12] = 11 */

! Bounded repeat-fault limit (contract §7.0 P2). Expected total is 3.
#define FAULT_BOUND 8

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
! Harness vector page. VBR points HERE, not at the kernel's jcore_vbr_base:
! the +0x400 shim is what turns the pre-fix unbounded fault loop into a
! diagnosable result code instead of a cosim timeout (contract §7.0 P2).
!
! .balign 0x100 is safe against sh32_p1.x: .text is placed at ORIGIN
! 0x80000200, which is already 0x100-aligned, so the alignment gas computes
! relative to the section start survives linking.
!
! On entry SR.RB = 1 (bank 1) and bank-1 r0-r7 are pure scratch to the real
! handler -- jcore_vec_tlb's first act is to push r4-r7 and PR -- so the shim
! may use r0/r1/r2 freely. Every address it touches is P1 or P2, i.e.
! untranslated, which matters because SR.BL = 1 here: a nested TLB miss would
! be a double fault.
! ===========================================================================
        .balign 0x100
ENTRY(harness_vbr_base)
0:      bra     0b
        nop

        .org    harness_vbr_base + 0x100
        ! Any non-TLB-miss exception: MULTI_HIT, protection, illegal, TRAPA.
        ! This harness expects none of them.
        mov.l   g_res, r0
        mov.l   g_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
g_res:  .long TEST_RESULT_ADDRESS
g_code: .long 0x000000F1

        .org    harness_vbr_base + 0x400
        ! P2: bounded repeat-fault counter, then the REAL vector body.
        mov.l   t_cnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov     #FAULT_BOUND, r2
        cmp/hi  r2, r1                  ! r1 > FAULT_BOUND ?
        bt      9f
        mov.l   t_real, r0
        jmp     @r0                     ! jcore_tlb_miss (== jcore_vbr_base+0x400)
        nop
9:      ! Bound exceeded: report 0xE0 | phase and spin. This is the pre-fix
        ! failure signature -- a NAMED result, never a --stop-time timeout.
        mov.l   t_phase, r0
        mov.l   @r0, r1
        tst     r1, r1                  ! a repeat fault before any scenario
        bt      6f                      ! started has no phase to name: 0xFE
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
        ! No interrupt source is enabled; reaching here is a defect.
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
        ! ---- Ensure RB=0 (keep MD=1). core/cpu.vhd gates walk_req on
        ! ---- dp_sr.rb = '0' and the cosim starts in bank 1. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        ! ---- Initialise PR: the fault handlers' first sts.l pr, @-r15 must
        ! ---- not store undefined data (the GHDL SRAM model rejects it). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- Pre-zero the GPRs the fault handlers push on entry, in BOTH
        ! ---- banks (exception entry sets SR.RB=1). Same rationale. ----
        mov.l   p_rbset,  r8
        mov.l   p_rbclear, r9
        stc     sr, r0 ; or  r8, r0 ; ldc r0, sr    ! -> RB=1 (bank 1)
        nop ; nop
        mov     #0, r0 ; mov #0, r1 ; mov #0, r2 ; mov #0, r3
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7
        stc     sr, r0 ; and r9, r0 ; ldc r0, sr    ! -> RB=0 (bank 0)
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

        ! ---- ASIDR = 0, GBR = 0 (jcore_tlb_fault_entry saves GBR). ----
        mov     #0, r0
        ldc     r0, asidr
        nop
        nop
        mov     #0, r0
        ldc     r0, gbr
        nop
        nop

        ! ---- Zero the scratch globals: TLB-fault counter, phase, and the
        ! ---- do_page_fault handshake. ----
        mov.l   k_scratch, r0
        mov     #K_SCRATCH_WORDS, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- pgd[0] -> pte table. ----
        mov.l   k_pgd,   r0
        mov.l   k_ptetbl, r1
        mov.l   r1, @r0

        ! ---- The three 16 KB ptes (size slot 0 -> jcore_pm_for_slot[0] == 1
        ! ---- -> PageMask pm=1 -> 16 KB). ----
        mov.l   k_pte_a, r0 ; mov.l v_pte_a, r1 ; mov.l r1, @r0
        mov.l   k_pte_b, r0 ; mov.l v_pte_b, r1 ; mov.l r1, @r0
        mov.l   k_pte_c, r0 ; mov.l v_pte_c, r1 ; mov.l r1, @r0

        ! ---- Zero the TSB (16 sets x 32 bytes => 128 words). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        shll    r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed the backing words: a distinct sentinel at each first-touch
        ! ---- sub-page, and a DIFFERENT loud sentinel at each page's BASE
        ! ---- sub-page, so a read that aliased down to VA[13:12]=00 returns
        ! ---- 0xBAD000nn instead of the expected value. ----
        mov.l   k_seed_tab, r14
        mov.l   k_seed_end, r13
1:      mov.l   @r14+, r0
        mov.l   @r14+, r1
        mov.l   r1, @r0
        cmp/hs  r13, r14
        bf      1b

        ! ---- MMU_TTB -> our pgd. ----
        mov.l   k_ttb_a, r0 ; mov.l k_pgd, r1 ; mov.l r1, @r0

        ! ---- VBR -> the HARNESS vector page (see its header above). ----
        mov.l   k_vbr, r0
        ldc     r0, vbr
        nop
        nop

        ! ---- TSB config. ----
        mov.l   k_tsbbr_a,  r0 ; mov.l v_tsbbr,  r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0
        nop
        nop

        ! =================== the three scenarios ==========================
        mov.l   k_scen_tab, r14
        mov.l   k_scen_end, r13

_scen_loop:
        mov.l   @r14+, r10              ! VA to touch (VA_base + delta)
        mov.l   @r14+, r11              ! sentinel expected there
        mov.l   @r14+, r12              ! phase id, also the fail-code base

        ! Publish the phase so the VBR+0x400 shim can name the scenario if it
        ! trips the repeat-fault bound.
        mov.l   s_phase, r0
        mov.l   r12, @r0

        ! Baselines: fault counter, and cnt_hits from P4_TSBCNT.
        mov.l   s_tlbfaults, r0
        mov.l   @r0, r8                 ! f0
        mov.l   s_walkcnt, r0
        mov.l   @r0, r7
        extu.w  r7, r7                  ! hits0

        ! ---- THE FIRST TOUCH of this page, at a NON-BASE 4 KB sub-page. ----
        mov.l   @r10, r5

        ! ---- A store through the same VA. The entry is installed by now, so
        ! ---- this must take no further fault; it is read back after AT is
        ! ---- off to prove the PA relocation was exact. ----
        mov.l   s_storebase, r0
        mov     r12, r6
        or      r0, r6                  ! 0x57000000 | phase
        mov.l   r6, @r10

        ! ---- Deltas. ----
        mov.l   s_tlbfaults, r0
        mov.l   @r0, r6
        sub     r8, r6                  ! r6 = fault delta
        mov.l   s_walkcnt, r0
        mov.l   @r0, r4
        extu.w  r4, r4
        sub     r7, r4                  ! r4 = cnt_hits delta

        ! ---- Assert: the load returned the sub-page's own sentinel. ----
        cmp/eq  r11, r5
        bt      1f
        mov     r12, r9                 ! 0x01 / 0x02 / 0x03
        bra     _fail
        nop
1:
        ! ---- Assert: exactly ONE TLB-miss fault. ----
        mov     #1, r0
        cmp/eq  r0, r6
        bt      2f
        mov     r12, r9
        add     #0x10, r9               ! 0x11 / 0x12 / 0x13
        bra     _fail
        nop
2:
        ! ---- P1 anti-vacuity: cnt_hits must have moved, and by exactly 1. ----
        tst     r4, r4
        bf      3f
        mov.l   s_f0code, r9            ! 0xF0 -- software resolved it, not the
        bra     _fail                   ! walker: the case would be vacuous
        nop
3:      mov     #1, r0
        cmp/eq  r0, r4
        bt      4f
        mov     r12, r9
        add     #0x20, r9               ! 0x21 / 0x22 / 0x23
        bra     _fail
        nop
4:
        cmp/hs  r13, r14
        bt      _scen_done
        bra     _scen_loop
        nop

        .align 2
s_phase:     .long K_PHASE
s_tlbfaults: .long K_TLBFAULTS
s_walkcnt:   .long 0xFF000054           ! [31:16]=cnt_walks [15:0]=cnt_hits
s_storebase: .long 0x57000000
s_f0code:    .long 0x000000F0

_scen_done:
        ! ---- Drain the write path, then turn AT off and verify the three
        ! ---- stores by PHYSICAL address. ----
        mov     #20, r0
1:      dt      r0
        bf      1b
        mov.l   q_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0
        nop
        nop

        mov.l   q_chk_tab, r14
        mov.l   q_chk_end, r13
_chk_loop:
        mov.l   @r14+, r10              ! P1 address to read
        mov.l   @r14+, r11              ! value it must hold
        mov.l   @r14+, r12              ! fail code
        mov.l   @r10, r5
        cmp/eq  r11, r5
        bt      1f
        mov     r12, r9
        bra     _fail
        nop
1:      cmp/hs  r13, r14
        bt      _all_done
        bra     _chk_loop
        nop

        .align 2
q_mmucr:   .long 0xFF000010
q_chk_tab: .long _chk_tab
q_chk_end: .long _chk_tab_end

_all_done:
        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000        ! SR.RB
k_pgd:          .long PGD_TBL
k_ptetbl:       .long PTE_TBL
k_tsb:          .long TSB_BASE
k_scratch:      .long K_SCRATCH
k_ttb_a:        .long 0xFF000008        ! MMU_TTB
k_vbr:          .long harness_vbr_base
k_tsbbr_a:      .long 0xFF000014        ! TSBBR
v_tsbbr:        .long TSB_BASE | 4      ! TSB_SIZE_LOG=4 -> 16 sets
k_tsbcfg_a:     .long 0xFF000018        ! TSBCFG
v_tsbcfg:       .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
k_mmucr:        .long 0xFF000010
k_seed_tab:     .long _seed_tab
k_seed_end:     .long _seed_tab_end
k_scen_tab:     .long _scen_tab
k_scen_end:     .long _scen_tab_end

! ---- The three 16 KB ptes, addressed the way the walker indexes them:
! ---- pte_index = (VA >> 14) & 0xFFF, and pgd_index = VA >> 26 == 0 for all
! ---- three, so one pte table under pgd[0] covers them. Computing the index
! ---- from the VA rather than hardcoding it means a VA edit cannot leave the
! ---- pte behind at a stale slot.
k_pte_a:        .long PTE_TBL + ((VA_A >> 14) & 0xFFF) * 4
v_pte_a:        .long PA_A | PTE_FLAGS
k_pte_b:        .long PTE_TBL + ((VA_B >> 14) & 0xFFF) * 4
v_pte_b:        .long PA_B | PTE_FLAGS
k_pte_c:        .long PTE_TBL + ((VA_C >> 14) & 0xFFF) * 4
v_pte_c:        .long PA_C | PTE_FLAGS

        .balign 4
_seed_tab:
        ! P1 address of the physical word    value
        .long P1(PA_A + D_A), 0x5E9A0001   ! the first-touch sub-page's sentinel
        .long P1(PA_A),       0xBAD00001   ! the BASE sub-page's loud decoy
        .long P1(PA_B + D_B), 0x5E9A0002
        .long P1(PA_B),       0xBAD00002
        .long P1(PA_C + D_C), 0x5E9A0003
        .long P1(PA_C),       0xBAD00003
_seed_tab_end:

        .balign 4
_scen_tab:
        ! VA to touch       sentinel      phase / fail-code base
        .long VA_A + D_A,   0x5E9A0001,   1        ! B1a  VA[13:12] = 01
        .long VA_B + D_B,   0x5E9A0002,   2        ! B1b  VA[13:12] = 10
        .long VA_C + D_C,   0x5E9A0003,   3        ! B1c  VA[13:12] = 11
_scen_tab_end:

        .balign 4
_chk_tab:
        ! P1 address           required value  fail code
        .long P1(PA_A + D_A),  0x57000001,  0x31   ! the store landed here...
        .long P1(PA_A),        0xBAD00001,  0x41   ! ...and NOT on the base sub-page
        .long P1(PA_B + D_B),  0x57000002,  0x32
        .long P1(PA_B),        0xBAD00002,  0x42
        .long P1(PA_C + D_C),  0x57000003,  0x33
        .long P1(PA_C),        0xBAD00003,  0x43
_chk_tab_end:

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: a code of 0 names
        bf      1f                      ! nothing, so report 0x7F instead
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
! (same set as sim/tests/mmuhuge.S -- same real link, same needs).
! ===========================================================================

! do_page_fault(regs, error_code, address). Every scenario here has a present,
! writable, non-PROTNONE pte, so reaching this is itself the defect: report
! 0xF3 and spin rather than trying to fix anything up.
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

! exception_handler -- generic (non-TLB) exception dispatch; never taken,
! because VBR points at the harness vector page, not at jcore_vbr_base.
ENTRY(exception_handler)
        rts
        nop

! Referenced by tlb-jcore.o (__update_tlb) and entry.o; never reached here.
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
