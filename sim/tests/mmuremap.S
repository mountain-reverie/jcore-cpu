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
! Flow (single D-load-miss handler at VBR+0x420):
!   setup (RB=0, AT off): map page 0 identity kernel-exec (code fetches hit
!     once AT is on); seed PA1=SENT1, PA2=SENT2; revoked=0; direct-LDTLB
!     VA->PA1. Enable AT.
!   step 1: load VA -> HITS PA1 -> r8 = SENT1 (mapping works; no miss).
!   step 2: re-install VA with STALE=1 (dedup overwrites in place), soft-
!     invalidating just the VA entry (page 0 stays live).
!   step 3: load VA -> MISSES -> handler: revoked=1; install VA->PA2 via
!     LDTLB.RN (PTEH holds the faulting VPN); return. Load completes -> r10.
!   verify: r8==SENT1 (initial mapping served PA1), revoked==1 (the STALE
!     entry really stopped matching -> a miss was taken), r10==SENT2 (the VA now
!     serves PA2; PA1's SENT1 is NOT returned -> revocation holds).
!
!   BROKEN core (STALE not enforced): step 3 HITS the stale PA1
!     entry -> no miss -> revoked stays 0 and r10==SENT1 -> FAIL 2 or 3.
!
! Non-vacuity: dropping the entry.stale='0' term from tlb.vhd's match makes
! step 3 hit the stale entry -> revoked==0 -> FAIL.
!
! PTEL flag bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G
!                                 bit1=STALE bit0=V.
!
! Result codes:
!   0  pass
!   1  r8 != SENT1   -- initial VA->PA1 mapping did not serve PA1
!   2  revoked != 1  -- post-revoke access did NOT miss (STALE not enforced)
!   3  r10 != SENT2  -- VA did not re-map to PA2 (old PA1 still served, or bad)

#include "sim_instr.h"
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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

        ! ---- Map page 0 identity kernel-exec (W|X|C, U=0) for code fetch. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN 0)
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Install VA=0x00100000 -> PA1=0x00300000 directly (AT off). ----
        mov.l   p_pteh_va, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN of VA)
        mov.l   p_ptel_pa1, r0         ! PA1 | W|X|U|D|V
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= STEP 1: VA hits PA1 =================
        mov.l   va, r0
        mov.l   @r0, r8                 ! -> SENT1 (no miss)

        ! ================= STEP 2: revoke VA via STALE ===================
        ! Re-install VA with STALE=1: dedup overwrites the VA->PA1 entry in
        ! place, soft-invalidating it (the lookup match requires stale='0').
        ! Only the VA mapping is revoked -- page 0 (code) stays live, so a
        ! global TI flush's code-fetch self-immolation is avoided, and this
        ! exercises the H-I1 STALE revocation primitive directly.
        mov.l   p_pteh_va, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN of VA)
        mov.l   p_ptel_pa1_stale, r0   ! PA1 | W|X|U|D|V | STALE
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

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
v_sent1:    .long 0x51111111
v_sent2:    .long 0x52222222
p_ptel_code:.long 0x000000C8            ! PA 0 | W|X|C (kernel code page)
p_pteh_va:  .long 0x00100000            ! VPN of VA
p_ptel_pa1: .long 0x003000F1            ! PA1 0x00300000 | W|X|U|D|V
p_ptel_pa1_stale: .long 0x003000F3      ! PA1 | W|X|U|D|V | STALE (bit1) -> revoked
va:         .long 0x00100000
#endif

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

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! ===================== Exception vector base =====================
        .balign 4
_vbase:
        .space 0x420, 0
_v_load:                                ! _vbase + 0x420  (DMISS_R)
        bra     _h_common
        nop

        ! ---- Miss handler: mark revoked, install VA->PA2, return. ----
_h_common:
        mov.l   H_revoked, r4
        mov     #1, r5
        mov.l   r5, @r4                 ! revoked = 1 (a real miss was taken)
        mov.l   H_ptel_pa2, r0
        .word   0x406E                  ! LDC r0, PTEL  (PA2 image)
        .word   0x0078                  ! LDTLB.RN (install VA->PA2 + return)

        .align 2
H_revoked:  .long 0x80002D00
H_ptel_pa2: .long 0x004000F1            ! PA2 0x00400000 | W|X|U|D|V
#endif
