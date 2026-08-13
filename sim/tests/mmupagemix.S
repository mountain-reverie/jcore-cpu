! mmupagemix.S -- mixed-page-size coexistence: 16KB and 4KB entries installed
! together (16KB first). VA 0x12000 must hit the 16KB entry (PA 0x12000); VA
! 0x14000 must hit the 4KB entry (PA 0x44000). Proves per-entry PageMask with
! no cross-size aliasing. (J4, cpu_cache_tb)
!
! ---- walker-install version (retire-LDTLB) --------------------------------
! This guard's whole point is INSTALL ORDER: a 16 KB entry and a 4 KB entry
! whose VAs are 16 KB apart must coexist without the superpage over-matching,
! and it must not matter which went in first. mmupagemix and mmupagemix2 are
! the two orders.
!
! Under walker-only install there is no software install sequence left -- the
! walker installs on a MISS, so install order IS ACCESS ORDER. This guard
! therefore establishes its order by TOUCHING the 16 KB page and then the 4 KB page before any
! check runs. That is a faithful translation, not a weakening: access order is
! now the only order the hardware has.
!
! A NEW result 3 also makes it STRONGER than the LDTLB version on the axis it
! is named for. Check A (load VA 0x12000) previously proved only that the load
! returned SA, which a plain 4 KB entry for VA 0x12000 satisfies just as well.
! The guard now snapshots the walk counters (0xFF000054) after both installs
! and requires check A NOT to have walked, so the 16 KB page-mask term is what
! translated it. If that term were broken, check A would miss, walk the
! (otherwise unread) VA 0x12000 row, install and still return SA -- both data
! checks would pass and only result 3 catches it.
!
! Order under test here: 16 KB installed FIRST.
!
! Setup requirements walker-only install adds, none of which LDTLB had:
!   * RB MUST be 0 -- core/cpu.vhd's walk_req is gated on dp_sr.rb = '0' and
!     the cosim starts in bank 1, so without the clear nothing ever walks and
!     the failure is silent (MMUCR reads back 1, the walk counter stays 0).
!   * The identity code page must be U=0: once an entry reaches the ITLB, SMEP
!     (core/tlb.vhd:247, kernel fetch of a user page) rejects it.
!   * The image is padded past the END of the TSB -- the walker reads the TSB
!     BY PHYSICAL ADDRESS and the cosim backs SRAM only within the loaded
!     image, so a TSB beyond it reads as nothing and every walk silently
!     misses with no fault and no data.
!   * The VA 0x12000 row is present but PROVABLY NEVER READ (result 3 is that
!     assertion). It is kept only because dropping it trips the cpu_cache_tb
!     anomaly recorded in mmupage16k.S.
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
        ! ---- Ensure RB=0 (bank 0). core/cpu.vhd's walk_req is gated on
        ! ---- dp_sr.rb = '0' and the cosim starts in bank 1, so without this
        ! ---- NO walk is ever armed: AT comes on, nothing installs, and the
        ! ---- walk counter at 0xFF000054 never leaves zero.
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
        ! ---- Fill the TSB from the (VA, ASID, PTEL) table; each row's set
        ! ---- address comes from the P4 helper under that row's ASID, so no
        ! ---- hash is hand-computed. AT is off: plain P0 stores.
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
        ! ---- reaches +1020 bytes, so migrated bodies need two pools.
        .align 2
p_rbclear:     .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00048008        ! base=0x00048000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! identity code page, U=0 (SMEP)
        .long 0x00010000, 0x00000000, 0x000101E9  ! 16 KB page, PA 0x10000, pm=1
        .long 0x00012000, 0x00000000, 0x000101E9  ! sub-page row -- never read
        .long 0x00014000, 0x00000000, 0x000440E9  ! 4 KB page, PA 0x44000, pm=0
_tsb_tab_end:

ENTRY(_run)
        ! --- seed sentinels via P2 (uncached physical alias) ---
        ! SA = 0xAAAA0001 at PA 0x12000 (sub-region of the 16KB page)
        mov.l   p_sa, r5
        mov.l   p_p2_12k, r1   ! 0xA0012000
        mov.l   r5, @r1
        ! SB = 0xBBBB0002 at PA 0x44000 (the 4KB page's PA)
        mov.l   p_sb, r6
        mov.l   p_p2_44k, r2   ! 0xA0044000
        mov.l   r6, @r2

        ! --- enable AT ---
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0

        ! --- drain write-through buffer ---
        mov     #20, r0
1:      dt      r0
        bf      1b

        ! ---- Establish INSTALL ORDER by access order; see the header. The
        ! ---- 16 KB page is touched at VA 0x10800 -- same 4 KB VPN as its row,
        ! ---- but not a word any check reads back.
        mov.l   q_va_16k_base, r11
        mov.l   @r11, r12
        mov.l   q_va_14k, r11
        mov.l   @r11, r12
        ! ---- Snapshot the walk counters AFTER both installs. ----
        mov.l   q_walkcnt, r11
        mov.l   @r11, r13

        ! --- check A: load VA 0x12000 -> must return SA (16KB entry relocation) ---
        mov.l   p_va_12k, r7   ! 0x00012000
        mov.l   @r7, r8
        mov.l   p_sa, r0
        cmp/eq  r8, r0
        mov     #1, r9         ! fail 1: VA 0x12000 did not relocate to PA 0x12000
        bf      _fail

        ! ---- Check A must NOT have walked: only the 16 KB page-mask term can
        ! ---- have translated VA 0x12000. See the header.
        mov.l   q_walkcnt, r11
        mov.l   @r11, r12
        cmp/eq  r13, r12
        mov     #3, r9         ! fail 3: VA 0x12000 walked, so no 16 KB coverage
        bf      _fail

        ! --- check B: load VA 0x14000 -> must return SB (4KB entry, PA 0x44000) ---
        mov.l   p_va_14k, r7   ! 0x00014000
        mov.l   @r7, r8
        mov.l   p_sb, r0
        cmp/eq  r8, r0
        mov     #2, r9         ! fail 2: VA 0x14000 did not hit 4KB entry at PA 0x44000
        bf      _fail

        bra     _done
        nop

        .align 2
q_va_16k_base: .long 0x00010800   ! base VPN of the 16 KB page
q_va_14k:      .long 0x00014000
q_walkcnt:     .long 0xFF000054   ! [31:16]=cnt_walks [15:0]=cnt_hits
p_mmucr:    .long 0xFF000010
p_sa:       .long 0xAAAA0001
p_sb:       .long 0xBBBB0002
p_p2_12k:   .long 0xA0012000
p_p2_44k:   .long 0xA0044000
p_va_12k:   .long 0x00012000
p_va_14k:   .long 0x00014000
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
        ! Pad past the TSB (0x48000..0x49FFF); see the header note.
        .org 0x4A000
