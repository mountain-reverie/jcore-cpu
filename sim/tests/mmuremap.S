! mmuremap.S -- revocation / TLB-desync: a mapping that is REVOKED (here via a
! STALE soft-invalidate) must actually stop translating -- the old PA's contents
! must NOT keep being returned for the VA. Closes the review's "revocation"
! TEST GAP: mmurun flushes+re-walks functionally, but nothing proved a revoked
! mapping is unusable.
!
! Non-identity mappings make the served frame observable: VA=0x00100000 maps
! first to PA1=0x00300000 (holding SENT1), then, after revocation, to
! PA2=0x00400000 (holding SENT2). If the flush is a no-op the VA keeps hitting
! PA1 and returns SENT1 -> caught.
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). The subject -- revocation must
! actually stop translating -- is unchanged. WHICH LAYER is revoked has moved,
! and the reason must not be lost:
!
!   * The walker installs ONLY on a miss, so a resident VA cannot be
!     re-installed; step 2's "re-install with STALE=1, dedup overwrites in
!     place" has no walker-only equivalent.
!   * The walker REFUSES a STALE row outright (core/tlb_walk.vhd requires V=1
!     and STALE=0 before st_install), so a STALE entry can never become
!     resident at all. That makes core/tlb.vhd's `entry.stale = '0'` lookup
!     term unreachable -- defence in depth only. mmustale.S records the same
!     consequence for the same reason.
!
! So revocation is now exercised where software can actually perform it: in the
! TSB. Step 2 sets STALE in the TSB ROW and flushes the TLB (MMUCR.TI = TI|AT;
! the TSB deliberately SURVIVES a TI flush, so the row -- and its STALE bit --
! is what the next walk sees). The requirement is unchanged in substance: after
! revocation the VA must NOT keep being served from PA1, it must fault.
!
! Verdict: WEAKER in exactly one respect, which must not be oversold -- it no
! longer covers a STALE entry already resident in the TLB, because that state
! is unreachable under walker-only install. Otherwise unchanged: the same three
! assertions, the same non-identity PA1/PA2 discrimination.
!
! Flow (single D-load-miss handler at VBR+0x400):
!   setup (RB=0, AT off): publish TSB rows for page 0 identity kernel-exec
!     (code fetches walk in once AT is on) and for VA->PA1; seed PA1=SENT1,
!     PA2=SENT2; revoked=0. Enable AT.
!   step 1: load VA -> walker installs VA->PA1 -> r8 = SENT1.
!   step 2: set STALE in the VA's TSB row, then MMUCR = TI|AT to evict the
!     resident entry. Page 0's row is untouched and valid, so the code page
!     simply walks back in; only the VA is revoked.
!   step 3: load VA -> the walker reads the row, sees STALE, REFUSES it ->
!     DMISS_R -> handler: revoked=1; rewrite the row to PA2 (valid, not
!     stale); plain RTE. The load retries, the walker installs PA2 -> r10.
!   verify: r8==SENT1 (initial mapping served PA1), revoked==1 (the STALE row
!     really stopped translating -> a fault was taken), r10==SENT2 (the VA now
!     serves PA2; PA1's SENT1 is NOT returned -> revocation holds).
!
!   BROKEN core (walker ignores STALE): step 3 installs the stale PA1 row ->
!     no fault -> revoked stays 0 and r10==SENT1 -> FAIL 2 or 3.
!
! PTEL flag bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G
!                                 bit1=STALE bit0=V.
!
! Result codes:
!   0  pass
!   1  r8 != SENT1   -- initial VA->PA1 mapping did not serve PA1
!   2  revoked != 1  -- post-revoke access did NOT miss (STALE not enforced)
!   3  r10 != SENT2  -- VA did not re-map to PA2 (old PA1 still served, or bad)

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

        .text
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

        ! ---- ASIDR = 0. ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed PA1 and PA2 backing via P1 (untranslated); revoked=0. ----
        mov.l   k_bk_pa1, r0 ; mov.l v_sent1, r1 ; mov.l r1, @r0   ! PA1 0x00300000
        mov.l   k_bk_pa2, r0 ; mov.l v_sent2, r1 ; mov.l r1, @r0   ! PA2 0x00400000
        mov.l   k_revoked, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ---- Configure the TSB (base 0x00014000, TSB_SIZE_LOG=8 -> 256 sets
        ! ---- x 32 bytes; HASH_SHIFT=6, HASH_MODE=1) and publish the two rows:
        ! ---- page 0 identity kernel-exec (W|X|C, U=0 -- a kernel fetch of a
        ! ---- U=1 page is an SMEP protection fault) and VA -> PA1. AT is off,
        ! ---- so these are plain P0 stores.
        mov.l   k_tsbbr_addr, r0
        mov.l   k_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   k_tsbcfg_addr, r0
        mov.l   k_tsbcfg_val, r1
        mov.l   r1, @r0

        mov.l   k_tsbslot, r12
        mov.l   k_tab, r14
        mov.l   k_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
        mov.l   @r14+, r8               ! PTEL
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- Remember the VA's SET address: steps 2 and 3 rewrite that row,
        ! ---- and once AT is on the P4 helper is still reachable but the row
        ! ---- must be addressed through P1 (the TSB itself is unmapped).
        mov.l   va, r6
        mov.l   r6, @r12
        mov.l   @r12, r10
        mov.l   k_p1, r0
        or      r0, r10
        mov.l   k_rowptr, r0
        mov.l   r10, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= STEP 1: VA hits PA1 =================
        mov.l   va, r0
        mov.l   @r0, r8                 ! -> SENT1 (no miss)

        ! ================= STEP 2: revoke VA via STALE ===================
        ! Set STALE in the VA's TSB ROW, then evict the TLB with MMUCR = TI|AT.
        ! Both halves are needed and neither alone would do: the row alone
        ! leaves the already-resident entry translating, and the flush alone
        ! would just let the walker re-install the very same valid row. Page
        ! 0's row is untouched and valid, so the code page walks straight back
        ! in and the flush does not immolate the fetch stream.
        mov.l   k_rowptr, r0
        mov.l   @r0, r1                 ! r1 = P1 address of the VA's TSB set
        mov.l   p_ptel_pa1_stale, r2    ! PA1 | W|X|U|D|V | STALE
        mov.l   r2, @(8, r1)
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! TI|AT: flush, AT on

        ! ================= STEP 3: VA now misses -> handler re-maps to PA2 =
        mov.l   va, r0
        mov.l   @r0, r10               ! MISS -> 0x420 handler -> PA2 -> SENT2

        ! ---- Disable AT before touching the sim result register. ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ================= VERIFY =================
        mov.l   v_sent1, r1 ; cmp/eq r1, r8  ; mov #1, r9 ; bf _fail
        mov.l   k_revoked, r0 ; mov.l @r0, r2 ; mov #1, r3
        cmp/eq  r3, r2 ; mov #2, r9 ; bf _fail   ! STALE revoke must have caused a miss
        mov.l   v_sent2, r1 ; cmp/eq r1, r10 ; mov #3, r9 ; bf _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:  .long 0xDFFFFFFF
k_vbr:      .long 0x80000000 + _vbase
k_mmucr:    .long 0xFF000010
k_bk_pa1:   .long 0x00300000
k_bk_pa2:   .long 0x00400000
k_revoked:  .long 0x80002D00
k_rowptr:   .long 0x80002D04            ! P1 address of the VA's TSB set
k_p1:       .long 0x80000000
k_tsbbr_addr:  .long 0xFF000014
k_tsbbr_val:   .long 0x00014008         ! base=0x00014000, TSB_SIZE_LOG=8
k_tsbcfg_addr: .long 0xFF000018
k_tsbcfg_val:  .long 0x00000061         ! HASH_SHIFT=6, HASH_MODE=1
k_tsbslot:     .long 0xFF000048         ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
k_tab:         .long _tsb_tab
k_tab_end:     .long _tsb_tab_end
v_sent1:    .long 0x51111111
v_sent2:    .long 0x52222222
p_ptel_code:.long 0x000000C8            ! PA 0 | W|X|C (kernel code page)
p_pteh_va:  .long 0x00100000            ! VPN of VA
p_ptel_pa1: .long 0x003000F1            ! PA1 0x00300000 | W|X|U|D|V
p_ptel_pa1_stale: .long 0x003000F3      ! PA1 | W|X|U|D|V | STALE (bit1) -> revoked
va:         .long 0x00100000

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! page 0 identity, W|X|C|V, U=0
        .long 0x00100000, 0x00000000, 0x003000F1  ! VA -> PA1, W|X|U|D|V
_tsb_tab_end:
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

#if CONFIG_PRIV_ARCH
        ! ===================== Exception vector base =====================
        .balign 4
_vbase:
        .space 0x400, 0
_v_tlb:                                 ! _vbase + 0x400  (all TLB faults)
        bra     _h_common
        nop

        ! ---- Miss handler: mark revoked, re-map VA->PA2 in the TSB, return.
        ! ---- The row is addressed through P1 because AT is on and the TSB is
        ! ---- unmapped, so a P0 store from the handler would fault here.
_h_common:
        mov.l   H_revoked, r4
        mov     #1, r5
        mov.l   r5, @r4                 ! revoked = 1 (a real fault was taken)
        mov.l   H_rowptr, r4
        mov.l   @r4, r4                 ! r4 = P1 address of the VA's TSB set
        mov.l   H_ptel_pa2, r0
        mov.l   r0, @(8, r4)            ! row data := PA2, valid, NOT stale
        rte                             ! retry: the walker now installs PA2
        nop

        .align 2
H_revoked:  .long 0x80002D00
H_rowptr:   .long 0x80002D04
H_ptel_pa2: .long 0x004000F1            ! PA2 0x00400000 | W|X|U|D|V

        ! ---- The image must reach past the END of the TSB (PA 0x14000..
        ! ---- 0x15FFF): the walker reads the TSB by PHYSICAL address and a
        ! ---- physical alias is backed by SRAM only within the loaded image.
_tsb_backing:
        .space 0x16000, 0
#endif
