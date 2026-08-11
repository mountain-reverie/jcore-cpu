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
! VA with a load. It TLB-misses (no HW entry yet) at VBR+0x400
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
!   r9=99 do_page_fault() was reached unexpectedly (scenarios 1-3: the
!         walker treated our present, valid pte as not-present -- a real
!         fault when none was expected)
!   r9=10 scenario 4 (fault path, not-present pte): fault-count global did
!         not read back as exactly 1 (do_page_fault() not reached, or
!         reached more than once)
!   r9=11 scenario 4: do_page_fault()'s captured faulting address != VA_B
!         (real jcore_tlb_fault_entry passed the wrong MMU_TEA readback,
!         or the stub mis-recorded it)
!   r9=12 scenario 4: VA_B's TSB slot tag_hi == VA_B (a translation WAS
!         installed for a faulting access -- __jcore_tlb_walk() must
!         return before any TSB/PTEL write on the not-present path)
!   r9=13 scenario 5 (STALE pte): fault-count global did not read back as
!         exactly 2 (do_page_fault() not reached exactly once more)
!   r9=14 scenario 5: captured faulting address != VA_C
!   r9=15 scenario 5: VA_C's TSB slot tag_hi == VA_C (translation WAS
!         installed despite _PAGE_STALE -- walker must fault, not install)
!   r9=16 scenario 6 (ASID generation tagging): resumed load's value !=
!         harness seed for VA_D (initial gen0 install), OR the TSB slot's
!         tag_lo != the live (gen1) ASIDR after the cross-generation
!         re-touch (a stale gen0 tag surviving would mean a false-hit risk
!         -- security-review S-I3)
!   r9=17 scenario 6: walker-invocation counter did NOT change across the
!         ASIDR generation bump (same 12-bit ASID, gen_low 0->1) -- the
!         TSB fast-path tag_lo compare must treat this as a miss and force
!         a real re-walk, exactly like scenario 3's cross-ASID case
!   r9=18 scenario 7 (write-protect fault, REAL entry.S prologue): fault-
!         count global did not read back as exactly 3 (do_page_fault() not
!         reached exactly once more for VA_E's store)
!   r9=19 scenario 7: k_faultcode (error_code as REAL entry.S/do_page_fault
!         built it from r5, NOT the harness) != (FAULT_CODE_PROT|
!         FAULT_CODE_WRITE) == 0x09 -- proves entry.S reads MMU_FSR and
!         extu.b's it into r5, rather than the old `mov #0, r5` gap
!   r9=20 scenario 7: captured faulting address != VA_E (confirms the rest
!         of the shipped prologue is otherwise intact)
!   r9=21 scenario 8 (TSB invalidation on TLB flush): do_page_fault() was
!         reached a SECOND time for VA_F's store. The first episode's
!         handler already set _PAGE_DIRTY and called the REAL
!         local_flush_tlb_all(); if the store still faults after that, the
!         flush invalidated only the hardware TLB and left the stale
!         read-only slot live in the software TSB, so the fast path
!         reinstalls it forever -- the C1 livelock. THIS is the code the
!         guard reports when the tlb-jcore.c TSB-memset fix is absent.
!   r9=22 scenario 8: fault-count global did not read back as exactly 4
!         (VA_F's store must cost exactly ONE do_page_fault episode on
!         top of scenarios 4/5/7's three)
!   r9=23 scenario 8: VA_F's backing page does not hold the stored value --
!         the store "completed" without actually writing through
!
! do_page_fault() has a real body from Task 3/SP2 scenarios 4-5: records a
! fault-count + faulting address into scratch globals, restores SR.RB=0
! and the harness SP (captured just before the faulting touch), then
! JUMPS (never rts/rte) to a per-scenario target address held in a
! scratch global -- the mapping is never fixed up, so returning through
! entry.S's rte would just re-fault forever. Scenarios 1-3 point that
! target at `unexpected_fault` (== the old Task-1 stub behavior: record
! r9=99, halt) since they expect zero faults.
! jcore_tlb_walk_mark_accessed() IS stubbed from Task 2 on: a STRONG
! definition near the bottom of this file shadows tlb-jcore.o's __weak
! default so scenarios 2-3 get a walker-invocation counter (see that
! function's comment for why this gives an unambiguous signal).

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
p_sp:    .long 0x80030F00
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
        mov     #0, r11                 ! r11-r14: unbanked, never touched by
        mov     #0, r12                 ! scenarios 1-3 (no real fault taken),
        mov     #0, r13                 ! but jcore_tlb_fault_entry (scenarios
        mov     #0, r14                 ! 4-5) DOES push them into pt_regs --
                                         ! must be defined or the SRAM model
                                         ! rejects the store (undefined data).

        ! ---- ASIDR = 0 (single context for scenarios 1-2; scenario 3
        ! switches ASIDR itself). ----
        mov     #0, r0
        ldc     r0, asidr
        nop
        nop

        ! ---- GBR = 0. Never otherwise touched by this harness, but
        ! jcore_tlb_fault_entry (scenarios 4-5) unconditionally saves it
        ! into pt_regs via `stc gbr,r1` -- undefined at reset, so that
        ! store trips the SRAM model's undefined-write-data check. ----
        mov     #0, r0
        ldc     r0, gbr
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

        ! ---- Scenario 4/5 ptes: VA_B not-present (all-zero), VA_C
        ! present+valid but _PAGE_STALE. Same pgd[0]/pte-table range as
        ! va_A (different pte_index), so no extra pgd entry is needed. ----
        mov.l   k_pte_b, r0
        mov.l   v_pte_b, r1
        mov.l   r1, @r0
        mov.l   k_pte_c, r0
        mov.l   v_pte_c, r1
        mov.l   r1, @r0

        ! ---- Scenario 6 pte: VA_D present+valid, no STALE (own backing
        ! page/PFN, distinct from va_A's). Same pgd[0]/pte-table range. ----
        mov.l   k_pte_d, r0
        mov.l   v_pte_d, r1
        mov.l   r1, @r0

        ! ---- Scenario 7 pte: VA_E present+valid, read-only (W clear).
        ! Same pgd[0]/pte-table range. ----
        mov.l   k_pte_e, r0
        mov.l   v_pte_e, r1
        mov.l   r1, @r0

        ! ---- Scenario 8 pte: VA_F present+valid, WRITABLE in the Linux pte
        ! but CLEAN (_PAGE_DIRTY clear), so jcore_pte_to_ptel() withholds
        ! PTEL.W and the first store must trap. Same pgd[0]/pte-table
        ! range. ----
        mov.l   k_pte_f, r0
        mov.l   v_pte_f, r1
        mov.l   r1, @r0

        ! ---- Zero the do_page_fault handshake globals; point the fault
        ! target at `unexpected_fault` (scenarios 1-3 expect zero faults --
        ! same behavior the old Task-1 stub had: record r9=99 and halt). ----
        mov.l   k_faultcnt, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   k_fault_target, r0
        mov.l   unexpected_fault_ptr, r1
        mov.l   r1, @r0

        ! ---- Zero the TSB (16 sets x 32 bytes => 128 words, matches mmurun.S). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        shll    r2                      ! 2-way sets: 32 B/set => 128 words
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

        ! ---- Seed scenario 6's own backing page (distinct PFN/value from
        ! va_A's, so its readback is unambiguous). ----
        mov.l   k_backing_d, r0
        mov.l   v_seed_d,    r1
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
        mov.l   @r0, r8                 ! load -> TLB miss -> VBR+0x400 ->
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
        ! slot -- no fault has occurred since). AT is off, and the P4
        ! TSBPTR alias is untranslated regardless. Keep the slot ptr in r3. ----
        mov.l   k_tsbptr_a, r3
        mov.l   @r3, r3None

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

        ! ================= SCENARIO 4: fault path (not-present pte) =========
        ! VA_B's pte word is all-zero (no _PAGE_VALID). Touch VA_B under AT:
        ! real __jcore_tlb_walk() sees !_PAGE_VALID -> returns -EFAULT ->
        ! jcore_tlb_miss_slow falls through to the real fault tail
        ! (jcore_tlb_real_fault -> jcore_tlb_fault_entry, now fetchable
        ! under AT since the whole image links at P1) -> our do_page_fault
        ! body records fault-count + address, restores SR.RB=0 and SP, and
        ! JUMPS to s4_assert (see the do_page_fault comment below for why
        ! it never rts/rte).
        mov.l   k_saved_sp, r0
        mov.l   r15, @r0
        mov.l   k_fault_target, r0
        mov.l   s4_assert_ptr, r1
        mov.l   r1, @r0

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! flush TLB (fresh miss)

        mov.l   va_B, r0
        mov.l   @r0, r8                 ! faulting load -> TLB miss -> walker
                                         ! -EFAULT -> real fault tail -> stub

        ! Expected path never falls through to here (the stub jumps to
        ! s4_assert instead); if it does, the fault tail was never taken.
        mov     #90, r9
        bra     _fail
        nop
        .align 2
s4_assert_ptr:  .long s4_assert
s4_assert:
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   k_faultcnt, r0
        mov.l   @r0, r1
        mov     #1, r2
        cmp/eq  r2, r1 ; mov #10, r9 ; bf _fail             ! fault not recorded exactly once

        mov.l   k_faultaddr, r0
        mov.l   @r0, r1
        mov.l   va_B, r2
        cmp/eq  r2, r1 ; mov #11, r9 ; bf _fail             ! captured address != VA_B

        mov.l   k_tsbptr_a, r3
        mov.l   @r3, r3None
        mov.l   @r3, r2                 ! tag_hi at VA_B's TSB slot
        mov.l   va_B, r1
        cmp/eq  r1, r2 ; mov #12, r9 ; bt _fail             ! translation WAS installed

        ! ================= SCENARIO 5: STALE pte =============================
        ! VA_C's pte is otherwise valid+present but carries _PAGE_STALE
        ! (0x002). The walker's `pte_val(entry) & (_PAGE_PROTNONE|_PAGE_STALE)`
        ! check must still fault it -- same fault-tail path as scenario 4.
        mov.l   k_saved_sp, r0
        mov.l   r15, @r0
        mov.l   k_fault_target, r0
        mov.l   s5_assert_ptr, r1
        mov.l   r1, @r0

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! AT on + flush TLB

        mov.l   va_C, r0
        mov.l   @r0, r8                 ! faulting load -> walker sees STALE
                                         ! -> -EFAULT -> fault tail -> stub

        mov     #91, r9
        bra     _fail
        nop
        .align 2
s5_assert_ptr:  .long s5_assert
s5_assert:
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        mov.l   k_faultcnt, r0
        mov.l   @r0, r1
        mov     #2, r2
        cmp/eq  r2, r1 ; mov #13, r9 ; bf _fail             ! fault-count not exactly 2

        mov.l   k_faultaddr, r0
        mov.l   @r0, r1
        mov.l   va_C, r2
        cmp/eq  r2, r1 ; mov #14, r9 ; bf _fail             ! captured address != VA_C

        mov.l   k_tsbptr_a, r3
        mov.l   @r3, r3None
        mov.l   @r3, r2                 ! tag_hi at VA_C's TSB slot
        mov.l   va_C, r1
        cmp/eq  r1, r2 ; mov #15, r9 ; bt _fail             ! translation WAS installed

        ! ================= SCENARIO 6: ASID generation tagging (S-I3) ========
        ! VA_D is a fresh mapped page (present+valid, no STALE) never touched
        ! by scenarios 1-5. Install its translation under ASIDR=gen0 (12-bit
        ! ASID X, gen_low=0), then advance ASIDR to gen1 (SAME 12-bit ASID X,
        ! gen_low=0->1) and re-touch: the TSB fast-path's tag_lo compare
        ! (core/tlb.vhd ASID_TAG[15:12] generation field) must MISS despite
        ! the low 12 ASID bits being identical, forcing a real re-walk. This
        ! proves generation-tagging rejects a stale cross-generation TSB
        ! entry instead of a false ASID-recycling hit.
        !
        ! ---- Reset the fault target: scenario 6 expects zero faults (VA_D
        ! is present+valid), same discipline as scenarios 1-3. ----
        mov.l   k_fault_target, r0
        mov.l   unexpected_fault_ptr, r1
        mov.l   r1, @r0

        ! ---- ASIDR = gen0 (12-bit ASID X, gen_low=0). ----
        mov.l   k_asidr_gen0, r0
        ldc     r0, asidr
        nop                             ! ASIDR write-to-use hazard
        nop

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! flush TLB, AT on

        mov.l   va_D, r0
        mov.l   @r0, r8                 ! TLB miss -> TSB miss (fresh VA) ->
                                         ! __jcore_tlb_walk() installs under
                                         ! ASID_TAG = gen0

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   v_seed_d, r1 ; cmp/eq r1, r8 ; mov #16, r9 ; bf _fail
                                         ! initial gen0 translation wrong

        mov.l   k_wcnt, r0 ; mov.l @r0, r4   ! r4 = wcnt baseline (post gen0 walk)

        ! ---- ASIDR = gen1 (SAME 12-bit ASID X, gen_low 0->1). The TSB slot
        ! installed above still carries tag_lo = gen0's ASIDR value; the
        ! generation bump must make the fast-path tag_lo compare MISS even
        ! though the low 12 ASID bits are unchanged. ----
        mov.l   k_asidr_gen1, r0
        ldc     r0, asidr
        nop
        nop

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! flush TLB, AT on

        mov.l   va_D, r0
        mov.l   @r0, r8                 ! re-touch under new generation: TSB
                                         ! tag_lo(gen0) != ASIDR(gen1) -> fast
                                         ! path MUST miss -> real re-walk

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   k_wcnt, r0 ; mov.l @r0, r5
        cmp/eq  r4, r5 ; mov #17, r9 ; bt _fail
                                 ! walker did NOT re-run for the new generation

        mov.l   k_tsbptr_a, r3
        mov.l   @r3, r3None
        mov.l   @(4, r3), r2            ! tag_lo (ASID_TAG) at VA_D's TSB slot
        mov.l   k_asidr_gen1, r1
        cmp/eq  r1, r2 ; mov #16, r9 ; bf _fail
                         ! stale gen0 tag retained -- false-hit risk (S-I3)

        mov.l   v_seed_d, r1 ; cmp/eq r1, r8 ; mov #16, r9 ; bf _fail
                                 ! translation after generation bump wrong/stale

        ! ================= SCENARIO 7: write-protect fault (REAL entry.S) ====
        ! VA_E's pte is present+valid but read-only (PTEL W clear). Storing
        ! to it takes a real DPROT_W through the REAL linux@jcore entry.S
        ! prologue (arch/sh/kernel/cpu/jcore/entry.S), which now reads
        ! MMU_FSR and extu.b's it into r5 before calling do_page_fault --
        ! this is the gap a stubbed/hand-rolled prologue could never catch.
        mov.l   k_saved_sp, r0
        mov.l   r15, @r0
        mov.l   k_fault_target, r0
        mov.l   s7_assert_ptr, r1
        mov.l   r1, @r0

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! flush TLB, AT on

        mov.l   va_E, r0
        mov.l   r0, @r0                 ! faulting store -> DPROT_W -> real
                                         ! entry.S -> real do_page_fault stub

        mov     #92, r9
        bra     _fail
        nop
        .align 2
s7_assert_ptr:  .long s7_assert
s7_assert:
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   k_faultcnt, r0
        mov.l   @r0, r1
        mov     #3, r2
        cmp/eq  r2, r1 ; mov #18, r9 ; bf _fail             ! fault-count not exactly 3

        mov.l   k_faultcode, r0
        mov.l   @r0, r1
        mov     #0x09, r2
        cmp/eq  r2, r1 ; mov #19, r9 ; bf _fail             ! error_code != (PROT|WRITE)

        mov.l   k_faultaddr, r0
        mov.l   @r0, r1
        mov.l   va_E, r2
        cmp/eq  r2, r1 ; mov #20, r9 ; bf _fail             ! captured address != VA_E

        ! ================= SCENARIO 8: TSB invalidation on TLB flush ========
        ! The C1 guard. Everything above runs ONE fault episode per scenario
        ! against a do_page_fault stub that never repairs the mapping, so
        ! none of them can observe what happens on the SECOND touch of a page
        ! whose pte was fixed and whose TLB was then flushed. That is exactly
        ! where the software TSB and the hardware TLB can diverge:
        ! MMUCR.TI invalidates only the hardware TLB, while the ex.S fast
        ! path treats a TSB hit as authoritative and reinstalls it with
        ! LDTLB.RN without re-reading the page table.
        !
        ! VA_F is present+valid and writable in the Linux pte but CLEAN, so
        ! jcore_pte_to_ptel() withholds PTEL.W. Sequence:
        !
        !   episode 1: store -> DMISS_W -> TSB miss -> real
        !              __jcore_tlb_walk() installs a READ-ONLY entry AND
        !              writes that read-only PTEL into the TSB slot ->
        !              store retries -> DPROT_W -> real entry.S ->
        !              do_page_fault stub -> s8_ep1.
        !   s8_ep1:    models the kernel's repair: sets _PAGE_DIRTY in the
        !              pte (what handle_mm_fault/ptep_set_access_flags does)
        !              and then calls the REAL local_flush_tlb_all() out of
        !              tlb-jcore.o -- not a hand-rolled MMUCR.TI strobe, so
        !              the fix under test is the one actually shipped -- and
        !              RTEs back to the store.
        !   episode 2: MUST NOT HAPPEN. With the TSB left stale, the retried
        !              store takes DMISS_W, hits the stale W=0 slot,
        !              reinstalls read-only, takes DPROT_W, and loops
        !              forever. s8_ep2 catches that as r9=21 instead of
        !              hanging the simulation.
        !
        ! So: fails with Result=21 without the tlb-jcore.c fix, passes with
        ! it, and the store completing at all is the termination proof
        ! scenario 7 could not give.
        mov.l   k_saved_sp, r0
        mov.l   r15, @r0
        mov.l   k_fault_target, r0
        mov.l   s8_ep1_ptr, r1
        mov.l   r1, @r0

        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! flush TLB, AT on

        mov.l   va_F, r0
        mov.l   r0, @r0                 ! episode 1; re-executed by s8_ep1's
                                         ! RTE and required to COMPLETE then.
                                         ! r0 is re-established by s8_ep1
                                         ! before the RTE (the fault path
                                         ! clobbers bank-0 r0-r7).

        ! ---- Reached only when the store finally retires. ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off for readback

        mov.l   k_faultcnt, r0
        mov.l   @r0, r1
        mov     #4, r2
        cmp/eq  r2, r1 ; mov #22, r9 ; bf _fail             ! fault-count not exactly 4

        mov.l   k_backing_f, r0
        mov.l   @r0, r1
        mov.l   va_F, r2
        cmp/eq  r2, r1 ; mov #23, r9 ; bf _fail             ! store did not write through

        mov     #0, r9
        bra     _done
        nop

        .align 2
s8_ep1_ptr:     .long s8_ep1

! Episode-1 fault handler (jumped to by the do_page_fault stub, SR.RB
! already 0 and r15 already restored to the harness stack). Repairs the
! pte, flushes via the real kernel routine, arms the second-episode trap,
! then resumes the faulting store. SPC/SSR still hold the store's restart
! PC and its SR (RB=0), untouched by entry.S/do_page_fault, so RTE lands
! back on the store. local_flush_tlb_all() is plain SH ABI and preserves
! r8-r15, so the harness's r8/r9/r15 survive the call.
s8_ep1:
        mov.l   s8_k_pte_f, r0
        mov.l   @r0, r1
        mov     #0x10, r2               ! _PAGE_DIRTY (pgtable-bits-jcore.h)
        or      r2, r1
        mov.l   r1, @r0                 ! pte is now writable AND dirty

        mov.l   s8_k_fault_target, r0   ! any further episode is a failure
        mov.l   s8_ep2_ptr, r1
        mov.l   r1, @r0

        mov.l   s8_p_lfta, r0
        jsr     @r0                     ! REAL local_flush_tlb_all()
        nop                              ! (tlb-jcore.o): MMUCR.TI strobe +
                                         ! the TSB memset that is the fix

        mov.l   s8_va_F, r0             ! re-establish the store's operand
        rte
        nop

! Second do_page_fault episode for VA_F == the C1 livelock. Reported, not
! looped, so the failure is a deterministic Result=21 rather than a
! stop-time timeout.
s8_ep2:
        mov     #21, r9
        bra     _fail
        nop

        .align 2
s8_k_pte_f:       .long 0x80024114      ! == k_pte_f  (duplicated: mov.l is
s8_k_fault_target:.long 0x8002900C      ! == k_fault_target   PC-relative
s8_ep2_ptr:       .long s8_ep2          !                     forward-only)
s8_p_lfta:        .long local_flush_tlb_all
s8_va_F:          .long 0x00114000      ! == va_F

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000        ! SR.RB bit (bank select)
k_pgd:          .long 0x80020000
k_ptetbl:       .long 0x80024000
k_pte:          .long 0x80024100        ! pte_index(0x00100000) = 0x40 -> +0x100
v_pte:          .long 0x000400B9        ! PFN(0x00040000) | V|C|U|W|D (0x1|0x8|0x20|0x80|0x10)
k_tsb:          .long 0x80028000        ! == jcore_boot_tsb (see the equate below)
k_backing:      .long 0x80040000
v_seed:         .long 0xC0FFEE00
k_ttb_a:        .long 0xFF000008        ! MMU_TTB
k_vbr:          .long jcore_vbr_base
k_tsbbr_a:      .long 0xFF000014        ! TSBBR
v_tsbbr:        .long 0x80028004        ! jcore_boot_tsb | TSB_SIZE_LOG=4
k_tsbcfg_a:     .long 0xFF000018        ! TSBCFG
v_tsbcfg:       .long 0x00000061
k_mmucr:        .long 0xFF000010        ! MMUCR
va_A:           .long 0x00100000
v_ptel_expect:  .long 0x000401B9        ! PFN(0x00040000)|PageMask(16K,0x100)|V|C|U|W|D
k_wcnt:         .long 0x80029000        ! walker_calls counter (past TSB/before stack)
k_tsbptr_a:     .long 0xFF00001C        ! read-only P4 TSBPTR alias
v_accessed_clr: .long 0xFFFFFEFF        ! ~_PAGE_ACCESSED (0x100), see pgtable-bits-jcore.h

! ---- Scenario 4/5 scratch: extra ptes (same pgd[0]/pte-table range as
! va_A, different pte_index so no new pgd entry is needed), and the
! do_page_fault <-> harness handshake globals (fault-count/address/target
! jump-address/saved-SP), placed in the same scratch RAM region as k_wcnt.
va_B:           .long 0x00104000        ! pte_index 0x41 -> k_ptetbl+0x104
k_pte_b:        .long 0x80024104
v_pte_b:        .long 0x00000000        ! not present (_PAGE_VALID clear)
va_C:           .long 0x00108000        ! pte_index 0x42 -> k_ptetbl+0x108
k_pte_c:        .long 0x80024108
v_pte_c:        .long 0x000400BB        ! PFN(0x00040000)|V|C|U|W|D|STALE (0xB9|_PAGE_STALE(0x2))
k_faultcnt:     .long 0x80029004        ! do_page_fault-recorded fault count
k_faultaddr:    .long 0x80029008        ! do_page_fault-recorded faulting address
k_fault_target: .long 0x8002900C        ! address do_page_fault jumps to next
k_saved_sp:     .long 0x80029010        ! r15 snapshot restored by do_page_fault
k_faultcode:    .long 0x80029014        ! do_page_fault-recorded error_code (r5)
unexpected_fault_ptr: .long unexpected_fault

! ---- Scenario 6 scratch: a fresh mapped VA_D (present+valid, own backing
! page distinct from va_A's so its seed value is unambiguous) and the two
! ASIDR literals that differ ONLY in gen_low (bits [15:12]) -- same 12-bit
! ASID X (chosen as 2, distinct from scenario 1's ASID 0 and scenario 3's
! ASID 1) across both generations.
va_D:           .long 0x0010C000        ! pte_index 0x43 -> k_ptetbl+0x10C
k_pte_d:        .long 0x8002410C
v_pte_d:        .long 0x000440B9        ! PFN(0x00044000)|V|C|U|W|D
k_backing_d:    .long 0x80044000
v_seed_d:       .long 0xD00DFEED
k_asidr_gen0:   .long 0x00000002        ! ASID X=2, gen_low=0
k_asidr_gen1:   .long 0x00001002        ! ASID X=2, gen_low=1 (X | 0x1000)

! ---- Scenario 7 scratch: VA_E present+valid, read-only (PTEL X|U|C =
! 0x68, W clear), own backing page. A store must take a real DPROT_W
! (walker installs the read-only translation, hardware then traps the
! write against a present-but-non-writable TLB entry) through the REAL
! linux@jcore entry.S prologue, proving it builds error_code from MMU_FSR
! instead of the old `mov #0, r5`. ----
va_E:           .long 0x00110000        ! pte_index 0x44 -> k_ptetbl+0x110
k_pte_e:        .long 0x80024110
v_pte_e:        .long 0x00048069        ! PFN(0x00048000)|V|C|U|X (0x68|0x01), W clear
k_backing_e:    .long 0x80048000

! ---- Scenario 8 scratch: VA_F present+valid, USER, EXEC, CACHEABLE and
! _PAGE_WRITE set, but _PAGE_DIRTY CLEAR -- the clean-writable case
! jcore_pte_to_ptel() deliberately installs read-only so the first store
! traps (dirty-bit emulation; J4 has no hardware initial-page-write
! exception). Own backing page so the write-through check is unambiguous.
va_F:           .long 0x00114000        ! pte_index 0x45 -> k_ptetbl+0x114
k_pte_f:        .long 0x80024114
v_pte_f:        .long 0x0004C0E9        ! PFN(0x0004C000)|W|X|U|C|V, D and
                                        ! ACCESSED clear (0x80|0x40|0x20|0x8|0x1)
k_backing_f:    .long 0x8004C000

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
! symbols (SP2 Task 0's stub set; do_page_fault gets a real body in Task 3).
! ===========================================================================

! do_page_fault(regs, error_code, address) -- real body for SP2 scenarios
! 4-5. Entered by jcore_tlb_fault_entry's `jsr` with r4=regs, r5=error_code
! (always 0 today -- entry.S doesn't yet thread a real code through),
! r6=faulting address (MMU_TEA readback). SR.RB is still 1 (exception-
! entry bank) and r15 is this call's OWN pt_regs frame, not the harness's
! SP -- both must be restored before we can safely run harness code again.
!
! Never rts/rte back into entry.S: the fault is never actually fixed up
! here (no pte gets patched), so resuming the faulting load would just
! re-fault forever. Instead: record fault-count + address, restore
! SR.RB=0 and the harness's pre-touch SP, then JUMP to whatever address
! k_fault_target currently holds (scenarios 1-3: `unexpected_fault`;
! scenarios 4/5: that scenario's assert label).
ENTRY(do_page_fault)
        mov.l   dpf_faultcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   dpf_faultaddr, r0
        mov.l   r6, @r0
        mov.l   dpf_faultcode, r0
        mov.l   r5, @r0                 ! record error_code as entry.S built it

        ! ---- SR.RB=1 -> 0: harness code (incl. the assert target) runs
        ! against bank 0; entry.S never clears RB itself. ----
        mov.l   dpf_rbclear, r0
        stc     sr, r1
        and     r0, r1
        ldc     r1, sr
        nop
        nop

        ! ---- restore the harness SP captured just before the faulting
        ! touch (bank-0 r15 is unbanked/shared, so this is safe to do here
        ! even though the RB flip above only just took effect). ----
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
dpf_faultcode:  .long 0x80029014        ! == k_faultcode

! unexpected_fault -- scenarios 1-3 point k_fault_target here (they expect
! zero faults). Same behavior the original Task-1 do_page_fault stub had:
! record r9=99 and halt, rather than let anything resume into a fault loop.
ENTRY(unexpected_fault)
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
! jcore_handle_exception(regs, expevt) / do_IRQ(irq, regs) -- referenced by
! entry.o since J4 gained real handlers at VBR+0x100 and VBR+0x600. This
! harness never drives a general exception or an interrupt (mmulinuxexc does),
! so these only need to exist. Reaching one means a fault took a vector this
! harness did not expect, so spin rather than return into a bogus context.
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

! memset(s, c, n) / jcore_boot_tsb -- referenced by tlb-jcore.o's
! jcore_tsb_flush_on_generation() (ASID-generation wrap, S-I3) and, since
! the C1 fix, by local_flush_tlb_all() as well -- which scenario 8 DOES
! invoke for real. So neither is a link-only stub any more.
!
! jcore_boot_tsb must therefore BE the TSB the hardware is pointed at
! (TSBBR, k_tsb below), not a separate buffer: if the kernel memset()s one
! array while the MMU hashes into another, local_flush_tlb_all()'s TSB
! invalidation is a no-op here and scenario 8 would pass vacuously. Defined
! as an absolute symbol at k_tsb's address rather than a .bss array so
! there is exactly one TSB and the equality is stated, not hoped for. The
! kernel memsets JCORE_BOOT_TSB_BYTES (4096) from it; 0x80028000..0x80029000
! is reserved for that and ends exactly where the scratch globals (k_wcnt)
! begin.
        .globl  jcore_boot_tsb
jcore_boot_tsb = 0x80028000

! r4=s, r5=c, r6=n; returns s in r0 (SH memset ABI). Word-store fast path
! for the aligned case: the kernel's TSB memset is 4096 bytes and a
! byte-at-a-time loop costs ~25k cycles inside the 200us guard budget.
ENTRY(memset)
        mov     r4, r3                  ! save s
        extu.b  r5, r5
        mov     r4, r0
        or      r6, r0
        tst     #3, r0                  ! s and n both 4-aligned?
        bf      3f
        tst     r6, r6
        bt      2f
        mov     r5, r2                  ! splat c into all four bytes
        shll8   r2 ; or r5, r2
        mov     r2, r1
        shll16  r1 ; or r1, r2
1:      mov.l   r2, @r4
        add     #4, r4
        add     #-4, r6
        tst     r6, r6
        bf      1b
        bra     2f
        nop
3:      tst     r6, r6                  ! byte-at-a-time fallback
        bt      2f
        mov.b   r5, @r4
        add     #1, r4
        add     #-1, r6
        bra     3b
        nop
2:      mov     r3, r0
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
