! mmuhuge.S -- J4-TLB multi-size HugeTLB program, Task 6: bare-metal harness
! driving the REAL arch/sh/mm/tlb-jcore.c __jcore_tlb_walk() (and the real
! arch/sh/kernel/cpu/jcore/{ex,entry}.S fixed TLB-miss vectors) through the
! GHDL cosim, proving the REAL Linux walker installs a huge TLB entry (a
! PageMask != base 16 KB) from a PTE that carries a page-size *slot* (the
! 3-bit field packed into free flag bits {10,12,13}, see
! asm/pgtable-bits-jcore.h's jcore_pte_size_slot()/jcore_pte_to_ptel()).
!
! Modeled directly on sim/tests/mmulinux.S (SP2 Task 1) -- same real-object
! link, same boilerplate (RB=0, GPR pre-zeroing so the handlers' first
! sts.l/mov.l @-r15 pushes don't hit the SRAM model's undefined-write-data
! guard, ASIDR=0, GBR=0), same TSB/PGD/PTE construction. The only new idea:
!
!   Once a huge TLB entry is installed, ALL of the huge page's address space
!   hits that SAME entry via the hardware's masked VPN compare (PageMask
!   widens the "don't care" low VA bits used in the tag match, see
!   core/tlb.vhd vpn_compare_mask()/page_offset_mask()). So we only need to
!   populate ONE pte slot (the one the first faulting address indexes) --
!   NOT the whole huge span -- and then touch a SECOND address inside the
!   same huge page, at a DIFFERENT 16 KB sub-page (base + 0x4000). That
!   second address's OWN pte slot is left un-populated (zero, i.e.
!   "not present"): if the huge entry did not really cover the whole span
!   (e.g. a base-page-only regression), the second access would either
!   mistranslate to the wrong PA, or -- if the miss vector wrongly fell
!   through to a real walk for that slot -- fault against a not-present
!   pte. Either way, the intended behaviour (a masked-compare HIT on the
!   SAME entry, translating to PA_base+0x4000, with the walker-invocation
!   counter unchanged) is the only path that reaches "Test Passed".
!
! Three huge sizes are exercised. All three fit comfortably inside the GHDL
! cosim's 16 MB anonymous backing region right past the loaded image -- see
! sim/cpu_ctb.c's `mmap_ptr2`/mem_bus_stack_map -- so no huge span needs to
! be fully backed by real RAM, only the handful of words this harness
! actually touches:
!
!   - slot 1 -> PageMask pm=2 -> 64 KB   (jcore_pm_for_slot[1] == 2)
!   - slot 3 -> PageMask pm=4 -> 1 MB    (jcore_pm_for_slot[3] == 4)
!   - slot 7 -> PageMask pm=8 -> 256 MB  (jcore_pm_for_slot[7] == 8)
!
! H1/H2 bracket the size range with the smallest non-base huge size and a
! size two hardware PageMask steps larger, while both base VAs/PAs stay
! well under 4 MB -- comfortably inside the 16 MB backed window. H3 proves
! the opposite end: the LARGEST PageMask the J4 TLB supports installs
! correctly as one entry.
!
! H3/pm=8 has a hardware wrinkle worth documenting (core/tlb.vhd,
! core/cpu.vhd's `g_dstore_squash`/PIPT relocation): the design caps
! physical addresses at 28 bits (PA[31:28] is unconditionally forced to
! "0000" on every TLB hit, not just for huge pages), and page_offset_mask()
! for pm=8 sets n=16, i.e. ALL 16 bits of the PPN[27:12] field become
! "in-page offset -> use VA", none come from the PTE's stored PPN. So for
! a 256 MB page the PTE's PPN bits are architecturally inert: the
! translated PA is always VA & 0x0FFFFFFF, independent of what physical
! frame the PTE names. In other words, the 256 MB size is only usable as
! an identity-style window (VA[27:0] == PA[27:0]) -- there are no frame-
! select bits left once a huge page spans the CPU's entire 256 MB physical
! range. VA_H3 is chosen equal to PA_H3 for exactly this reason.
!
! Memory map (P1 = 0x80000000 | physical offset; P0 addresses are genuine,
! translated by the walker):
!
!   0x00020000  PGD table        (16 KB, P1 0x80020000)
!   0x00024000  PTE table        (16 KB, P1 0x80024000) -- covers pgd[0]
!   0x00028000  TSB              (256 B, P1 0x80028000)
!   0x00029000  scratch globals  (walker-invocation counter, fault handshake)
!   0x0002A000  stack            (P1 0x8002A000, SP set near top)
!   0x00100000  H1 backing page  (64 KB huge page's PFN, slot 1)
!   0x00200000  H2 backing page  (1 MB huge page's PFN, slot 3)
!   0x00300000  H3 backing page + VA_H3 (256 MB huge page's PFN==VA, slot 7,
!                                  see the pm=8 wrinkle above)
!   0x00200000 (P0) VA_H1        pgd_index=0, pte_index=0x80
!   0x00400000 (P0) VA_H2        pgd_index=0, pte_index=0x100
!   0x00300000 (P0) VA_H3        pgd_index=0, pte_index=0xC0
!
! Assertions (distinct r9 fail codes so a regression is diagnosable):
!   r9=1  VA_H1 base load != the sentinel seeded at PA_H1 (translation
!         did not happen, or landed on the wrong PA)
!   r9=2  VA_H1's TSB slot PTEL image != the expected encoding: PFN(PA_H1)
!         | PageMask(pm=2, 64 KB) | V|C|U|W|D -- proves jcore_pte_to_ptel()
!         actually decoded the size slot, not just "some install happened"
!   r9=3  VA_H1+0x4000 (a DIFFERENT 16 KB sub-page, own pte slot left
!         un-populated) load != the sentinel seeded at PA_H1+0x4000 -- the
!         definitive huge-page proof: this can only read correctly if the
!         single huge entry installed for VA_H1 covers this address too
!   r9=4  walker-invocation counter changed across the VA_H1+0x4000 touch
!         (a real walk must NOT have happened -- it would have found the
!         un-populated pte slot and either faulted or installed a bogus
!         entry; either way the masked-compare TLB hit is what's expected)
!   r9=5  VA_H2 base load != the sentinel seeded at PA_H2 (1 MB huge page)
!   r9=6  VA_H2's TSB slot PTEL image != PFN(PA_H2) | PageMask(pm=4, 1 MB)
!         | V|C|U|W|D
!   r9=7  VA_H2+0x4000 load != the sentinel seeded at PA_H2+0x4000
!   r9=8  walker-invocation counter changed across the VA_H2+0x4000 touch
!   r9=9  VA_H3 base load != the sentinel seeded at PA_H3 (256 MB huge page)
!   r9=10 VA_H3's TSB slot PTEL image != PFN(PA_H3) | PageMask(pm=8, 256 MB)
!         | V|C|U|W|D -- proves the LARGEST PageMask the J4 TLB supports
!         installs correctly as one entry
!   r9=11 VA_H3+0x4000 load != the sentinel seeded at PA_H3+0x4000
!   r9=12 walker-invocation counter changed across the VA_H3+0x4000 touch
!   r9=99 do_page_fault() was reached unexpectedly (this harness expects
!         zero faults across all six touches)

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

        ! ---- Initialise PR (first-fault store-of-uninitialised-PR guard --
        ! see mmulinux.S's identical comment). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- Pre-zero the GPRs the fault handlers push on entry before
        ! defining them (same rationale as mmulinux.S: the GHDL SRAM bus
        ! model rejects an undefined-data store). Bank-1 r4-r7 must be
        ! zeroed under RB=1 (exception entry sets SR.RB=1); r8-r10 are
        ! unbanked so one zero covers both banks. ----
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

        ! ---- ASIDR = 0 (single context; not exercised by this harness). ----
        mov     #0, r0
        ldc     r0, asidr
        nop
        nop

        ! ---- GBR = 0 (jcore_tlb_fault_entry unconditionally saves it). ----
        mov     #0, r0
        ldc     r0, gbr
        nop
        nop

        ! ---- Zero the walker-invocation counter (bumped by our own strong
        ! jcore_tlb_walk_mark_accessed() override below). ----
        mov.l   k_wcnt, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Build pgd[0] -> pte table (P1 pointer, page-aligned). ----
        mov.l   k_pgd,   r0
        mov.l   k_ptetbl, r1
        mov.l   r1, @r0

        ! ---- Build the three huge ptes. VA_H1's/VA_H2's/VA_H3's own +0x4000
        ! sub-page pte slots are deliberately left un-populated (the
        ! underlying GHDL anon-mmap backing is zero-initialised, so those
        ! words already read as an all-zero, not-present pte -- no explicit
        ! store needed; see the file header). ----
        mov.l   k_pte_h1, r0
        mov.l   v_pte_h1, r1
        mov.l   r1, @r0
        mov.l   k_pte_h2, r0
        mov.l   v_pte_h2, r1
        mov.l   r1, @r0
        mov.l   k_pte_h3, r0
        mov.l   v_pte_h3, r1
        mov.l   r1, @r0

        ! ---- Zero the do_page_fault handshake globals; point the fault
        ! target at `unexpected_fault` (this harness expects zero faults). ----
        mov.l   k_faultcnt, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   k_fault_target, r0
        mov.l   unexpected_fault_ptr, r1
        mov.l   r1, @r0

        ! ---- Zero the TSB (64 words). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed the six backing words directly (P1, untranslated). ----
        mov.l   k_backing_h1,  r0 ; mov.l v_seed_h1,  r1 ; mov.l r1, @r0
        mov.l   k_backing_h1b, r0 ; mov.l v_seed_h1b, r1 ; mov.l r1, @r0
        mov.l   k_backing_h2,  r0 ; mov.l v_seed_h2,  r1 ; mov.l r1, @r0
        mov.l   k_backing_h2b, r0 ; mov.l v_seed_h2b, r1 ; mov.l r1, @r0
        mov.l   k_backing_h3,  r0 ; mov.l v_seed_h3,  r1 ; mov.l r1, @r0
        mov.l   k_backing_h3b, r0 ; mov.l v_seed_h3b, r1 ; mov.l r1, @r0

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

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0
        nop
        nop

        ! ============= SCENARIO H1: 64 KB huge page (slot 1, pm=2) =========
        mov.l   va_h1, r0
        mov.l   @r0, r8                 ! load -> TLB miss -> walker installs
                                         ! the 64 KB huge entry from k_pte_h1

        stc     tsbptr, r3              ! capture VA_H1's TSB slot ptr NOW
                                         ! (still AT-on; STC reads the MMU
                                         ! register regardless)
        mov.l   k_wcnt, r0 ; mov.l @r0, r4   ! wcnt baseline, post-base-walk

        mov.l   va_h1b, r0
        mov.l   @r0, r11                ! DIFFERENT 16 KB sub-page, own pte
                                         ! slot un-populated -> must be a
                                         ! masked-compare HIT on the SAME
                                         ! huge entry, translating to
                                         ! PA_H1+0x4000, NOT a fresh walk

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   v_seed_h1, r1 ; cmp/eq r1, r8 ; mov #1, r9 ; bf _fail

        mov.l   @(8, r3), r2            ! TSB slot data (PTEL image)
        mov.l   v_ptel_expect_h1, r1
        cmp/eq  r1, r2 ; mov #2, r9 ; bf _fail

        mov.l   v_seed_h1b, r1 ; cmp/eq r1, r11 ; mov #3, r9 ; bf _fail

        mov.l   k_wcnt, r0 ; mov.l @r0, r5
        cmp/eq  r4, r5 ; mov #4, r9 ; bf _fail   ! walker must NOT have re-run

        ! ============= SCENARIO H2: 1 MB huge page (slot 3, pm=4) ==========
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! AT back on
        nop
        nop

        mov.l   va_h2, r0
        mov.l   @r0, r8                 ! load -> TLB miss -> walker installs
                                         ! the 1 MB huge entry from k_pte_h2

        stc     tsbptr, r3
        mov.l   k_wcnt, r0 ; mov.l @r0, r4

        mov.l   va_h2b, r0
        mov.l   @r0, r11                ! own pte slot un-populated -> must
                                         ! be a masked-compare HIT

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   v_seed_h2, r1 ; cmp/eq r1, r8 ; mov #5, r9 ; bf _fail

        mov.l   @(8, r3), r2
        mov.l   v_ptel_expect_h2, r1
        cmp/eq  r1, r2 ; mov #6, r9 ; bf _fail

        mov.l   v_seed_h2b, r1 ; cmp/eq r1, r11 ; mov #7, r9 ; bf _fail

        mov.l   k_wcnt, r0 ; mov.l @r0, r5
        cmp/eq  r4, r5 ; mov #8, r9 ; bf _fail

        ! ============= SCENARIO H3: 256 MB huge page (slot 7, pm=8) =========
        ! Largest PageMask the J4 TLB supports -- proves it installs as ONE
        ! entry, same single-slot / cross-16KB-subpage-hit technique as H1/H2.
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! AT back on
        nop
        nop

        mov.l   va_h3, r0
        mov.l   @r0, r8                 ! load -> TLB miss -> walker installs
                                         ! the 256 MB huge entry from k_pte_h3

        stc     tsbptr, r3
        mov.l   k_wcnt, r0 ; mov.l @r0, r4

        mov.l   va_h3b, r0
        mov.l   @r0, r11                ! own pte slot un-populated -> must
                                         ! be a masked-compare HIT

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   v_seed_h3, r1 ; cmp/eq r1, r8 ; mov #9, r9 ; bf _fail

        mov.l   @(8, r3), r2
        mov.l   v_ptel_expect_h3, r1
        cmp/eq  r1, r2 ; mov #10, r9 ; bf _fail

        mov.l   v_seed_h3b, r1 ; cmp/eq r1, r11 ; mov #11, r9 ; bf _fail

        mov.l   k_wcnt, r0 ; mov.l @r0, r5
        cmp/eq  r4, r5 ; mov #12, r9 ; bf _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000        ! SR.RB bit (bank select)
k_pgd:          .long 0x80020000
k_ptetbl:       .long 0x80024000
k_tsb:          .long 0x80028000
k_wcnt:         .long 0x80029000
k_faultcnt:     .long 0x80029004
k_faultaddr:    .long 0x80029008
k_fault_target: .long 0x8002900C
k_saved_sp:     .long 0x80029010
unexpected_fault_ptr: .long unexpected_fault
k_ttb_a:        .long 0xFF000008        ! MMU_TTB
k_vbr:          .long jcore_vbr_base
k_tsbbr_a:      .long 0xFF000014        ! TSBBR
v_tsbbr:        .long 0x80028004
k_tsbcfg_a:     .long 0xFF000018        ! TSBCFG
v_tsbcfg:       .long 0x00000061
k_mmucr:        .long 0xFF000010        ! MMUCR

! ---- Scenario H1: 64 KB huge page, size slot 1 (pte bit10 == 0x400 set,
! bits12/13 clear -> jcore_pte_size_slot() == 1 -> jcore_pm_for_slot[1] == 2
! -> PTEL PageMask == 2 -> page size 4 KB << (2*2) == 64 KB). pte_index for
! VA_H1 = (0x00200000 >> 14) & 0xFFF = 0x80 -> k_ptetbl + 0x200; VA_H1's own
! +0x4000 sub-page (VA 0x00204000) is pte_index 0x81 -- deliberately left
! un-populated (zero / not-present).
va_h1:          .long 0x00200000
va_h1b:         .long 0x00204000
k_pte_h1:       .long 0x80024200
v_pte_h1:       .long 0x001004B9        ! PFN(0x00100000)|slot1(0x400)|V|C|U|W|D(0xB9)
k_backing_h1:   .long 0x80100000
k_backing_h1b:  .long 0x80104000
v_seed_h1:      .long 0xC0FFEE64        ! 64 KB scenario sentinel
v_seed_h1b:     .long 0xC0FFEE65
v_ptel_expect_h1: .long 0x001002B9      ! PFN(0x00100000)|PageMask(pm=2,0x200)|V|C|U|W|D

! ---- Scenario H2: 1 MB huge page, size slot 3 (pte bits10,12 set (0x400 |
! 0x1000 == 0x1400), bit13 clear -> jcore_pte_size_slot() == 3 ->
! jcore_pm_for_slot[3] == 4 -> PTEL PageMask == 4 -> page size 4 KB<<(2*4)
! == 1 MB). pte_index for VA_H2 = (0x00400000 >> 14) & 0xFFF = 0x100 ->
! k_ptetbl + 0x400; VA_H2's own +0x4000 sub-page (VA 0x00404000) is
! pte_index 0x101 -- deliberately left un-populated.
va_h2:          .long 0x00400000
va_h2b:         .long 0x00404000
k_pte_h2:       .long 0x80024400
v_pte_h2:       .long 0x002014B9        ! PFN(0x00200000)|slot3(0x1400)|V|C|U|W|D(0xB9)
k_backing_h2:   .long 0x80200000
k_backing_h2b:  .long 0x80204000
v_seed_h2:      .long 0xC0FFEE10        ! 1 MB scenario sentinel
v_seed_h2b:     .long 0xC0FFEE11
v_ptel_expect_h2: .long 0x002004B9      ! PFN(0x00200000)|PageMask(pm=4,0x400)|V|C|U|W|D

! ---- Scenario H3: 256 MB huge page, size slot 7 (pte bits10,12,13 all set
! (0x400 | 0x1000 | 0x2000 == 0x3400) -> jcore_pte_size_slot() == 7 ->
! jcore_pm_for_slot[7] == 8 -> PTEL PageMask == 8 -> page size 4 KB<<(2*8)
! == 256 MB, the LARGEST size the J4 TLB supports). At pm=8,
! page_offset_mask() makes ALL 16 bits of PPN[27:12] "in-page offset ->
! use VA" (see the file header): the PTE's PPN is architecturally inert
! for this size, so the translated PA is always VA & 0x0FFFFFFF. VA_H3 is
! therefore chosen numerically equal to PA_H3 (0x00300000); pgd_index =
! VA_H3>>26 == 0 (fits pgd[0], same table as H1/H2) and pte_index =
! (VA_H3 >> 14) & 0xFFF == 0xC0 -> k_ptetbl + 0x300. VA_H3's own +0x4000
! sub-page (VA 0x00304000) is pte_index 0xC1 -- deliberately left
! un-populated. ----
va_h3:          .long 0x00300000
va_h3b:         .long 0x00304000
k_pte_h3:       .long 0x80024300
v_pte_h3:       .long 0x003034B9        ! PFN(0x00300000)|slot7(0x3400)|V|C|U|W|D(0xB9)
k_backing_h3:   .long 0x80300000
k_backing_h3b:  .long 0x80304000
v_seed_h3:      .long 0xC0FFEE01        ! 256 MB scenario sentinel
v_seed_h3b:     .long 0xC0FFEE02
v_ptel_expect_h3: .long 0x003008B9      ! PFN(0x00300000)|PageMask(pm=8,0x800)|V|C|U|W|D

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

! ===========================================================================
! Stub set for the three real linux@jcore objects' cross-object undefined
! symbols (copied verbatim from mmulinux.S -- same real link, same needs).
! ===========================================================================

! do_page_fault(regs, error_code, address) -- this harness expects ZERO
! faults; if one is reached, record it and halt (never rts/rte -- the
! fault is never actually fixed up).
ENTRY(do_page_fault)
        mov.l   dpf_faultcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   dpf_faultaddr, r0
        mov.l   r6, @r0

        mov.l   dpf_rbclear, r0
        stc     sr, r1
        and     r0, r1
        ldc     r1, sr
        nop
        nop

        mov.l   dpf_saved_sp, r0
        mov.l   @r0, r15

        mov.l   dpf_target, r0
        mov.l   @r0, r0
        jmp     @r0
        nop
        .align 2
dpf_faultcnt:   .long 0x80029004        ! == k_faultcnt
dpf_faultaddr:  .long 0x80029008        ! == k_faultaddr
dpf_rbclear:    .long 0xDFFFFFFF        ! == p_rbclear (duplicated: forward-only pc-rel)
dpf_saved_sp:   .long 0x80029010        ! == k_saved_sp
dpf_target:     .long 0x8002900C        ! == k_fault_target

! unexpected_fault -- this harness's fault target throughout (expects zero
! faults). Record r9=99 and halt.
ENTRY(unexpected_fault)
        mov.l   p_test_result2, r0
        mov     #99, r9
        mov.l   r9, @r0
1:      bra     1b
        nop
        .align 2
p_test_result2: .long TEST_RESULT_ADDRESS

! exception_handler -- generic (non-TLB) exception dispatch; never taken.
ENTRY(exception_handler)
        rts
        nop

! arch_local_irq_restore(flags) / arch_local_save_flags() -- referenced by
! tlb-jcore.o's __update_tlb(); never actually called here.
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

! jcore_tlb_walk_mark_accessed(pte_t *ptep, pte_t entry) -- STRONG
! definition shadows tlb-jcore.o's __weak default (mmuhuge.o links first,
! see sim/tests/Makefile) so this harness gets an unambiguous
! walker-invocation counter: __jcore_tlb_walk() only calls this when it
! finds the pte's _PAGE_ACCESSED bit unset, which is true for every real
! walk our two base-VA touches take (fresh ptes, never marked accessed
! before). r4 = ptep, r5 = entry (32-bit scalar pte_t, non-PAE).
ENTRY(jcore_tlb_walk_mark_accessed)
        mov.l   p_wcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   r5, @r4                 ! set_pte(ptep, entry)
        rts
        nop
        .align 2
p_wcnt: .long 0x80029000               ! == k_wcnt (duplicated locally:
                                        ! mov.l is PC-relative-forward-only)
