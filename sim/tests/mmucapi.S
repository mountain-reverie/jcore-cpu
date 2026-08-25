! mmucapi.S -- I-side (ITLB) CAPACITY, and INTERLEAVED I/D walks under
! pressure on both arrays. Lane 1, cpu_tb.
!
! Third member of the D0b capacity suite; see docs/mmu/tlb-capacity-suite.md
! for the shared harness contract and the whole mutation table.
!
! WHY IT EXISTS
! =============
! Two gaps, both named in the D0b remediation item:
!
!   * TLB PRESSURE ABOVE THE ENTRY COUNT, on the I side. The shipped ITLB is 8
!     entries (core/cpu.vhd, u_itlb). mmudrain.S's leg D does exceed it -- ten
!     stubs plus a trampoline -- but it ASSERTS nothing about it: its header
!     records the 11 pages as an observation ("capacity misses the walker
!     absorbs as stalls"), and every check in the file is D-side base-register
!     arithmetic or a fault count. No claim is made here that mmudrain is the
!     ONLY such guard -- that was not checked across all 100 mmu*.S files --
!     only that nothing anywhere MEASURES that the ITLB evicts, or that a chain
!     which fits stays resident.
!
!   * MIXED I/D WALKS. The walker is one unit shared by both sides, routed by
!     `walk_side_i` (core/cpu.vhd), with a one-way I->D shadow fill on top. The
!     suite exercises the two sides largely one at a time. Leg M below runs a
!     chain in which every single page transition is an I-side walk immediately
!     followed by a D-side walk of a DIFFERENT page, twenty times over, with
!     both arrays over-subscribed throughout.
!
! THE MEASUREMENT
! ===============
! Each leg traverses a self-driving chain of stub pages three times from the
! same return point and measures P4_TLBINST (0xFF000058, [31:16] = ITLB slot
! writes, [15:0] = DTLB slot writes) across the LAST traversal only. Measuring
! the last of three, from a fixed return address, is what makes "zero" a legal
! answer at all: by then every page of the driver loop itself has been fetched,
! so the only installs left to count are the chain's.
!
!   leg S   N_SMALL_I stubs + trampoline -- fits in the ITLB
!           last traversal must install NOTHING in the ITLB (delta == 0).
!   leg L   N_LARGE_I stubs + trampoline -- exceeds it
!           last traversal must install at least N_LARGE_I ITLB entries: with
!           more pages than slots, coming back round the chain finds every one
!           of them evicted.
!   leg M   N_MIX stubs, each of which ALSO loads one aliased data page --
!           I and D walks strictly interleaved, both arrays over-subscribed.
!           Asserts the ITLB and DTLB install counts, the exact sum of the
!           twenty loaded words, and both chain pointers.
!
! Leg S's assertion is a non-increment and would be satisfied by a dead
! counter; leg L and leg M take exact-positive deltas off the SAME counter in
! the same run, so it is not dead. (Counter trustworthiness, the P1 pattern.)
!
! NEVER IDENTITY-MAPPED -- AND THE I SIDE IS THE STRONGER CASE
! ===========================================================
! Every stub and every data page is executed/read at VA = PA + ALIAS_DELTA.
! The alias window sits above the image, where the cosim's backing is anonymous
! and zero-filled, so if translation does not happen the instruction fetch
! returns 0x0000 -- which is not a stub, it is a general illegal instruction,
! and it lands in the VBR+0x100 handler as Result=0x42. An inert MMU cannot
! reach a single assertion in this file. Neither carve-out of
! sim/tests/README-identity-mapping.md is claimed: the frames move by editing
! ALIAS_DELTA alone.
!
! The DRIVER's own code pages are identity-mapped -- carve-out (b), the flat
! image load -- and no assertion depends on them.
!
! P5 (VA-backing). The alias window runs from _stubs_a + 0x0040_0000 for 58
! pages, i.e. at most 0x0044_0000, and the code pages sit below 0x0000_8000.
! All of it is inside the cosim's 16 MB backed window, which matters because
! the raw VA reaches the bus while a miss is being walked.
!
! MAINTENANCE HAZARD, read before growing the driver
! ==================================================
! Leg S asserts an ITLB delta of EXACTLY ZERO, which holds only while
! N_SMALL_I + 1 trampoline + the driver's own code pages stay at or under 8.
! Measured on the tree this landed on: the driver spans two pages (start at
! 0x1000, _code_end at 0x2418), so leg S's live set is 6 of 8. Adding ~2 pages
! of driver code turns leg S red at 0x52 -- which will look like a capacity
! defect and will not be one. If that happens, shrink N_SMALL_I rather than
! weakening the assertion to `<= n`; the exact zero is what makes the leg-S /
! leg-L differential mean anything.
!
! WHY THE STUBS ADVANCE r12 IN A DELAY SLOT
! =========================================
! `jmp @r12` / `add r11,r12`: SH-2 reads the jump target before the delay slot
! executes, so a stub can jump to the next page and compute the one after it in
! two instructions and no scratch. Same construction as mmudrain.S's leg D,
! which is where it was proved SH-2-correct on this core. r12's final value is
! asserted in every leg, so a dropped or doubled advance is caught rather than
! silently shortening the chain.
!
! GROUP C, and the mutations that make it non-vacuous
! ==================================================
! This guard passes on today's RTL, so a green run proves nothing on its own.
! Its strength is these, which were RUN:
!
!   M5  core/cpu.vhd, u_itlb `entries => 8` -> `entries => 32`
!       The 12-stub chain now fits and leg L's last traversal installs nothing.
!       MEASURED: FAIL mmucapi, Result=84 (0x54).
!
!   M6  core/cpu.vhd, u_itlb `entries => 8` -> `entries => 2`
!       Now even leg S's three stubs plus their trampoline do not fit.
!       MEASURED: FAIL mmucapi, Result=82 (0x52).
!
!   M0  the inert-MMU check CLAUDE.md asks for: change the `Enable AT` store
!       in the preamble from `mov #1,r1` to `mov #0,r1`. The first jump into
!       the chain then fetches the alias VA untranslated, reads 0x0000, and
!       takes a general illegal-instruction exception.
!       MEASURED: FAIL mmucapi, Result=66 (0x42) -- i.e. the guard cannot even
!       enter its first leg without real I-side relocation.
!
! M5 and M6 bracket the shipped ITLB size from above and below.
!
! WHAT IS NOT PINNED BY AN RTL MUTATION, said plainly. M5/M6 fire in legs L
! and S; M0 fires before any leg runs. Leg M's own codes (0x55-0x59) have NO
! dedicated RTL mutation here. What carries them is M0 -- an interleaved chain
! reading zeros instead of frames fails 0x55 as soon as it gets that far --
! plus the fact that 0x55 is an EXACT sum over twenty relocated loads, so a
! dropped, doubled or mis-relocated one moves it. Anyone tightening leg M
! should add a mutation aimed at the walker's D-side install routing, which
! this file does not currently have one for.
!
! AND 0x57 IS NOT INDEPENDENT EVIDENCE -- do not read it as such. The I->D
! shadow fill (core/cpu.vhd, p_tlb_shadow / `dtlb_wr <= ... or shadow_wr`)
! installs the STUB page into the DTLB one cycle behind every ITLB install, and
! P4_TLBINST[15:0] counts actual slot writes, shadow ones included. With N_MIX
! over-subscribed stub pages the third traversal therefore produces on the
! order of N_MIX DTLB installs FROM SHADOW FILLS ALONE, so
! "DTLB installs >= N_MIX" is satisfiable with not one D-side demand install in
! the run. It is a live-ness check on the D-side install path, no more.
! The D-side evidence in this leg is 0x55 (the exact twenty-term relocated sum)
! and 0x59 (the data pointer advanced exactly N_MIX times); those two are what
! make the interleave mean anything, and a reader weighing this guard should
! weigh them and discount 0x57 accordingly.
!
! RESULT CODES
! ============
!   0x51  leg S: chain pointer wrong after a traversal -- the chain did not run
!         to its trampoline exactly once
!   0x52  leg S: the last traversal installed ITLB entries although the chain
!         FITS -- something evicted with room to spare (M6)
!   0x53  leg L: chain pointer wrong
!   0x54  leg L: the last traversal installed fewer than N_LARGE_I ITLB entries
!         -- pressure above the entry count did not evict (M5)
!   0x55  leg M: the sum of the loaded words is wrong -- a D-side touch in the
!         interleaved chain mis-translated, or ran the wrong number of times
!   0x56  leg M: fewer than N_MIX ITLB installs in the last traversal
!   0x57  leg M: fewer than N_MIX DTLB installs in the last traversal. WEAK --
!         the I->D shadow fill alone can satisfy it; see the note above.
!   0x58  leg M: I-side chain pointer wrong
!   0x59  leg M: D-side data pointer wrong
!   0x2E  SETUP: a TSB set was full in BOTH ways while seeding the CODE pages.
!   0x2F  SETUP: ditto while seeding the ALIAS window. Split from 0x2E because
!         the two ranges fail for different reasons: the code range grows with
!         the guard, the alias range with N_LARGE_I / N_MIX. Either is a
!         harness collision, not a CPU defect.
!   0x41  unexpected TLB exception (VBR+0x400). Every VA here has a TSB row.
!         If you are reading this after changing a PARAMETER rather than the
!         RTL, check the assembly-time range checks below first.
!   0x42  unexpected general exception (VBR+0x100) -- notably what an
!         UNTRANSLATED fetch of the alias window produces, since it reads 0x0000
!   0x7F  NOT an assertion. The _fail integrity net rewrites r9==0 to 0x7F, so
!         this is a fall-through into _fail without a code being set, not a
!         failed check. Chase the control flow, not the MMU.
!
! Codes are all <= 0x7F so `mov #imm` does not sign-extend them.
!
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

#define PAGE_SZ      0x1000
! ITLB is 8 entries (core/cpu.vhd, u_itlb). N_SMALL_I + 1 trampoline + the
! driver's own code pages must stay under it; N_LARGE_I must exceed it.
#define N_SMALL_I    3
#define N_LARGE_I    12
#define N_MIX        20
#define ALIAS_DELTA  0x00400000
! One PTEL flag word serves stub pages and data pages alike: 0xCD is
! W|X|C|G|V with U=0. X=1 lets the kernel fetch it, U=0 keeps SMEP happy
! (a kernel fetch from a U=1 page faults forever), W=1 lets it be written,
! and a kernel data read needs no U bit at all.
#define MAP_FLAGS    0x000000CD
#define TSB_BASE     0x00F00000
#define TSB_SIZE_LOG 10

! Total 4 KB pages in the alias window: three chains, each N stubs plus a
! trampoline, and leg M's data pages.
#define ALIAS_PAGES  ((N_SMALL_I + 1) + (N_LARGE_I + 1) + (N_MIX + 1) + N_MIX)

! ---------------------------------------------------------------------------
! PARAMETER RANGE CHECKS -- at ASSEMBLY time. Same reasoning as mmucapd.S's:
! a misconfigured constant otherwise reaches run time and lands on Result=0x41
! or 0x42, whose texts accuse the walker, so a harness mistake reads as an RTL
! defect. Each counter below is consumed by `mov #imm`, which sign-extends
! above 127. Every operand is a preprocessor constant, so `.if` can evaluate
! it -- see the longer note in mmucapd.S about why that distinction matters.
! ---------------------------------------------------------------------------
        .if N_LARGE_I > 127
        .error "mmucapi: N_LARGE_I is loaded with `mov #imm', which sign-extends above 127"
        .endif
        .if N_SMALL_I > 127
        .error "mmucapi: N_SMALL_I is loaded with `mov #imm', which sign-extends above 127"
        .endif
        .if N_MIX > 127
        .error "mmucapi: N_MIX is loaded with `mov #imm', which sign-extends above 127"
        .endif
        .if N_SMALL_I >= N_LARGE_I
        .error "mmucapi: N_SMALL_I must be strictly under N_LARGE_I, or legs S and L do not differ"
        .endif
        ! The alias window must sit ENTIRELY ABOVE the image, or an
        ! untranslated fetch there stops reading 0x0000 and the inert-MMU
        ! tripwire (Result=0x42) dies.
        .if ALIAS_PAGES * PAGE_SZ > ALIAS_DELTA
        .error "mmucapi: the alias window would overlap the image; an untranslated fetch there stops reading 0x0000 and the inert-MMU tripwire dies"
        .endif
        ! P5: the raw VA reaches the bus while a miss is walked, so every VA
        ! must be inside the cosim's 16 MB backing. The 1 MB allowance stands
        ! in for _stubs_a, which is not a constant.
        .if ALIAS_DELTA + ALIAS_PAGES * PAGE_SZ + 0x00100000 > 0x01000000
        .error "mmucapi: the alias window leaves the cosim's 16 MB backed range (P5)"
        .endif
        ! HONESTY NOTE: at the shipped ALIAS_DELTA of 0x0040_0000 the overlap
        ! check above always trips first, so this P5 check is UNREACHABLE and
        ! was NOT demonstrated firing -- unlike the others, each of which was.
        ! It is kept because it becomes the binding constraint the moment
        ! anyone raises ALIAS_DELTA, and a check that only matters later is
        ! still cheaper than the run-time 0x41 it replaces.

        ! Stack deliberately NOT the usual 0x7000, which would land inside
        ! the stub pages. Nothing here uses it.
        mmu_vect_block 0x00300000
        .balign PAGE_SZ
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

        ! ---- VBR = _vecblk (handlers at +0x100 and +0x400). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- TSB configuration, then ASIDR = 0. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

        ! ---- Rows for the driver's own code pages: IDENTITY (delta 0). ----
        mov.l   p_code_start, r1
        mov.l   p_code_end, r2
        mov.l   p_4kmask, r3
        mov     #0, r4
        mov.l   p_flags, r5
        mov     #0x2E, r9               ! setup-failure code for THIS range
        mov.l   p_seed, r0
        jsr     @r0
        nop

        ! ---- Rows for the whole alias window: VA = PA + ALIAS_DELTA. Every
        ! ---- page here is 4 KB (there is no CAP_PM analogue on this axis), so
        ! ---- the PPN mask is the plain page mask for both calls.
        mov.l   p_alias_va, r1
        mov.l   p_alias_vaend, r2
        mov.l   p_4kmask, r3
        mov.l   p_delta, r4
        mov.l   p_flags, r5
        mov     #0x2F, r9
        mov.l   p_seed, r0
        jsr     @r0
        nop

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        bra     _leg_S
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _vecblk
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long TSB_BASE + TSB_SIZE_LOG
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_code_start:   .long start
p_code_end:     .long _code_end
p_4kmask:       .long 0xFFFFF000
p_alias_va:     .long _stubs_a + ALIAS_DELTA
p_alias_vaend:  .long _alias_end + ALIAS_DELTA
p_delta:        .long ALIAS_DELTA
p_flags:        .long MAP_FLAGS
p_seed:         .long _seed
p_mmucr:        .long 0xFF000010

        ! r9 already carries 0x2E or 0x2F -- whichever seed call landed here.
ENTRY(_setup_full)
        bra     _fail
        nop

        mmu_seed_routine z, PAGE_SZ

#else
        bra     _done
        nop
#endif  ! CONFIG_PRIV_ARCH (preamble)

        mmu_done_fail p

#if CONFIG_PRIV_ARCH
! ===========================================================================
! LEG S -- an I-side chain that FITS in the ITLB.
!
! Three traversals from one return point; the ITLB install count is taken
! across the third. r15 is the iteration counter (not the stack: nothing here
! pushes), r11 the stub stride, r12 the running next-stub VA, r14 the return.
! ===========================================================================
ENTRY(_leg_S)
        mov.l   s_tlbi, r10
        mov.l   s_stride, r11
        mov.l   s_ret, r14
        mov     #3, r15
1:      mov.l   s_a1, r12               ! r12 = stub 1's VA
        mov.l   s_a0, r1                ! r1  = stub 0's VA
        mov.l   @r10, r4                ! install counts before this traversal
        jmp     @r1
        nop
ENTRY(_capi_sret)
        mov.l   @r10, r6                ! ...and after
        dt      r15
        bf      1b

        mov.l   s_a_fin, r0             ! the LAST traversal (r12 is reset each
                                        ! iteration) reached the trampoline and
                                        ! advanced exactly N_SMALL_I + 1 times
        cmp/eq  r0, r12
        mov     #0x51, r9
        bt      2f
        bra     _fail
        nop
2:      mov     r6, r7
        sub     r4, r7
        shlr16  r7                      ! r7 = ITLB installs in traversal 3
        tst     r7, r7
        mov     #0x52, r9
        bt      3f
        bra     _fail
        nop
3:      bra     _leg_L
        nop

        .align 2
s_tlbi:         .long 0xFF000058        ! P4_TLBINST [31:16]=ITLB [15:0]=DTLB
s_stride:       .long PAGE_SZ
s_ret:          .long _capi_sret
s_a0:           .long _stubs_a + ALIAS_DELTA
s_a1:           .long _stubs_a + ALIAS_DELTA + PAGE_SZ
s_a_fin:        .long _stubs_a + ALIAS_DELTA + (N_SMALL_I + 1) * PAGE_SZ

! ===========================================================================
! LEG L -- an I-side chain that does NOT fit.
!
! Identical driver, longer chain. Coming back round to stub 0 must find it
! evicted, and so must every stub after it, so the third traversal installs at
! least N_LARGE_I ITLB entries.
! ===========================================================================
ENTRY(_leg_L)
        mov.l   l_mmucr, r0
        mmu_flush_at r0                 ! leg boundary: AT off, TI, AT on

        mov.l   l_tlbi, r10
        mov.l   l_stride, r11
        mov.l   l_ret, r14
        mov     #3, r15
1:      mov.l   l_b1, r12
        mov.l   l_b0, r1
        mov.l   @r10, r4
        jmp     @r1
        nop
ENTRY(_capi_lret)
        mov.l   @r10, r6
        dt      r15
        bf      1b

        mov.l   l_b_fin, r0
        cmp/eq  r0, r12
        mov     #0x53, r9
        bt      2f
        bra     _fail
        nop
2:      mov     r6, r7
        sub     r4, r7
        shlr16  r7                      ! r7 = ITLB installs in traversal 3
        mov     #N_LARGE_I, r0
        cmp/hs  r0, r7                  ! T = (installs >= N_LARGE_I)
        mov     #0x54, r9
        bt      3f
        bra     _fail
        nop
3:      bra     _leg_M
        nop

        .align 2
l_mmucr:        .long 0xFF000010
l_tlbi:         .long 0xFF000058
l_stride:       .long PAGE_SZ
l_ret:          .long _capi_lret
l_b0:           .long _stubs_b + ALIAS_DELTA
l_b1:           .long _stubs_b + ALIAS_DELTA + PAGE_SZ
l_b_fin:        .long _stubs_b + ALIAS_DELTA + (N_LARGE_I + 1) * PAGE_SZ

! ===========================================================================
! LEG M -- interleaved I-side and D-side walks, both arrays over-subscribed.
!
! Every mixed stub loads one aliased data page and then jumps to the next
! aliased stub page, so the walker alternates sides N_MIX times per traversal
! with N_MIX code pages against 8 ITLB entries and N_MIX data pages (plus the
! I->D shadow fills) against 16 DTLB entries.
!
! The sum of the loaded words is the D-side evidence: each word holds its own
! physical address, so the sum is right only if every load relocated to the
! right frame AND ran exactly once, in order. A dropped or doubled load moves
! it. The expected value is computed here in a loop rather than folded into a
! literal, because `N * symbol` is not a relocatable expression.
!
! It is the evidence BECAUSE the DTLB install count is not. The I->D shadow
! fill writes a DTLB slot behind every ITLB install, and P4_TLBINST[15:0]
! counts slot writes, so the 0x57 threshold below can be met by shadow fills
! alone without a single D-side demand install. 0x57 is a live-ness check;
! 0x55 and 0x59 are the leg.
! ===========================================================================
ENTRY(_leg_M)
        mov.l   m_mmucr, r0
        mmu_flush_at r0                 ! leg boundary: AT off, TI, AT on

        ! expected sum = sum of the N_MIX data-page PHYSICAL addresses
        mov.l   m_dpa, r1
        mov.l   m_stride, r4
        mov     #N_MIX, r2
        mov     #0, r3
1:      add     r1, r3
        add     r4, r1
        dt      r2
        bf      1b
        ! Park it in r5, NOT r9. r9 is the fail-code register, and the _fail
        ! integrity net only rewrites r9 == 0 -- so any check added inside the
        ! window below would have reported a 32-bit sum (~0x0034_0000) and read
        ! as memory corruption rather than as a failed assertion. r5 is free
        ! here (the mixed stub touches only r6, r7, r8, r11, r12, r13) and is
        ! not reused until after the 0x55 compare consumes it.
        mov     r3, r5
        mov.l   m_tlbi, r10
        mov.l   m_stride, r11
        mov.l   m_dstride, r8
        mov.l   m_ret, r14
        mov     #3, r15
2:      mov.l   m_m1, r12
        mov.l   m_dva, r13
        mov     #0, r7                  ! running sum for THIS traversal
        mov.l   m_m0, r1
        mov.l   @r10, r4
        jmp     @r1
        nop
ENTRY(_capi_mret)
        mov.l   @r10, r6
        dt      r15
        bf      2b

        ! ---- 0x55: the twenty loads translated correctly, exactly once each
        cmp/eq  r5, r7
        mov     #0x55, r9
        bt      3f
        bra     _fail
        nop
3:      mov     r6, r5                  ! r5 is free again from here
        sub     r4, r5                  ! r5 = packed install delta
        mov     r5, r3
        shlr16  r3                      ! r3 = ITLB installs
        extu.w  r5, r5                  ! r5 = DTLB installs
        mov     #N_MIX, r0
        cmp/hs  r0, r3
        mov     #0x56, r9
        bt      4f
        bra     _fail
        nop
4:      mov     #N_MIX, r0
        cmp/hs  r0, r5
        mov     #0x57, r9
        bt      5f
        bra     _fail
        nop
5:      mov.l   m_m_fin, r0
        cmp/eq  r0, r12
        mov     #0x58, r9
        bt      6f
        bra     _fail
        nop
6:      mov.l   m_d_fin, r0
        cmp/eq  r0, r13
        mov     #0x59, r9
        bt      7f
        bra     _fail
        nop
7:      mov.l   m_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off before handing over the result
        mov     #0, r9
        bra     _done
        nop

        .align 2
m_mmucr:        .long 0xFF000010
m_tlbi:         .long 0xFF000058
m_stride:       .long PAGE_SZ
m_dstride:      .long PAGE_SZ
m_ret:          .long _capi_mret
m_dpa:          .long _mdata
m_dva:          .long _mdata + ALIAS_DELTA
m_m0:           .long _stubs_m + ALIAS_DELTA
m_m1:           .long _stubs_m + ALIAS_DELTA + PAGE_SZ
m_m_fin:        .long _stubs_m + ALIAS_DELTA + (N_MIX + 1) * PAGE_SZ
m_d_fin:        .long _mdata + ALIAS_DELTA + N_MIX * PAGE_SZ

! ===========================================================================
! Vector block (mmuwalk_common.inc). 0x42 is the one an inert MMU produces:
! an untranslated fetch of the alias window reads 0x0000.
! ===========================================================================
        mmu_vec_handlers H, 0x42, 0x41

        .balign 4
ENTRY(_code_end)                        ! end of the identity-mapped driver

! ===========================================================================
! The alias window: everything from here to _alias_end is reached ONLY through
! VA = PA + ALIAS_DELTA. Nothing below jumps or loads by physical address.
!
! Chain arithmetic: stub i is entered with r12 == VA(stub i+1); it jumps there
! and its delay slot bumps r12 to VA(stub i+2). The last stub therefore lands
! on the trampoline, which sits exactly one page past the last stub because
! the `.balign PAGE_SZ` inside the .rept makes the spacing exact. The
! s_a_fin / l_b_fin / m_m_fin assertions prove that rather than assume it.
! ===========================================================================
        .balign PAGE_SZ
_stubs_a:
        .rept   N_SMALL_I
        .balign PAGE_SZ
        jmp     @r12
        add     r11, r12
        .endr
        .balign PAGE_SZ
_tramp_a:
        jmp     @r14
        nop

        .balign PAGE_SZ
_stubs_b:
        .rept   N_LARGE_I
        .balign PAGE_SZ
        jmp     @r12
        add     r11, r12
        .endr
        .balign PAGE_SZ
_tramp_b:
        jmp     @r14
        nop

! Mixed stubs: one D-side load of an aliased data page, accumulated into r7,
! then the same two-instruction page hop. r8 is the data stride and r13 the
! running data VA, both staged by the driver.
        .balign PAGE_SZ
_stubs_m:
        .rept   N_MIX
        .balign PAGE_SZ
        mov.l   @r13, r6
        add     r6, r7
        add     r8, r13
        jmp     @r12
        add     r11, r12
        .endr
        .balign PAGE_SZ
_tramp_m:
        jmp     @r14
        nop

! The data pages leg M reads. One word per page, holding ITS OWN PHYSICAL
! ADDRESS -- the same self-describing sentinel mmucapd.S uses, so the expected
! sum is computable from _mdata and needs no table.
        .balign PAGE_SZ
_mdata:
        .rept   N_MIX
        .long   .
        .space  PAGE_SZ - 4, 0
        .endr
        .balign PAGE_SZ
ENTRY(_alias_end)

#endif  ! CONFIG_PRIV_ARCH (legs + vectors + alias window)
