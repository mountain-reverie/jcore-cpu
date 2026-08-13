! mmupage1m.S -- 1 MB page: a sub-page access hits the one entry and relocates
! (J4, cpu_cache_tb). RED on fixed-4KB RTL (VA 0x101000 unmapped); GREEN
! once PageMask=4 makes one entry cover VA 0x100000-0x1FFFFF and relocate per offset.
! Sub-region at offset 0x1000 into the 1MB page (keeps image at ~1 MB).
!
! ---- walker-install version (retire-LDTLB) --------------------------------
! The 1 MB entry now reaches the TLB through the hardware TSB walker. THE
! SUPERPAGE TERM IS WHAT MAKES THIS DELICATE, and a naive migration silently
! destroys it: the walker's TSB tag compare is EXACT on the 4 KB VPN even for a
! superpage entry, so a TSB row on VA 0x101000 would make the store succeed
! whether or not the INSTALLED ENTRY covers 1 MB -- the guard would quietly
! become a 4 KB test.
!
! The WITNESS that the superpage term is doing the work is the WALK COUNTER,
! not the absence of a TSB row:
!   1. LOAD from VA 0x00100800 -- misses, walks, installs the 1 MB entry
!   2. snapshot cnt_walks/cnt_hits (0xFF000054)
!   3. STORE to VA 0x00101000, a DIFFERENT 4 KB VPN
!   4. the counter must NOT have moved (result 3). If the page-mask term were
!      broken, step 3 would miss, WALK, install and then succeed -- the data
!      checks would all still pass and ONLY the counter catches it. Result 3 is
!      what keeps this a superpage test instead of a 4 KB test.
! The sub-page's own TSB row is present but PROVABLY NEVER READ, which is
! exactly what result 3 asserts. STRONGER than the LDTLB version, which
! asserted only that the store landed.
!
! ---- a measured anomaly, recorded rather than worked around ---------------
! Removing the sub-page row entirely -- the construction that looks strictly
! cleaner -- passes under cpu_tb but FAILS under cpu_cache_tb: the sub-page
! STORE completes, then the next access takes an exception, banks away (r0-r7
! switch) and runs off into a wild SRAM address. With the row present (never
! read, per result 3) the same sequence is green on both tops. A walker-
! installed superpage therefore behaves differently under the cached top
! depending on TSB contents the counter says were not consulted. NOT
! root-caused here; it is a walker/cache interaction deserving its own
! investigation, and it is why this guard keeps a row it does not need.
!
! Setup requirements the LDTLB version did not have:
!   * RB MUST be 0 -- core/cpu.vhd's walk_req is gated on dp_sr.rb = '0' and
!     the cosim starts in bank 1, so without the clear nothing ever walks.
!   * The identity code page MUST be U=0 (0x...C9): once an entry reaches the
!     ITLB, SMEP (core/tlb.vhd:247) rejects a kernel fetch of a U=1 page.
!   * The image is padded past the TSB at PA 0x00104000 -- the walker reads the TSB
!     BY PHYSICAL ADDRESS and the cosim backs SRAM only within the loaded
!     image, so a TSB past the image end reads as nothing and every walk
!     silently misses with no fault and no data.
!
! Result code 3 is new: the sub-page access WALKED, so it was not translated by
! the page-mask term of the already-installed entry.
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
ENTRY(start)
#if CONFIG_PRIV_ARCH
        ! ---- Ensure RB=0 (bank 0); see the header note. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
        ! ---- Fill the TSB from the (VA, ASID, PTEL) table. Each row's set
        ! ---- address comes from the P4 helper under that row's ASID, so no
        ! ---- hash is hand-computed. AT is off: plain P0 stores.
        ! ---- The sub-page row is present but never read; see the header.
        mov.l   p_tsbslot, r12
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6              ! VA
        mov.l   @r14+, r7              ! ASID
        mov.l   @r14+, r8              ! PTEL
        mov     r7, r0
        .word   0x407E                 ! LDC r0, ASIDR
        nop
        nop
        mov.l   r6, @r12               ! write VA -> helper
        mov.l   @r12, r10              ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b
        bra     _run
        nop

        ! ---- Literal pool 1 (setup). `mov.l @(disp,PC)` is FORWARD-only and
        ! ---- reaches +1020 bytes, hence two pools.
        .align 2
p_rbclear:     .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00104008        ! base=0x00104000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! identity code page, U=0 (SMEP)
        .long 0x00100000, 0x00000000, 0x001004E9  ! the 1 MB superpage
        .long 0x00101000, 0x00000000, 0x001004E9  ! sub-page row -- see the header
_tsb_tab_end:

ENTRY(_run)
        ! clear PA 0x100000 and 0x101000 via P2
        mov     #0, r1
        mov.l   p_p2_base, r2          ! 0xA0100000
        mov.l   r1, @r2
        mov.l   p_p2_sub,  r3          ! 0xA0101000
        mov.l   r1, @r3
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! ---- Step 1: touch the BASE VPN so the walker installs the superpage.
        mov.l   q_va_base, r7
        mov.l   @r7, r11
        ! ---- Snapshot the walk counter AFTER that install. ----
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        ! ---- Step 2: the sub-page store. No TSB row -> only the page-mask
        ! ---- term of the entry installed in step 1 can translate it.
        ! store SENTINEL through translated VA 0x101000 (2nd 4KB sub-region of 1MB page)
        mov.l   p_sentinel, r5         ! sentinel 0x5E91A16C
        mov.l   p_va_sub, r6           ! 0x00101000
        mov.l   r5, @r6
        ! drain write-through buffer
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back via P2 (uncached, AT-independent)
        mov.l   @r3, r8                ! PA 00101000
        mov.l   @r2, r10               ! PA 00100000
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = sub-page didn't hit/relocate to PA 0x101000
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = base PA 0x100000 wrongly written
        bf      _fail
        ! ---- Step 3: the sub-page access must NOT have walked. ----
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #3, r9                 ! fail 3 = sub-page walked, not a superpage hit
        bf      _fail
        bra     _done
        nop
        .align 2
q_va_base:   .long 0x00100800          ! same 4 KB VPN as the TSB row, but a
                                       ! different cache line from the words
                                       ! this guard reads back through P2
q_walkcnt:   .long 0xFF000054          ! [31:16]=cnt_walks [15:0]=cnt_hits
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A16C
p_p2_base:   .long 0xA0100000
p_p2_sub:    .long 0xA0101000
p_va_sub:    .long 0x00101000
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
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC
        ! Pad past the TSB; see the header note.
        .org 0x106000
