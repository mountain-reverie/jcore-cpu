! mmucapd.S -- D-side (DTLB) CAPACITY / EVICTION sweep. Lane 1, cpu_tb.
!
! This file is BOTH a guard and the harness its siblings parameterise. See
! "PARAMETERS" below; sim/tests/mmucapsub.S is a three-line wrapper over it.
! The suite as a whole -- harness contract, mutation table, how to add a
! parameterisation -- is docs/mmu/tlb-capacity-suite.md.
!
! WHY IT EXISTS
! =============
! The cycle cosim's MMU working sets were, with one exception, small enough to
! fit in the TLB and were always touched base-first. That hides exactly the
! class of defect a TLB is for:
!
!   * a translation that is correct on first touch but WRONG after the entry
!     has been evicted and re-walked;
!   * a replacement policy that never actually evicts (an infinite-capacity
!     model passes every guard whose working set fits);
!   * an entry installed from a NON-BASE first touch that fails to cover the
!     rest of its own mapping.
!
! The one exception was mmudrain.S, whose ten D-side pages made it the suite's
! only DTLB-size canary -- and ten is still under the shipped DTLB's sixteen
! entries, so even that guard never forces a capacity eviction. It reacts to
! an 8-entry DTLB and to nothing else. This file replaces that one-off probe
! with a differential measurement that brackets the capacity from both sides.
!
! THE MEASUREMENT (why a green run here is not vacuous)
! ====================================================
! Two legs run the IDENTICAL probe over working sets that differ ONLY in size:
!
!   leg S   N_SMALL mappings   -- fits in the DTLB
!           after the sweep, re-touching mapping 0 must take NO walk.
!   leg L   N_LARGE mappings   -- exceeds the DTLB
!           after the sweep, re-touching mapping 0 must take EXACTLY ONE walk
!           that hits the TSB (P4_TSBCNT delta == 0x0001_0001).
!
! Neither leg can be satisfied by a stuck counter or an inert MMU: leg S's
! assertion is a NON-increment, but leg L's is an EXACT POSITIVE delta taken by
! the same three instructions, and every touch in both legs additionally
! asserts the RELOCATED data (below). A model with no capacity at all fails leg
! L; a model that cannot keep anything resident fails leg S.
!
! NEVER IDENTITY-MAPPED
! =====================
! Every mapping under test is VA = PA + ALIAS_DELTA, and each backing word
! holds ITS OWN PHYSICAL ADDRESS (`.long .` in the `_frames` block). So the
! check after every single touch is
!
!       load(VA) == VA - ALIAS_DELTA
!
! which is false unless the translation actually relocated the access to the
! right frame. The VA window itself is above the image, so the cosim's
! anonymous zero-filled backing makes an untranslated read return 0 -- i.e. an
! MMU that never came on, an entry that never installed, or a walker that never
! ran all fail the very first data check (0x11) rather than passing quietly.
! Neither carve-out of sim/tests/README-identity-mapping.md is claimed or
! needed: the frames move by editing ALIAS_DELTA alone.
!
! The CODE pages are identity-mapped, which is carve-out (b) (the flat image
! load pins them), and no assertion in this file depends on them.
!
! P5 (VA-backing). Every VA touched under AT=1 lies in [0, 0x0100_0000). The
! raw VA reaches the bus while a miss is walked, and all of the following is
! inside the cosim's 16 MB backed window. MEASURED on the linked images:
!   mmucapd    code 0x0000_1000..0x0000_2418, alias 0x0040_3000..0x0041_B000
!   mmucapsub  code 0x0000_4000..0x0000_5418, alias 0x0040_8000..0x0046_8000
! (mmucapsub's .text is pushed to 0x4000 because `.balign MAP_SPAN` on _frames
! raises the whole input section's alignment to 0x4000. Harmless, but it is why
! the two builds do not share a `start`.)
!
! MAINTENANCE HAZARD, read before growing this file
! =================================================
! Leg S asserts that the walker counters do NOT move, which holds only while
! N_SMALL mappings plus the code pages this file reads literal pools out of
! stay at or under the DTLB's 16 entries. Measured on the tree this landed on:
! the code region is two pages (start at 0x1000, _code_end at 0x2418), so leg
! S's D-side live set is 8 of 16. There is room, but it is not unlimited --
! and if leg S ever goes red at 0x13 after an edit that only ADDED code, that
! is the reason. Shrink N_SMALL rather than weakening the assertion: the exact
! non-increment is what makes the leg-S / leg-L differential mean anything.
!
! PARAMETERS (a wrapper #defines these, then #includes this file)
! ===============================================================
!   CAP_PM        PageMask of every mapping under test. 0 => 4 KB (this file's
!                 own build), 1 => 16 KB (mmucapsub.S).
!   CAP_FIRSTSUB  which 4 KB sub-page of a mapping is touched FIRST. 0 is
!                 base-first; mmucapsub.S uses 3, i.e. the LAST sub-page of a
!                 16 KB mapping, so no mapping in that build is ever entered
!                 through its own first PAGE_SIZE.
!   N_SMALL       how many mappings the "fits" leg sweeps.       default 6
!   N_LARGE       how many the "does not fit" leg sweeps.        default 24
!
! N_LARGE is overridable BECAUSE it has to be: the VA window is
! N_LARGE * MAP_SPAN and must stay inside the cosim's 16 MB backing, so raising
! CAP_PM without being able to lower N_LARGE would walk straight off the end of
! P5. See the block at the #ifndefs below for the one constraint that binds.
!
! The TSB is 4 KB-granular BY CONTRACT -- core/tlb_walk.vhd compares
! `bus_d(31 downto 12) = va_reg(31 downto 12)` and core/datapath_pkg.vhd's
! tsb_ptr() hashes VA[31:12] -- so a superpage needs one row per 4 KB sub-page,
! all carrying the same PTEL. The seed loop below walks the alias window in
! PAGE_SZ steps and derives each row's PPN as (VA - ALIAS_DELTA) & ~(MAP_SPAN-1),
! which produces exactly that for any CAP_PM.
!
! GROUP C, and the mutations that make it non-vacuous
! ==================================================
! This guard passes on today's RTL. A green run therefore proves nothing on its
! own; its strength comes entirely from the following named mutations, which
! were RUN, not argued. Re-run them before trusting any change to core/tlb.vhd's
! NRU/install path or to the two `entries` generics in core/cpu.vhd.
!
!   M1  core/cpu.vhd, u_dtlb `entries => 16` -> `entries => 32`
!       The 24-mapping working set now fits, mapping 0 is never evicted, and
!       leg L's probe takes no walk.
!       MEASURED: FAIL mmucapd, Result=35 (0x23).
!
!   M2  core/cpu.vhd, u_dtlb `entries => 16` -> `entries => 4`
!       Now even leg S's six mappings do not fit, so the entry that leg S
!       requires to be resident has been evicted.
!       MEASURED: FAIL mmucapd, Result=19 (0x13).
!
! M1 and M2 bracket the shipped size from above and below: the guard is red if
! the DTLB is bigger than it says and red if it is smaller. That is what makes
! "TLB pressure greater than the entry count" a measurement rather than a
! description.
!
!   M0  the inert-MMU check CLAUDE.md asks for: in the preamble below, change
!       the `Enable AT` store from `mov #1,r1` to `mov #0,r1` so MMUCR.AT is
!       never set. Every access then reaches the bus untranslated, the alias
!       window reads back zeros, and the very first sweep touch is wrong.
!       MEASURED: FAIL mmucapd, Result=17 (0x11) -- and FAIL mmucapsub with
!       the same code, since it shares this preamble.
!
! RESULT CODES
! ============
!   0x11  leg S sweep: wrong data -- translation absent, wrong frame, or MMU off
!   0x12  leg S probe: wrong data
!   0x13  leg S probe: the walker counters MOVED. A working set that FITS
!         re-walked -> the entry was evicted although there was room. (M2)
!   0x21  leg L sweep: wrong data
!   0x22  leg L probe: wrong data
!   0x23  leg L probe: counter delta is not exactly one walk that hit
!         (0x0001_0001) -> pressure above the entry count did NOT evict. (M1)
!   0x24  leg L base probe: wrong data at the mapping BASE
!   0x25  leg L base probe: the counters MOVED. The entry installed from the
!         FIRST-TOUCH sub-page does not cover its own mapping base.
!         DEGENERATE IN *THIS* BUILD, and do not credit this file with the
!         property. At CAP_PM=0 / CAP_FIRSTSUB=0 the two probe VAs are the same
!         address -- l_first0 and l_base0 are both _frames + ALIAS_DELTA, and
!         the linked image shows both literals holding 0x00403000 -- so probe 2
!         re-touches exactly what probe 1 just installed. Here 0x25 asserts only
!         RESIDENCY ACROSS A RE-TOUCH, which is worth having but is not
!         coverage. The stated coverage property is measured by mmucapsub.S,
!         where CAP_FIRSTSUB=3 makes the two VAs 0x3000 apart, and it is
!         mmucapsub that goes red under M4 while this file stays green -- which
!         is exactly the evidence that 0x25 here is inert.
!   0x26  leg L sweep: fewer than N_LARGE walks over the whole sweep -> the
!         sweep did not actually miss, so leg L measured nothing
!   0x31  final re-sweep at the mapping bases: wrong data after the churn
!   0x2E  SETUP: a TSB set was full in BOTH ways while seeding the CODE pages.
!   0x2F  SETUP: ditto while seeding the ALIAS window. Split from 0x2E because
!         the two ranges fail for different reasons and have different fixes --
!         the code range grows with the guard, the alias range with N_LARGE.
!         Either is a harness collision, not a CPU defect: widen TSB_SIZE_LOG
!         or move the window.
!   0x41  unexpected TLB exception (VBR+0x400). Every VA touched here has a TSB
!         row, so a fault means the walker did not resolve one it could have.
!         If you are reading this after changing a PARAMETER rather than the
!         RTL, see the assembly-time range checks below first -- they exist
!         because several misconfigurations used to land here and read as an
!         RTL defect.
!   0x42  unexpected general exception (VBR+0x100)
!   0x7F  NOT an assertion. The _fail integrity net rewrites r9==0 to 0x7F, so
!         this is what reaching _fail without setting a code looks like: a
!         fall-through, not a failed check. Chase the control flow, not the MMU.
!
! Codes are all <= 0x7F so `mov #imm` does not sign-extend them.
!
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

#ifndef CAP_PM
#define CAP_PM 0
#endif
#ifndef CAP_FIRSTSUB
#define CAP_FIRSTSUB 0
#endif

! N_SMALL must fit in the DTLB alongside the handful of code pages this file
! reads literal pools out of; N_LARGE must exceed it outright. Shipped DTLB is
! 16 entries (core/cpu.vhd, u_dtlb). Every mapping costs exactly ONE entry
! whatever CAP_PM is, because a superpage is one entry.
!
! WRAPPER-OVERRIDABLE, and it has to be. The VA window is N_LARGE * MAP_SPAN
! bytes and must stay inside the cosim's 16 MB backing (P5), so a wrapper that
! raises CAP_PM has to be able to lower N_LARGE in the same breath -- at
! CAP_PM=4 the default 24 would need 24 MB. Both are #ifndef-guarded for that
! reason. The only hard constraint is the one above: N_SMALL + the code pages
! at or under the DTLB entry count, N_LARGE strictly over it.
#ifndef N_SMALL
#define N_SMALL      6
#endif
#ifndef N_LARGE
#define N_LARGE      24
#endif

#define PAGE_SZ      0x1000
#define CAP_NSUB     (1 << (2 * CAP_PM))
#define MAP_SPAN     (PAGE_SZ * CAP_NSUB)
#define FIRST_OFF    (CAP_FIRSTSUB * PAGE_SZ)

#define ALIAS_DELTA  0x00400000
#define DATA_FLAGS   ((CAP_PM << 8) | 0xE9)
#define CODE_FLAGS   0x000000CD
#define TSB_BASE     0x00F00000
#define TSB_SIZE_LOG 10

! ---------------------------------------------------------------------------
! PARAMETER RANGE CHECKS -- at ASSEMBLY time, and here is why they are worth
! six directives.
!
! Every one of the misconfigurations below used to assemble and link with no
! diagnostic at all, and then land on Result=0x41 at run time. 0x41's own text
! says "a fault means the walker did not resolve one it could have" -- so a
! harness mistake read as an RTL defect, which is the most expensive kind of
! wrong signal this suite can emit. Two measured examples:
!
!   CAP_FIRSTSUB=4 at CAP_PM=1  FIRST_OFF becomes MAP_SPAN, so every first
!                               touch slides up one whole mapping and leg L's
!                               last one falls off the end of the seeded
!                               window, where there is no row.
!   N_LARGE=130                 `mov #N_LARGE, r13` sign-extends; objdump
!                               shows `mov #-126,r13` and the sweep loop runs
!                               a garbage number of times.
!
! Every operand here is a preprocessor constant, so `.if` can evaluate it --
! unlike a section-relative symbol difference, which gas rejects with
! "non-constant expression in .if statement". That distinction is exactly what
! bit sim/tests/Makefile's single-page check, which had to move OUT of the
! file and onto the linked image for the same reason. These stay in-file
! BECAUSE they are pure arithmetic on #defines, and each was verified to fire
! by building a deliberately violating wrapper.
! ---------------------------------------------------------------------------
        .if CAP_FIRSTSUB >= CAP_NSUB
        .error "mmucapd: CAP_FIRSTSUB must index a sub-page INSIDE the mapping (0 .. CAP_NSUB-1)"
        .endif
        .if N_LARGE > 127
        .error "mmucapd: N_LARGE is loaded with `mov #imm', which sign-extends above 127"
        .endif
        .if N_SMALL > 127
        .error "mmucapd: N_SMALL is loaded with `mov #imm', which sign-extends above 127"
        .endif
        .if N_SMALL >= N_LARGE
        .error "mmucapd: N_SMALL must be strictly under N_LARGE, or the two legs do not differ"
        .endif
        ! The alias window must sit ENTIRELY ABOVE the image. The frames are
        ! N_LARGE * MAP_SPAN bytes at _frames, and the window starts at
        ! _frames + ALIAS_DELTA, so this is the whole condition -- and it is
        ! what keeps the inert-MMU tripwire alive: an untranslated read only
        ! returns 0 while the VA lands in the cosim's anonymous zero-filled
        ! backing rather than back inside the loaded image.
        .if N_LARGE * MAP_SPAN > ALIAS_DELTA
        .error "mmucapd: the alias window would overlap the image; an untranslated read there stops returning 0 and the inert-MMU tripwire dies"
        .endif
        ! P5: every VA touched under AT=1 must be inside the cosim's 16 MB
        ! backing, because the raw VA reaches the bus while a miss is walked.
        ! The 1 MB allowance stands in for _frames, which is not a constant.
        .if ALIAS_DELTA + N_LARGE * MAP_SPAN + 0x00100000 > 0x01000000
        .error "mmucapd: the alias window leaves the cosim's 16 MB backed range (P5)"
        .endif
        ! HONESTY NOTE: at the shipped ALIAS_DELTA of 0x0040_0000 the overlap
        ! check above always trips first, so this P5 check is UNREACHABLE and
        ! was NOT demonstrated firing -- unlike the others, each of which was.
        ! It is kept because it becomes the binding constraint the moment
        ! anyone raises ALIAS_DELTA, and a check that only matters later is
        ! still cheaper than the run-time 0x41 it replaces.

        ! Stack deliberately NOT the usual 0x7000, which lands inside
        ! _frames and would silently overwrite a sentinel. Nothing here uses
        ! it -- no JSR nesting, and exception entry saves to SPC/SSR.
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

        ! ---- Rows for the guard's own CODE pages, start .. _code_end:
        ! ---- IDENTITY (delta 0, 4 KB mask) and GLOBAL, U=0 for SMEP. Not what
        ! ---- is under test -- they only have to be resolvable the moment AT
        ! ---- goes on, and the walker pulls each in as a STALL on first touch,
        ! ---- so no exception is ever taken for them.
        mov.l   p_code_start, r1
        mov.l   p_code_end, r2
        mov.l   p_4kmask, r3
        mov     #0, r4                  ! identity: PA == VA
        mov.l   p_code_flags, r5
        mov     #0x2E, r9               ! setup-failure code for THIS range
        mov.l   p_seed, r0
        jsr     @r0
        nop

        ! ---- Rows for every 4 KB page of the ALIAS window. Each row's TAG is
        ! ---- that page's own VPN (the TSB is 4 KB-granular by contract, C1)
        ! ---- while its PTEL carries the MAPPING BASE's PPN plus CAP_PM, so
        ! ---- all CAP_NSUB sub-pages of one mapping share a PTEL and install
        ! ---- as ONE TLB entry:  PPN = (VA - ALIAS_DELTA) & ~(MAP_SPAN - 1).
        ! ----
        ! ---- Seeding every sub-page rather than only the first-touched one is
        ! ---- deliberate: a missing TLB entry then shows up as an extra WALK
        ! ---- (a named counter failure) instead of as an exception, which is a
        ! ---- far more legible signal.
        mov.l   p_va, r1
        mov.l   p_vaend, r2
        mov.l   p_spanmask, r3
        mov.l   p_delta, r4
        mov.l   p_data_flags, r5
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
p_seed:         .long _seed
p_code_start:   .long start
p_code_end:     .long _code_end
p_4kmask:       .long 0xFFFFF000
p_code_flags:   .long CODE_FLAGS
p_va:           .long _frames + ALIAS_DELTA
p_vaend:        .long _frames + ALIAS_DELTA + N_LARGE * MAP_SPAN
p_spanmask:     .long ~(MAP_SPAN - 1)
p_delta:        .long ALIAS_DELTA
p_data_flags:   .long DATA_FLAGS
p_mmucr:        .long 0xFF000010

        ! r9 already carries 0x2E or 0x2F -- whichever seed call landed here.
        ! Splitting them costs nothing and tells you which range collided.
ENTRY(_setup_full)
        bra     _fail
        nop

        mmu_seed_routine s, PAGE_SZ

#else
        bra     _done
        nop
#endif  ! CONFIG_PRIV_ARCH (preamble)

        mmu_done_fail p

#if CONFIG_PRIV_ARCH
! ===========================================================================
! LEG S -- a working set that FITS.
!
! Sweep N_SMALL mappings, each entered at its CAP_FIRSTSUB sub-page, then
! re-touch mapping 0. Nothing may have been evicted, so the re-touch must be a
! plain TLB hit: no walk, no TSB read, both halves of P4_TSBCNT unchanged.
!
! The probe is a three-instruction REGISTER-ONLY window -- counter, access,
! counter -- with the counter address and the probe VA staged beforehand. A
! PC-relative literal load inside the window would be a second D-side access
! through a code page and would make the delta mean something else.
! ===========================================================================
ENTRY(_leg_S)
        mov.l   s_cnt, r10              ! r10 = &P4_TSBCNT
        mov.l   s_first0, r11           ! r11 = mapping 0's first-touch VA
        mov.l   s_delta, r14
        mov.l   s_span, r12
        mov     r11, r1
        mov     #N_SMALL, r13
1:      mov.l   @r1, r2                 ! the touch
        mov     r1, r3
        sub     r14, r3                 ! expected = VA - ALIAS_DELTA
        cmp/eq  r3, r2
        mov     #0x11, r9
        bt      2f
        bra     _fail
        nop
2:      add     r12, r1
        dt      r13
        bf      1b

        ! ---- probe: register-only window ----
        mov.l   @r10, r4
        mov.l   @r11, r5
        mov.l   @r10, r6

        mov     r11, r3
        sub     r14, r3
        cmp/eq  r3, r5
        mov     #0x12, r9
        bt      3f
        bra     _fail
        nop
3:      cmp/eq  r4, r6                  ! the counters must NOT have moved
        mov     #0x13, r9
        bt      4f
        bra     _fail
        nop
4:      bra     _leg_L
        nop

        .align 2
s_cnt:          .long 0xFF000054        ! P4_TSBCNT [31:16]=walks [15:0]=hits
s_first0:       .long _frames + ALIAS_DELTA + FIRST_OFF
s_delta:        .long ALIAS_DELTA
s_span:         .long MAP_SPAN

! ===========================================================================
! LEG L -- a working set that does NOT fit.
!
! Same sweep, N_LARGE mappings. Three assertions:
!   0x26  the sweep itself walked at least N_LARGE times (it really did miss);
!   0x23  the re-touch of mapping 0 walks EXACTLY once and that walk HITS the
!         TSB -- the entry was evicted by capacity and rebuilt from the TSB;
!   0x25  the entry rebuilt from the FIRST-TOUCH sub-page then covers the
!         mapping BASE with no further walk.
!
! Nothing between the two probe windows may touch memory. The mapping base VA
! is therefore staged into r15 up front, and the 0x0001_0001 comparand is
! BUILT in a register (mov/shll16/add) instead of loaded from a literal pool.
! ===========================================================================
ENTRY(_leg_L)
        mov.l   l_mmucr, r0
        mmu_flush_at r0                 ! leg boundary: AT off, TI, AT on

        mov.l   l_cnt, r10
        mov.l   l_first0, r11
        mov.l   l_base0, r15            ! staged: no memory access between the
                                        ! two probe windows below
        mov.l   l_delta, r14
        mov.l   l_span, r12
        mov     r11, r1
        mov     #N_LARGE, r13
        mov.l   @r10, r7                ! counters before the whole sweep
1:      mov.l   @r1, r2
        mov     r1, r3
        sub     r14, r3
        cmp/eq  r3, r2
        mov     #0x21, r9
        bt      2f
        bra     _fail
        nop
2:      add     r12, r1
        dt      r13
        bf      1b
        mov.l   @r10, r8                ! counters after the whole sweep
        sub     r7, r8
        shlr16  r8                      ! r8 = walks delta
        mov     #N_LARGE, r0
        cmp/hs  r0, r8                  ! T = (walks >= N_LARGE)
        mov     #0x26, r9
        bt      3f
        bra     _fail
        nop

3:      ! ---- probe 1: mapping 0's first-touch VA. Must have been EVICTED. ----
        mov.l   @r10, r4
        mov.l   @r11, r5
        mov.l   @r10, r6

        mov     r11, r3
        sub     r14, r3
        cmp/eq  r3, r5
        mov     #0x22, r9
        bt      4f
        bra     _fail
        nop
4:      mov     r6, r7
        sub     r4, r7                  ! r7 = packed counter delta
        mov     #1, r0
        shll16  r0
        add     #1, r0                  ! r0 = 0x00010001: one walk, one hit
        cmp/eq  r0, r7
        mov     #0x23, r9
        bt      5f
        bra     _fail
        nop

5:      ! ---- probe 2: the mapping BASE, immediately after. Must be covered
        ! ---- by the entry probe 1 just installed, with NO further walk.
        mov.l   @r10, r4
        mov.l   @r15, r5
        mov.l   @r10, r6

        mov     r15, r3
        sub     r14, r3
        cmp/eq  r3, r5
        mov     #0x24, r9
        bt      6f
        bra     _fail
        nop
6:      cmp/eq  r4, r6
        mov     #0x25, r9
        bt      7f
        bra     _fail
        nop
7:      bra     _leg_F
        nop

        .align 2
l_mmucr:        .long 0xFF000010
l_cnt:          .long 0xFF000054
l_first0:       .long _frames + ALIAS_DELTA + FIRST_OFF
l_base0:        .long _frames + ALIAS_DELTA
l_delta:        .long ALIAS_DELTA
l_span:         .long MAP_SPAN

! ===========================================================================
! LEG F -- every mapping still translates correctly after the churn.
!
! N_LARGE base-VA touches with the DTLB thrashing throughout: each one is a
! capacity miss, a walk and a re-install. It is the whole-set version of leg
! L's single probe, and it is what would catch a re-walk that installs the
! RIGHT PTEL under the WRONG VPN (or vice versa) once entries start recycling.
! ===========================================================================
ENTRY(_leg_F)
        mov.l   f_base, r1
        mov.l   f_delta, r14
        mov.l   f_span, r12
        mov     #N_LARGE, r13
1:      mov.l   @r1, r2
        mov     r1, r3
        sub     r14, r3
        cmp/eq  r3, r2
        mov     #0x31, r9
        bt      2f
        bra     _fail
        nop
2:      add     r12, r1
        dt      r13
        bf      1b

        mov.l   f_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off before handing over the result
        mov     #0, r9
        bra     _done
        nop

        .align 2
f_base:         .long _frames + ALIAS_DELTA
f_delta:        .long ALIAS_DELTA
f_span:         .long MAP_SPAN
f_mmucr:        .long 0xFF000010

! ===========================================================================
! Vector block (mmuwalk_common.inc). Reaching either handler is a defect:
! every VA this guard touches under AT=1 has a TSB row, so the walker must
! resolve every miss as a stall.
! ===========================================================================
        mmu_vec_handlers H, 0x42, 0x41

        .balign 4
ENTRY(_code_end)                        ! everything below start is code, and
                                        ! is identity-mapped by _seed_code

! ===========================================================================
! The frames under test. One word per 4 KB page, holding ITS OWN PHYSICAL
! ADDRESS -- that is the entire sentinel scheme, and it needs no table: the
! expected value of any touch is simply VA - ALIAS_DELTA.
!
! N_LARGE mappings x CAP_NSUB sub-pages, contiguous from _frames, which is
! MAP_SPAN-aligned so every mapping base is too.
! ===========================================================================
        .balign MAP_SPAN
_frames:
        .rept   N_LARGE * CAP_NSUB
        .long   .
        .space  PAGE_SZ - 4, 0
        .endr

#endif  ! CONFIG_PRIV_ARCH (leg bodies + vectors + frames)
