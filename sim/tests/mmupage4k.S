! mmupage4k.S -- 4 KB page (pm=0) control guard: two adjacent 4 KB entries with
! distinct frames must NOT merge under masked compare. VA 0x10000 -> PA 0x10000
! (SA), VA 0x11000 -> PA 0x55000 (SB). With AT on, load from 0x10000 must return
! SA (fail 1) and load from 0x11000 must return SB (fail 2). RED if the match
! logic ignores pm=0 and merges them; GREEN once the pm=0 masked compare keeps
! adjacent 4 KB entries distinct.
! (J4, cpu_cache_tb)
!
! ---- walker-install version (retire-LDTLB) --------------------------------
! All three mappings now reach the TLB through the hardware TSB walker instead
! of LDTLB. The property under test is unchanged -- two DISTINCT 4 KB entries
! for ADJACENT VPNs must translate independently, which is what would break if
! the page-mask term over-matched -- so strength is SAME. The PTELs are
! byte-identical to the LDTLB versions apart from bit 0 (V), which the walker
! requires and LDTLB did not.
!
! Setup requirements the LDTLB version did not have:
!   * RB MUST be 0 -- core/cpu.vhd's walk_req is gated on dp_sr.rb = '0' and
!     the cosim starts in bank 1, so without the clear nothing ever walks.
!   * The identity code page MUST be U=0 (0x...C9): once an entry reaches the
!     ITLB, SMEP (core/tlb.vhd:247) rejects a kernel fetch of a U=1 page. The
!     two DATA pages keep U=1; SMEP is an I-side rule only.
!   * The image is padded past the TSB at PA 0x00058000 -- the walker reads the
!     TSB BY PHYSICAL ADDRESS and the cosim backs SRAM only within the loaded
!     image, so a TSB past the image end reads as nothing and every walk
!     silently misses with no fault and no data.
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

        ! ---- Literal pool 1 (setup); the +1020-byte forward reach of
        ! ---- `mov.l @(disp,PC)` is why there are two pools.
        .align 2
p_rbclear:     .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00058008        ! base=0x00058000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! identity code page, U=0 (SMEP)
        .long 0x00010000, 0x00000000, 0x000100E9  ! A: VA 0x10000 -> PA 0x10000
        .long 0x00011000, 0x00000000, 0x000550E9  ! B: VA 0x11000 -> PA 0x55000
_tsb_tab_end:

ENTRY(_run)
        ! --- seed SA at PA 0x10000 and SB at PA 0x55000 via P2 ---
        mov.l   p_sa,     r5    ! sentinel A 0x4A000001
        mov.l   p_sb,     r6    ! sentinel B 0x4B000002
        mov.l   p_p2_a,   r2    ! 0xA0010000  (P2 alias of PA 0x10000)
        mov.l   p_p2_b,   r3    ! 0xA0055000  (P2 alias of PA 0x55000)
        mov.l   r5, @r2
        mov.l   r6, @r3

        ! --- enable AT ---
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0

        ! --- drain write-through buffer ---
        mov     #20, r0
1:      dt      r0
        bf      1b

        ! --- load via translated VA 0x10000 -> must return SA ---
        mov.l   p_va_a, r7      ! 0x00010000
        mov.l   @r7, r8
        mov.l   p_sa, r0
        cmp/eq  r8, r0
        mov     #1, r9          ! fail 1 = VA 0x10000 did not return SA
        bf      _fail

        ! --- load via translated VA 0x11000 -> must return SB ---
        mov.l   p_va_b, r7      ! 0x00011000
        mov.l   @r7, r8
        mov.l   p_sb, r0
        cmp/eq  r8, r0
        mov     #2, r9          ! fail 2 = VA 0x11000 did not return SB
        bf      _fail

        bra     _done
        nop
        .align 2
p_mmucr:   .long 0xFF000010
p_sa:      .long 0x4A000001
p_sb:      .long 0x4B000002
p_p2_a:    .long 0xA0010000
p_p2_b:    .long 0xA0055000
p_va_a:    .long 0x00010000
p_va_b:    .long 0x00011000
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
        ! Pad past the TSB (0x58000..0x59FFF); see the header note.
        .org 0x5A000
