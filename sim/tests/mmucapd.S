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
!   0x26  leg L sweep: fewer than N_LARGE walks over the whole sweep -> the
!         sweep did not actually miss, so leg L measured nothing
!   0x31  final re-sweep at the mapping bases: wrong data after the churn
!   0x2F  SETUP: a TSB set was full in BOTH ways while seeding. A harness
!         collision, not a CPU defect -- widen TSB_SIZE_LOG or move the window.
!   0x41  unexpected TLB exception (VBR+0x400). Every VA touched here has a TSB
!         row, so a fault means the walker did not resolve one it could have.
!   0x42  unexpected general exception (VBR+0x100)
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

#define PAGE_SZ      0x1000
#define CAP_NSUB     (1 << (2 * CAP_PM))
#define MAP_SPAN     (PAGE_SZ * CAP_NSUB)
#define FIRST_OFF    (CAP_FIRSTSUB * PAGE_SZ)

! N_SMALL must fit in the DTLB alongside the handful of code pages this file
! reads literal pools out of; N_LARGE must exceed it outright. Shipped DTLB is
! 16 entries (core/cpu.vhd, u_dtlb). Every mapping costs exactly ONE entry
! whatever CAP_PM is, because a superpage is one entry.
#define N_SMALL      6
#define N_LARGE      24

#define ALIAS_DELTA  0x00400000
#define DATA_FLAGS   ((CAP_PM << 8) | 0xE9)
#define CODE_FLAGS   0x000000CD
#define TSB_BASE     0x00F00000
#define TSB_SIZE_LOG 10

        .section .vect
        .long start
        .long 0x00300000                ! stack: deliberately NOT the usual
                                        ! 0x7000, which lands inside _frames
                                        ! and would silently overwrite a
                                        ! sentinel. Nothing here uses it.
        .long start
        .long 0x00300000
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
        bra     _seed_code
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _vecblk
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long TSB_BASE + TSB_SIZE_LOG
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1

! ---------------------------------------------------------------------------
! Seed a TSB row for every code page, start .. _code_end. These are IDENTITY
! and GLOBAL (0xCD = W|X|C|G|V, U=0 for SMEP): the guard's own instruction
! stream and literal pools have to be resolvable the moment AT goes on, and
! they are not what is under test. The walker pulls each in as a STALL on
! first touch, so no exception is ever taken for them.
!
! AT is still off here, so these are plain P0 stores straight at the TSB.
! ---------------------------------------------------------------------------
ENTRY(_seed_code)
        mov.l   c_tsbslot, r12
        mov.l   c_start, r1
        mov.l   c_end, r2
        mov.l   c_flags, r5
        mov.l   c_pagesz, r4
1:      mov     r1, r6
        or      r5, r6                  ! PTEL = page | CODE_FLAGS
        mov.l   r1, @r12                ! ask the P4 slot helper for this VA
        mov.l   @r12, r7                ! r7 = 32-byte-aligned SET address
        mov.l   @(8, r7), r0
        tst     #1, r0                  ! way 0 data word: V clear?
        bt      3f
        add     #16, r7                 ! try way 1
        mov.l   @(8, r7), r0
        tst     #1, r0
        bt      3f
        mov.l   c_full, r0              ! both ways occupied: harness collision
        jmp     @r0
        nop
3:      mov     #0, r0                  ! ASID_TAG = 0
        tsb_fill r7, r1, r0, r6
        add     r4, r1
        cmp/hs  r2, r1
        bf      1b
        bra     _seed_data
        nop

        .align 2
c_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
c_start:        .long start
c_end:          .long _code_end
c_flags:        .long CODE_FLAGS
c_pagesz:       .long PAGE_SZ
c_full:         .long _setup_full

! ---------------------------------------------------------------------------
! Seed a TSB row for every 4 KB page of the alias window. The row's TAG is the
! page's own VPN (the TSB is 4 KB-granular by contract, C1) and its PTEL
! carries the MAPPING BASE's PPN plus CAP_PM, so all CAP_NSUB sub-pages of one
! mapping share a single PTEL and install as ONE TLB entry.
!
!   PPN = (VA - ALIAS_DELTA) & ~(MAP_SPAN - 1)
!
! Seeding every sub-page rather than only the first-touched one is deliberate:
! it means a missing TLB entry shows up as an extra WALK (a named counter
! failure) instead of as an exception, which is a far more legible signal.
! ---------------------------------------------------------------------------
ENTRY(_seed_data)
        mov.l   d_tsbslot, r12
        mov.l   d_va, r1
        mov.l   d_vaend, r2
        mov.l   d_spanmask, r3
        mov.l   d_delta, r4
        mov.l   d_flags, r5
        mov.l   d_pagesz, r8
1:      mov     r1, r6
        sub     r4, r6                  ! r6 = PA of this 4 KB page
        and     r3, r6                  ! r6 = PA of the MAPPING base
        or      r5, r6                  ! r6 = PTEL
        mov.l   r1, @r12
        mov.l   @r12, r7
        mov.l   @(8, r7), r0
        tst     #1, r0
        bt      3f
        add     #16, r7
        mov.l   @(8, r7), r0
        tst     #1, r0
        bt      3f
        mov.l   d_full, r0
        jmp     @r0
        nop
3:      mov     #0, r0
        tsb_fill r7, r1, r0, r6
        add     r8, r1
        cmp/hs  r2, r1
        bf      1b

        ! ---- Enable AT. ----
        mov.l   d_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        bra     _leg_S
        nop

        .align 2
d_tsbslot:      .long 0xFF000048
d_va:           .long _frames + ALIAS_DELTA
d_vaend:        .long _frames + ALIAS_DELTA + N_LARGE * MAP_SPAN
d_spanmask:     .long ~(MAP_SPAN - 1)
d_delta:        .long ALIAS_DELTA
d_flags:        .long DATA_FLAGS
d_pagesz:       .long PAGE_SZ
d_mmucr:        .long 0xFF000010
d_full:         .long _setup_full

ENTRY(_setup_full)
        mov     #0x2F, r9
        bra     _fail
        nop

#else
        bra     _done
        nop
#endif  ! CONFIG_PRIV_ARCH (preamble)

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is not a fail code
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
        ! ---- leg-boundary flush: AT off, MMUCR.TI pulse, AT on. AT must go
        ! ---- off first -- a TI taken with AT=1 unmaps the executing page.
        mov.l   l_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #4, r1
        mov.l   r1, @r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #1, r1
        mov.l   r1, @r0

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
! Vector block. _vecblk is PAGE_SZ-aligned, so `.space 0x100` lands _v_gen
! exactly at VBR+0x100 and the `.balign 0x400` after it lands _v_cap exactly
! at VBR+0x400 (the general handler's body is far shorter than 0x300 bytes).
! Both run with SR.RB=1; r9 is NOT banked, so the code they hand to _fail
! survives.
!
! Reaching either one is a defect: every VA this guard touches under AT=1 has
! a TSB row, so the walker must resolve every miss as a stall.
! ===========================================================================
        .balign PAGE_SZ
_vecblk:
        .space 0x100, 0
_v_gen:                                 ! VBR + 0x100
        mov.l   Hg_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #0x42, r9
        mov.l   Hg_fail, r0
        jmp     @r0
        nop
        .align 2
Hg_mmucr:       .long 0xFF000010
Hg_fail:        .long _fail

        .balign 0x400
_v_cap:                                 ! VBR + 0x400
        mov.l   Ht_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #0x41, r9
        mov.l   Ht_fail, r0
        jmp     @r0
        nop
        .align 2
Ht_mmucr:       .long 0xFF000010
Ht_fail:        .long _fail

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
