! mmupagewalk.S -- realistic D-store TLB-miss handler installing a 16 KB page.
!
! Flow:
!   1. Clear SR.RB=0. Install page 0 (VA 0x0->PA 0x0, 4 KB, C=1) for code.
!      Seed PA 0x10000 = 0, PA 0x11000 = 0 via P2 alias (AT off).
!      Set VBR so VBR+0x440 = _v_store (placed after .space 0x380 pad so
!      VBR = _v_store - 0x440 is a positive address).
!   2. Enable AT (no mapping for VA 0x11000).
!      Store sentinel to VA 0x11000 -> DMISS_W -> _v_store.
!   3. Handler (bank-1 scratch, SR.BL=1):
!      Build PTEL = 0x000101E8 (PA 0x10000, pm=1=16 KB, W|X|U|C).
!      LDC PTEL, LDC ASIDR=0, LDTLB.RN (atomic install+return, no delay slot).
!      LDTLB.RN returns to SPC: re-executes the faulting store.
!   4. Drain write buffer; disable AT.
!      P2-read PA 0x11000 (expect sentinel; fail 1).
!      P2-read PA 0x10000 (expect 0; fail 2).
!
! PTEH-alignment: the hardware captures PTEH = 0x11 (VA[31:12] of 0x11000).
! The handler uses the captured value as-is (no re-alignment to 0x10 needed).
! The masked VPN compare for pm=1 ignores VA[13:12], so PTEH=0x11 covers
! VA 0x10000-0x13FFF.  Relocation: VA 0x11000 -> PA 0x11000.
!
! J4 overlay opcodes:
!   LDC r0,PTEH  = 0x405E   LDC r0,PTEL = 0x406E   LDC r0,ASIDR = 0x407E
!   LDC r0,VBR   = 0x402E   LDTLB       = 0x0038   LDTLB.RN     = 0x0068

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
        ! ---- Ensure RB=0 (keep MD=1) so handler entry causes bank switch. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- Install code page 0: VA 0x0 -> PA 0x0, 4 KB, W|X|U|C ----
        mov     #0, r0
        .word   0x405E          ! LDC r0, PTEH (VPN = 0)
        mov.l   p_ptel_p0, r0   ! 0x000000E8  (PA=0 | W|X|U|C)
        .word   0x406E          ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E          ! LDC r0, ASIDR
        .word   0x0038          ! LDTLB

        ! ---- Seed PA 0x10000 = 0, PA 0x11000 = 0 via P2 alias (AT off) ----
        mov     #0, r1
        mov.l   p_p2_base, r2   ! 0xA0010000  (P2 alias of PA 0x10000)
        mov.l   r1, @r2
        mov.l   p_p2_sub,  r3   ! 0xA0011000  (P2 alias of PA 0x11000)
        mov.l   r1, @r3

        ! ---- VBR = _v_store - 0x440  (so VBR+0x440 = _v_store within page 0) ----
        mov.l   k_vbr, r0
        .word   0x402E          ! LDC r0, VBR

        ! ---- Enable AT (no mapping for VA 0x11000) ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Store sentinel to VA 0x11000 -> DMISS_W -> _v_store -> LDTLB.RN ----
        mov.l   p_sentinel, r5  ! 0x5E91A16C
        mov.l   p_va_sub, r6    ! 0x00011000
        mov.l   r5, @r6         ! fires DMISS_W; LDTLB.RN re-executes this store

        ! ---- (execution resumes here after LDTLB.RN RTE) ----
        ! Drain write buffer
        mov     #20, r0
1:      dt      r0
        bf      1b

        ! ---- Disable AT ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Verify PA 0x11000 == sentinel (store reached the physical page) ----
        mov.l   @r3, r8         ! r3 = 0xA0011000
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9          ! fail 1: sub-page not written to PA 0x11000
        bf      _fail

        ! ---- Verify PA 0x10000 == 0 (16 KB base-page not touched) ----
        mov.l   @r2, r10        ! r2 = 0xA0010000
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9          ! fail 2: PA 0x10000 wrongly written
        bf      _fail

        bra     _done
        nop

        .align 2
p_rbclear:   .long 0xDFFFFFFF
p_ptel_p0:   .long 0x000000E8   ! page 0: PA=0x0 | W|X|U|C
p_p2_base:   .long 0xA0010000   ! P2 alias of PA 0x10000
p_p2_sub:    .long 0xA0011000   ! P2 alias of PA 0x11000
k_vbr:       .long _v_store - 0x440
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A16C
p_va_sub:    .long 0x00011000
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
        ! ===================== DMISS_W handler at VBR+0x440 =====================
        ! Pad so _v_store lands past 0x440 from binary start, keeping VBR
        ! = _v_store - 0x440 as a positive address (avoiding 32-bit wrap, which
        ! is legal but mmustore.S style is simpler to reason about).
        ! _v_store must remain within page 0 (VA < 0x1000) for I-fetch to work
        ! with AT=1.  With ~0x1A0 bytes before this #if, padding 0x2C0 bytes
        ! puts _v_store near 0x460, well within page 0.
        .space 0x2C0, 0
        .balign 4

        ! On exception entry SR.RB=1: r0-r7 are bank-1 scratch, no save needed.
        ! PTEH already holds the captured faulting VPN (0x11 = VA[31:12] of
        ! 0x11000).  Build PTEL = 0x000101E8 (PA 0x10000 | pm=1 | W|X|U|C).
        ! pm=1 masks VPN[13:12] on compare, so entry covers VA 0x10000-0x13FFF.
        ! LDTLB.RN has NO delay slot: it atomically installs and returns to
        ! SPC/SSR, re-executing the faulting store through the new mapping.
_v_store:
        ! Explicitly set PTEH to the 16KB-aligned page base (VPN=0x10, VA 0x10000),
        ! mirroring mmuldtlbr.S's explicit-PTEH pattern.  Build via immediate:
        !   PTEH = 0x00010000 = 1 << 16
        mov     #1, r2
        shll16  r2              ! r2 = 0x00010000
        ! Build PTEL = 0x000101E8:
        !   0x000101E8 = (1 << 16) | (1 << 8) | 0xE8
        !              = PA 0x10000 | pm=1 | W|X|U|C
        mov     #1, r0
        shll16  r0              ! r0 = 0x00010000
        mov     #1, r1
        shll8   r1              ! r1 = 0x00000100  (pm=1 at PTEL[11:8])
        or      r1, r0          ! r0 = 0x00010100
        or      #0xE8, r0       ! r0 = 0x000101E8
        .word   0x425E          ! LDC r2, PTEH  (LDC r2,PTEH = 0x4n5E n=2 -> 0x425E)
        .word   0x406E          ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E          ! LDC r0, ASIDR
        .word   0x0068          ! LDTLB.RN: atomic install + return to SPC (no delay slot)
        nop                     ! padding only (never executed; LDTLB.RN has no delay slot) — matches mmurun.S
#endif
        .org 0x12000
