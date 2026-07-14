! mmulinux.S -- SP2 Task 1: bare-metal harness driving the REAL Linux
! arch/sh/mm/tlb-jcore.c __jcore_tlb_walk() (and the real
! arch/sh/kernel/cpu/jcore/{ex,entry}.S fixed TLB-miss vectors) through the
! GHDL cosim.
!
! Unlike sim/tests/mmurun.S (which hand-rolls its OWN vector table, its own
! ad-hoc PTE encoding, and .word-encodes every MMU-only instruction because
! it is assembled by the *system* sh2-elf-gas), this harness:
!
!   - links against the real linux@jcore objects (arch/sh/mm/tlb-jcore.o,
!     arch/sh/kernel/cpu/jcore/{ex,entry}.o) built by SP2 Task 0's kbuild
!     recipe, so jcore_vbr_base / jcore_vec_dload / jcore_vec_dstore /
!     jcore_tlb_miss_slow / __jcore_tlb_walk() are the actual kernel code;
!   - is itself assembled by the WIP J4 gas (binutils-gdb/build-sh2), so it
!     can use the real MMU mnemonics (stc/ldc pteh,ptel,asidr,tsbptr,vbr;
!     ldtlb.rn) directly instead of .word-encoding them;
!   - builds a REAL two-level Linux page table (pgd -> pte, 16 KB pages,
!     arch/sh/include/asm/pgtable-2level.h layout) instead of the hand-rolled
!     "PA|flags" PTE image mmurun.S uses, and drives it through MMU_TTB
!     (0xFF000008) exactly as switch_mm()/set_TTB() would.
!
! ---------------------------------------------------------------------------
! Linux 2-level page table layout used here (PAGE_SHIFT=14, 16 KB pages):
!   PTE_MAGNITUDE = 2 (4-byte ptes)         PTE_BITS = 14+2 = ... no:
!   PTE_BITS = PTE_SHIFT + PTE_MAGNITUDE = 14 + 2 = 16? -- NO: see
!   pgtable-2level.h: PTE_BITS = (PAGE_SHIFT - PTE_MAGNITUDE) is NOT the
!   formula either. Trust the actual header (included below) instead of
!   restating the arithmetic in a comment; the concrete indices used by
!   this harness are:
!     pgd_index(VA)  = (VA >> 26) & 0xFFF   (PGDIR_SHIFT = 26 for 16K pages)
!     pte_index(VA)  = (VA >> 14) & 0xFFF   (PAGE_SHIFT  = 14)
!   pgd[pgd_index] must hold the PAGE-ALIGNED *virtual* (P1) address of the
!   pte table (pmd_page_vaddr() returns pmd_val() verbatim -- no pfn/__va()
!   indirection -- see arch/sh/include/asm/pgtable_32.h). pte[pte_index]
!   holds a real Linux pte_t: PFN in bits 31:14, hw/sw flag bits in 13:0
!   per arch/sh/include/asm/pgtable-bits-jcore.h (#included below).
!
! Memory map chosen for this harness (all P1 addresses are 0x80000000 |
! the physical offset shown; the workload VA (0x00100000) is a genuine P0
! address, translated by the walker):
!
!   0x00020000  PGD table       (16 KB, P1 0x80020000)
!   0x00024000  PTE table       (16 KB, P1 0x80024000)  -- covers pgd[0]
!   0x00028000  TSB             (256 B, P1 0x80028000)
!   0x00030000  stack           (P1 0x80030000, SP set near top)
!   0x00040000  backing page    (16 KB, physical; the PTE's PFN)
!   0x00100000  workload VA     (P0; pgd_index=0, pte_index=0x40)
!
! Scenario 1 (walk + install): with MMUCR.AT enabled, touch the mapped P0
! VA with a load. It TLB-misses (no HW entry yet) at VBR+0x420
! (jcore_vec_dload, ex.o); the inlined JCORE_TLB_FASTPATH TSB probe misses
! (TSB was zeroed), so it falls to jcore_tlb_miss_slow, which calls the
! REAL __jcore_tlb_walk(pgd, addr, asid_tag). The walker finds our pte,
! builds the PTEL image, LDC's it into PTEL, rewrites the TSB slot, and
! returns 0; jcore_tlb_miss_slow then executes LDTLB.RN and the faulting
! load resumes and completes.
!
! Assertions (distinct r9 fail codes so a regression is diagnosable):
!   r9=1  the resumed load's value != what the harness wrote to the
!         backing PA directly (translation did not actually happen, or
!         landed on the wrong PA)
!   r9=2  TSB slot tag_hi (VPN) != the workload VA (walker did not run /
!         did not install into the TSB)
!   r9=3  TSB slot tag_lo (ASID_TAG) != 0
!   r9=4  TSB slot data (PTEL image) != the expected PTEL encoding (wrong
!         data installed -- proves jcore_pte_to_ptel() ran, not just "some
!         install happened")
!   r9=5  scenario 2 (warm TSB hit): resumed load's value != harness seed
!         after a TI flush + re-touch (translation lost/corrupted)
!   r9=6  scenario 2: walker-invocation counter changed across the warm
!         re-touch (the TSB-hit fast path should have installed via
!         LDTLB.RN directly -- __jcore_tlb_walk() must NOT have run)
!   r9=7  scenario 3 (ASID isolation): resumed load's value != harness seed
!         after switching ASIDR and re-walking under the new ASID
!   r9=8  scenario 3: walker-invocation counter did NOT increment across
!         the ASID switch (a cross-ASID TSB hit would wrongly skip the
!         walker -- tag_lo must be checked against the live ASIDR)
!   r9=99 do_page_fault() was reached (the walker treated our present,
!         valid pte as not-present -- a real fault when none was expected)
!
! do_page_fault() itself is stubbed for Task 1 (a fixed record+halt); Task 3
! fills in its real pt_regs-based body for the true-fault scenarios.
! jcore_tlb_walk_mark_accessed() IS stubbed from Task 2 on: a STRONG
! definition near the bottom of this file shadows tlb-jcore.o's __weak
! default so scenarios 2-3 get a walker-invocation counter (see that
! function's comment for why this gives an unambiguous signal).

#include "sim_instr.h"
#include <asm/pgtable-bits-jcore.h>
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
        ! ---- Relocate SP into P1 and jump to the P1 alias of kmain, so
        ! ALL harness code/stack/page-table accesses are untranslated once
        ! MMUCR.AT is enabled below (mirrors mmurun.S's kmain trampoline). --
        mov.l   p_sp,    r15           ! r15 = 0x80030F00 (P1 stack)
        mov.l   p_kmain, r0            ! r0  = 0x80000000 + kmain
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x80030F00
p_kmain: .long 0x80000000 + kmain

kmain:
        ! ---- Ensure RB=0 (keep MD=1). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        ! ---- Initialise PR (first-fault store-of-uninitialised-PR guard;
        ! see mmurun.S's identical comment -- the slow path does
        ! sts.l pr,@-r15 on entry). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- Initialise the caller-saved GPRs the fault handlers push on
        ! entry before defining them: jcore_tlb_miss_slow saves r4-r7 (and
        ! pr, above); __jcore_tlb_walk saves r8-r10. At the very first fault
        ! these are otherwise undefined, and the ghdl SRAM bus model rejects
        ! an undefined-data store (mov.l rN,@-r15 -> "invalid write data:
        ! UUUU"), hanging the sim. Same rationale as the PR guard above.
        !
        ! CRITICAL: exception entry sets SR.RB=1, so the handlers run against
        ! register BANK 1. r0-r7 are banked, so bank-1 r4-r7 (what the slow
        ! path actually pushes) must be zeroed with RB=1 -- zeroing them in
        ! bank 0 here would not define them. r8-r10 are common (unbanked), so
        ! one zero covers both banks. ----
        mov.l   p_rbset,  r8            ! r8/r9 common: survive the bank flip
        mov.l   p_rbclear, r9
        stc     sr, r0 ; or  r8, r0 ; ldc r0, sr    ! -> RB=1 (bank 1)
        nop ; nop
        mov     #0, r0 ; mov #0, r1 ; mov #0, r2 ; mov #0, r3
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7
        stc     sr, r0 ; and r9, r0 ; ldc r0, sr    ! -> RB=0 (bank 0)
        nop ; nop
        mov     #0, r4                  ! bank-0 GPRs too (tidy caller state)
        mov     #0, r5
        mov     #0, r6
        mov     #0, r7
        mov     #0, r8
        mov     #0, r9
        mov     #0, r10

        ! ---- ASIDR = 0 (single context for scenarios 1-2; scenario 3
        ! switches ASIDR itself). ----
        mov     #0, r0
        ldc     r0, asidr
        nop
        nop

        ! ---- Zero the walker-invocation counter (bumped by our own
        ! strong jcore_tlb_walk_mark_accessed() override below, which
        ! shadows tlb-jcore.o's __weak default). ----
        mov.l   k_wcnt, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Build pgd[0] -> pte table (P1 pointer, page-aligned; this is
        ! EXACTLY what pmd_page_vaddr()/pte_offset_kernel() expect -- a raw
        ! virtual pointer, no pfn encoding). ----
        mov.l   k_pgd,   r0
        mov.l   k_ptetbl, r1
        mov.l   r1, @r0

        ! ---- Build the one real Linux pte we need: PFN(backing PA) |
        ! V|C|U|W|D. Uses the actual _PAGE_* bits from
        ! asm/pgtable-bits-jcore.h, not a hand-rolled encoding. ----
        mov.l   k_pte,   r0
        mov.l   v_pte,   r1
        mov.l   r1, @r0

        ! ---- Zero the TSB (64 words, matches mmurun.S's TSB sizing). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed the backing page directly (P1, untranslated) with a
        ! known value; the resumed P0 load must read this back. ----
        mov.l   k_backing, r0
        mov.l   v_seed,    r1
        mov.l   r1, @r0

        ! ---- Point MMU_TTB at our pgd (raw P1 pointer -- __jcore_tlb_walk
        ! dereferences it directly, no __va() indirection). ----
        mov.l   k_ttb_a, r0 ; mov.l k_pgd, r1 ; mov.l r1, @r0

        ! ---- VBR = P1 alias of the REAL jcore_vbr_base (ex.o). ----
        mov.l   k_vbr, r0
        ldc     r0, vbr
        nop
        nop

        ! ---- TSB config registers via MMIO (mirrors mmurun.S). ----
        mov.l   k_tsbbr_a,  r0 ; mov.l v_tsbbr,  r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0
        nop
        nop

        ! ================= SCENARIO 1: walk + install =================
        mov.l   va_A, r0
        mov.l   @r0, r8                 ! load -> TLB miss -> VBR+0x420 ->
                                         ! TSB miss -> __jcore_tlb_walk()
                                         ! installs -> resumed load completes

        ! ---- Disable AT before touching sim result / TSB readback (plain
        ! P1 memory reads from here on). ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ================= VERIFY =================
        mov.l   v_seed, r1 ; cmp/eq r1, r8 ; mov #1, r9 ; bf _fail

        ! __jcore_tlb_walk() writes the TSB entry at the hardware-computed
        ! slot address it reads back from TSBPTR (jcore_read_tsbptr()), i.e.
        ! TSB_base + hash(VPN) -- NOT necessarily slot 0. For va_A this is
        ! k_tsb+0x40, so read the entry through TSBPTR (still holding va_A's
        ! slot -- no fault has occurred since). AT is off, but STC TSBPTR
        ! reads the MMU register regardless. Keep the slot ptr in r3. ----
        stc     tsbptr, r3

        mov.l   @r3, r2                 ! tag_hi (VPN)
        mov.l   va_A, r1
        cmp/eq  r1, r2 ; mov #2, r9 ; bf _fail

        mov.l   @(4, r3), r2           ! tag_lo (ASID_TAG)
        mov     #0, r1
        cmp/eq  r1, r2 ; mov #3, r9 ; bf _fail

        mov.l   @(8, r3), r2           ! data (PTEL image)
        mov.l   v_ptel_expect, r1
        cmp/eq  r1, r2 ; mov #4, r9 ; bf _fail

        ! ================= SCENARIO 2: warm TSB hit (no re-walk) =================
        ! Scenario 1's walk already wrote the ACCESSED bit into k_pte's live
        ! image (mark_accessed override below always fires when it sees the
        ! bit unset -- see the override's comment). Clear it again here so
        ! that IF the TLB miss wrongly falls to the slow path this time, the
        ! walker will unconditionally re-set it and our counter will catch
        ! it; a genuine TSB hit never looks at this pte at all, so clearing
        ! it is a no-op for the expected (hit) outcome. ----
        mov.l   k_pte, r0
        mov.l   @r0, r1
        mov.l   v_accessed_clr, r2
        and     r2, r1
        mov.l   r1, @r0

        ! ---- Flush the TLB (TI), keep AT on -- TSB stays warm. ----
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0

        mov.l   va_A, r0
        mov.l   @r0, r8                 ! re-touch: TLB miss -> ex.S inlined
                                         ! JCORE_TLB_FASTPATH TSB probe HITS
                                         ! (VPN+ASID_TAG match) -> LDTLB.RN
                                         ! directly, __jcore_tlb_walk() never
                                         ! called this time.

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        mov.l   v_seed, r1 ; cmp/eq r1, r8 ; mov #5, r9 ; bf _fail   ! translation still correct

        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #1, r3
        cmp/eq  r3, r2 ; mov #6, r9 ; bf _fail                       ! walker must NOT have run

        ! ================= SCENARIO 3: ASID isolation =================
        ! va_A's TSB slot currently carries tag_lo (ASID_TAG) == 0, the
        ! ASIDR value scenarios 1-2 ran under ("ASID A"). Switch to a
        ! different ASID ("ASID B"), flush the TLB, and touch va_A again:
        ! the TSB tag_lo compare must MISS (no cross-ASID hit), forcing a
        ! real re-walk under the new ASID_TAG.
        mov     #1, r0
        ldc     r0, asidr
        nop                             ! ASIDR write-to-use hazard
        nop                             ! (scenario-1 finding: 2-nop workaround)

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! flush TLB, AT stays on

        mov.l   va_A, r0
        mov.l   @r0, r8                 ! TSB tag_lo(0) != ASIDR(1) -> fast
                                         ! path misses -> jcore_tlb_miss_slow
                                         ! -> __jcore_tlb_walk() re-walks and
                                         ! reinstalls under the new ASID_TAG.

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        mov.l   v_seed, r1 ; cmp/eq r1, r8 ; mov #7, r9 ; bf _fail   ! same PA, still readable

        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #2, r3
        cmp/eq  r3, r2 ; mov #8, r9 ; bf _fail                       ! walker MUST have re-run

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000        ! SR.RB bit (bank select)
k_pgd:          .long 0x80020000
k_ptetbl:       .long 0x80024000
k_pte:          .long 0x80024100        ! pte_index(0x00100000) = 0x40 -> +0x100
v_pte:          .long 0x000400B9        ! PFN(0x00040000) | V|C|U|W|D (0x1|0x8|0x20|0x80|0x10)
k_tsb:          .long 0x80028000
k_backing:      .long 0x80040000
v_seed:         .long 0xC0FFEE00
k_ttb_a:        .long 0xFF000008        ! MMU_TTB
k_vbr:          .long 0x80000000 + jcore_vbr_base
k_tsbbr_a:      .long 0xFF000014        ! TSBBR
v_tsbbr:        .long 0x80028004
k_tsbcfg_a:     .long 0xFF000018        ! TSBCFG
v_tsbcfg:       .long 0x00000061
k_mmucr:        .long 0xFF000010        ! MMUCR
va_A:           .long 0x00100000
v_ptel_expect:  .long 0x000401B9        ! PFN(0x00040000)|PageMask(16K,0x100)|V|C|U|W|D
k_wcnt:         .long 0x80029000        ! walker_calls counter (past TSB/before stack)
v_accessed_clr: .long 0xFFFFFEFF        ! ~_PAGE_ACCESSED (0x100), see pgtable-bits-jcore.h

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
! symbols (SP2 Task 0's stub set; do_page_fault gets a real body in Task 3).
! ===========================================================================

! do_page_fault(regs, error_code, address) -- Task 1: never expected to be
! reached (our one pte is present and valid); if it IS reached, record a
! distinct code and halt rather than let entry.S's rte resume into a fault
! loop.
ENTRY(do_page_fault)
        mov.l   p_test_result2, r0
        mov     #99, r9
        mov.l   r9, @r0
1:      bra     1b
        nop
        .align 2
p_test_result2: .long TEST_RESULT_ADDRESS

! exception_handler -- generic (non-TLB) exception dispatch; scenario 1
! never takes a TRAPA/general exception.
ENTRY(exception_handler)
        rts
        nop

! arch_local_irq_restore(flags) / arch_local_save_flags() -- referenced by
! tlb-jcore.o's __update_tlb() (not exercised by the miss path scenario 1
! drives); never actually called here.
ENTRY(arch_local_irq_restore)
        rts
        nop
ENTRY(arch_local_save_flags)
        mov     #0, r0
        rts
        nop

! jcore_tlb_walk_mark_accessed(pte_t *ptep, pte_t entry) -- Task 2: this
! STRONG definition shadows tlb-jcore.o's __weak default (mmulinux.o links
! first, see sim/tests/Makefile) so scenarios 2-3 get an unambiguous
! walker-invocation counter: __jcore_tlb_walk() only calls this when it
! finds the pte's _PAGE_ACCESSED bit unset (tlb-jcore.c comment), so the
! harness clears that bit by hand before each "must re-walk" check to make
! every real walker invocation observable here, and leaves it alone before
! each "must NOT re-walk" (TSB-hit) check, where a genuine hit never reaches
! this function at all. r4 = ptep, r5 = entry (32-bit scalar pte_t, non-PAE).
ENTRY(jcore_tlb_walk_mark_accessed)
        mov.l   p_wcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   r5, @r4                 ! set_pte(ptep, entry)
        rts
        nop
        .align 2
p_wcnt: .long 0x80029000               ! same address as k_wcnt below --
                                        ! duplicated locally because mov.l
                                        ! is PC-relative-forward-only and
                                        ! k_wcnt's data-section slot is
                                        ! behind (earlier than) this function
