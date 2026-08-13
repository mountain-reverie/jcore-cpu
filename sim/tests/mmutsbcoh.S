! mmutsbcoh.S -- END-TO-END TSB COHERENCY: a TSB row written by ORDINARY
! CACHEABLE STORES -- the exact path Linux uses -- is the row the hardware
! walker reads and installs, with a DIFFERENT, structurally-valid entry for the
! same VA having been in that slot beforehand.
!
! WHY THIS GUARD EXISTS
! ---------------------
! `core/cpu.vhd` g_dstore_squash replaces db_o.a wholesale with the walker's
! TSB PHYSICAL address during walk_own, but the cacheability inputs the D-cache
! wrapper uses (mmu_o.d_at / mmu_o.d_c -> dcache_cacheable_mux's
! is_cacheable_mmu) were left on the TLB lookup of the CORE's address, which
! during a walk is an unrelated (and for an I-side walk, IDLE) VA. Whether a
! walker TSB read went through the D-cache or bypassed it to main memory was
! therefore a function of whether some UNRELATED page happened to be mapped --
! measured flipping between the two arms across guards and even within a single
! run. The routing is now pinned to region decode on the walker's own physical
! address; the RTL assert in core/cpu.vhd (search "R1") is what locks that,
! since the routing itself is not observable from software.
!
! WHAT THIS GUARD DOES AND DOES NOT PROVE
! ---------------------------------------
! It does NOT distinguish the two routing arms, and cannot: the J-core D-cache
! is WRITE-THROUGH, not write-back. Every store is pushed to memory as
! CACHE_DCMD_WRITESGL_SL (cache/dcache_ccl.vhm) and there is no dirty bit or
! writeback path anywhere under cache/ -- so a TSB row can never sit dirty in
! cache while memory holds something older, and BOTH arms see software's
! stores. (dcache_cacheable_mux.vhd's own header comment calls the cache
! "write-back" and speaks of "dirty-line writeback"; that comment is wrong.
! Measured: with the walker forced to bypass the cache, and with no eviction of
! any kind between the store and the walk, this guard still passes -- i.e. the
! store had already reached memory on its own.)
!
! What it DOES prove is the property that must hold under any routing policy and
! any future cache write policy: software's most recent TSB write is what the
! walker installs. That is the end-to-end invariant a routing change, or a move
! to a write-back cache, would break -- and under a write-back cache the bypass
! arm WOULD break it silently, which is why the invariant is worth pinning now
! rather than after the cache changes.
!
! HOW THE SCENARIO IS CONSTRUCTED
! -------------------------------
! Two identity data pages are seeded with distinguishable words:
!   PA 0x00042000 = 0xA5A5A5A5   (the CORRECT target)
!   PA 0x00043000 = 0x5A5A5A5A   (the STALE target)
! Then, for the single fault VA 0x00042000:
!   1. a STALE TSB entry (PTEL -> PA 0x00043000) is written to way 0 of its set;
!   2. the GOOD entry (PTEL -> PA 0x00042000) then overwrites the same way with
!      ordinary cacheable stores, in jcore_tsb_write_entry()'s data / tag_lo /
!      tag_hi order (the tsb_fill macro);
!   3. AT is enabled and the fault VA is loaded.
! A walker that reads what software wrote installs PA 0x00042000 and the load
! returns 0xA5A5A5A5. A walker that reads the superseded row installs
! PA 0x00043000 and returns 0x5A5A5A5A -- A WRONG TRANSLATION WITH NO
! EXCEPTION. Both entries are structurally valid, so nothing else in the machine
! can tell them apart: the returned WORD is the only witness.
!
! Between the good store and the test load there must be NO cacheable data
! access at all -- not even a literal-pool load -- so that nothing can refresh
! or reorder the row under test. Everything the tail needs is preloaded into
! registers first; only P4 (uncacheable) MMIO and instruction fetches happen in
! that window.
!
! The code page is mapped the way the other walker guards map it: a GLOBAL TSB
! entry in way 1 that the walker installs on the first I-fetch after AT goes on.
!
! Registered under BOTH cpu_tb and cpu_cache_tb (sim/mmu_sim.sh and
! .github/workflows/full-regression.yml): only cpu_cache_tb has a D-cache in the
! path at all, so only it exercises the routing this guard was written for.
!
! Result codes:
!   1  the load returned the STALE word (or anything else): the walker did not
!      install the row software last wrote -- TSB INCOHERENCY
!   2  an exception was taken (VBR+0x400 stub entered, or SPC changed)
!   3  SSR changed -> an exception was taken
!   4  EXPEVT changed -> an exception was taken
!   5  cnt_hits did not advance across the access -> the walker did not resolve
!      THIS access from the TSB, so check 1 proved nothing
!   6  the two data pages did not read back distinguishably before the test
!      (the construction itself is broken -- guards against a vacuous pass in
!      which both PAs happen to hold the same word)
!
! Mutation-proven -- both of these give Result=1, verified:
!   p_ptel_good -> 0x000430E9   (good entry made to point at the stale page)
!   p_expect    -> 0xA5A5A5A6   (comparand no longer matches the seeded word)
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

        ! ---- Ensure RB=0 (bank 0). Without this no walk arms at all. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_fault - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed both data pages (AT off, identity PA == VA). ----
        mov.l   p_pa_good, r2
        mov.l   p_seed_good, r3
        mov.l   r3, @r2                 ! [0x00042000] = 0xA5A5A5A5
        mov.l   p_pa_stale, r2
        mov.l   p_stale_word, r3
        mov.l   r3, @r2                 ! [0x00043000] = 0x5A5A5A5A

        ! ---- 6: prove the two pages are distinguishable BEFORE the test.
        ! ---- If they read back equal, check 1 could never fail and the whole
        ! ---- guard would be vacuous. ----
        mov.l   p_pa_good, r2
        mov.l   @r2, r4
        mov.l   p_pa_stale, r2
        mov.l   @r2, r5
        cmp/eq  r4, r5
        mov     #6, r9
        bt      _fail_at

        ! ---- Configure the TSB via MMIO (cold-path config registers). ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR  = 0x00010006
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG = 0x00000061

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR   (ASID 0 throughout)
        nop
        nop

        ! ---- Code page -> way 1 of ITS set. GLOBAL, U=0 (SMEP). The set
        ! ---- address is asked of the P4 slot helper (0xFF000048), never
        ! ---- hand-computed. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = code SET address
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- STALE data entry -> way 0 of the fault VA's set. PTEL points at
        ! ---- PA 0x00043000, the WRONG page. Same helper. ----
        mov.l   p_vpn,  r1
        mov     #0, r2
        mov.l   p_ptel_stale, r3
        mov.l   r1, @r12                ! write VA -> helper
        mov.l   @r12, r13               ! r13 = data SET address
        tsb_fill r13, r1, r2, r3

        ! PRELOAD EVERYTHING THE TAIL NEEDS FIRST. From the good store until the
        ! test load there must be NO cacheable data access whatsoever -- not
        ! even a literal-pool load. The literal pool lives in .text at a low
        ! address whose D-cache index can collide with the TSB set's, so an
        ! inline literal load evicts and refills the row under test between the
        ! store and the walk. Under today's write-through cache that is merely
        ! noise, but it is exactly the kind of interference that would decide
        ! the outcome under any other write policy, and it would do so
        ! invisibly -- the guard would keep passing while testing nothing.
        ! Keep this window clean. Instruction fetches are safe (they go to the
        ! I-cache) and the P4 MMIO accesses below are uncacheable by region.
        mov.l   p_mmucr, r6             ! r6  = 0xFF000010
        mov     #1, r7                  ! r7  = MMUCR.AT
        mov.l   p_sent_spc, r8          ! r8  = SPC sentinel
        mov.l   p_sent_ssr, r14         ! r14 = SSR sentinel
        mov.l   p_walkcnt, r5           ! r5  = 0xFF000054
        mov.l   p_testva, r4            ! r4  = the fault VA itself
        mov.l   p_vpn,  r1
        mov     #0, r2
        mov.l   p_ptel_good, r3
        tsb_fill r13, r1, r2, r3

        ! ---- From here to the test load: no cacheable data access. ----
        mov.l   r7, @r6                 ! AT on               (P4, uncached)
        .word   0x804E                  ! LDC r8,  SPC
        .word   0xE03E                  ! LDC r14, SSR
        mov.l   @r5, r11                ! cnt_hits before     (P4, uncached)
        extu.w  r11, r11

        ! ---- Take the miss: the walker must resolve it from the row software
        ! ---- wrote LAST, not the superseded one. ----
        mov.l   @r4, r4                 ! <-- TLB miss; walker installs & replays

        ! ---- 1: did the walker use the row software actually wrote? ----
        mov.l   p_expect, r5
        cmp/eq  r4, r5
        mov     #1, r9
        bf      _fail_at

        ! ---- 2: SPC untouched? ----
        .word   0x0042                  ! STC SPC, r0
        mov.l   p_sent_spc, r1
        cmp/eq  r0, r1
        mov     #2, r9
        bf      _fail_at

        ! ---- 3: SSR untouched? ----
        .word   0x0032                  ! STC SSR, r0
        mov.l   p_sent_ssr, r1
        cmp/eq  r0, r1
        mov     #3, r9
        bf      _fail_at

        ! ---- 4: EXPEVT never latched? ----
        mov.l   p_expevt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #4, r9
        bf      _fail_at

        ! ---- 5: did the walker actually resolve THIS access? ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        cmp/eq  r11, r1
        mov     #5, r9
        bt      _fail_at

        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

_fail_at:
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD ! identity: PPN=start, W|X|C|G|V, U=0
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_pa_good:      .long 0x00042000
p_pa_stale:     .long 0x00043000
! p_seed_good is what is STORED into the good page; p_expect is what the test
! load is COMPARED against. They are deliberately two separate literals holding
! the same value: a single shared literal makes the guard immune to mutation --
! corrupting it changes the seed and the comparand together and the guard still
! passes (measured). Mutating EITHER of these alone must now produce Result=1.
p_seed_good:    .long 0xA5A5A5A5
p_expect:       .long 0xA5A5A5A5
p_stale_word:   .long 0x5A5A5A5A
p_vpn:          .long 0x00042000
p_ptel_good:    .long 0x000420E9        ! PA 0x00042000 | V|C|U|X|W
p_ptel_stale:   .long 0x000430E9        ! PA 0x00043000 | V|C|U|X|W  (WRONG page)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_testva:       .long 0x00042000
p_sent_spc:     .long 0xDEADBE00
p_sent_ssr:     .long 0x40000000
p_expevt:       .long 0xFF000024
p_walkcnt:      .long 0xFF000054        ! walker counter window (P4, RO)

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
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
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
        ! ================================================================
        ! MISS-vector stub at VBR+0x400. Reaching it means a real exception
        ! was taken during what should have been a stall-and-walk hit.
        ! ================================================================
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #2, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
