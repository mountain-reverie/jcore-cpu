! mmup4alias.S -- Phase 3 Task 1: prove the new read-only P4 aliases return
! the SAME value as their STC counterpart, and that the walker-counter P4
! alias (0xFF000054) mirrors the P2 debug window (0xABCD0F00).
!
! This is the ONLY window in which the alias-vs-STC comparison is possible:
! Task 4 of this phase retires the STC PTEH/PTEL/ASIDR forms, after which the
! oracle this guard uses is gone. See docs/superpowers/specs/
! 2026-08-09-hardware-tsb-walker-design.md P3.1/P3.2 and
! .superpowers/sdd/2026-08-11-tsb-walker-phase3/task-1-brief.md.
!
! Checks:
!   1  0xFF000000 (PTEH alias)  != STC PTEH,Rn
!   2  0xFF000004 (PTEL alias)  != STC PTEL,Rn
!   3  0xFF000038 (ASIDR alias) != STC ASIDR,Rn
!   4  0xFF000054 (TSBCNT alias) != 0xABCD0F00 (P2 window) BEFORE any walk
!   5  walk counter word never advanced -> the walk that should bump it for
!      check 6 did not happen (setup defect, not the aliasing under test)
!   6  0xFF000054 (TSBCNT alias) != 0xABCD0F00 (P2 window) AFTER a real walk
!      (proves the alias tracks live counter state, not a latched snapshot)
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

        ! ---- VBR = _v_fault - 0x400 (unused unless setup is broken; keeps a
        ! ---- stray fault from running off into garbage). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ================= 1: PTEH alias vs STC ==========================
        mov.l   p_pteh_val, r0
        .word   0x405E                  ! LDC r0, PTEH
        .word   0x018B                  ! STC PTEH, r1   (0000 0001 1000 1011)
        mov.l   p_pteh_alias, r2
        mov.l   @r2, r3
        cmp/eq  r1, r3
        mov     #1, r9
        bf      _fail_at

        ! ================= 2: PTEL alias vs STC ==========================
        mov.l   p_ptel_val, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x019B                  ! STC PTEL, r1   (0000 0001 1001 1011)
        mov.l   p_ptel_alias, r2
        mov.l   @r2, r3
        cmp/eq  r1, r3
        mov     #2, r9
        bf      _fail_at

        ! ================= 3: ASIDR alias vs STC ==========================
        mov.l   p_asidr_val, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x01BB                  ! STC ASIDR, r1  (0000 0001 1011 1011)
        mov.l   p_asidr_alias, r2
        mov.l   @r2, r3
        cmp/eq  r1, r3
        mov     #3, r9
        bf      _fail_at

        ! ================= 4: TSBCNT alias vs P2 window (before) =========
        mov.l   p_walkcnt_p2, r0
        mov.l   @r0, r1
        mov.l   p_walkcnt_p4, r0
        mov.l   @r0, r2
        cmp/eq  r1, r2
        mov     #4, r9
        bf      _fail_at

        ! ---- Drive one real walk: same TSB setup as mmuwalkhit.S. ----
        ! Map the code page identity (SMEP-safe: U cleared).
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        mov.l   p_data_pa, r2
        mov.l   p_expect, r3
        mov.l   r3, @r2                 ! [0x00042000] = 0xA5A5A5A5

        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG

        mov.l   p_tsb_set, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_data, r3
        tsb_fill r0, r1, r2, r3

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on

        mov.l   p_testva, r0
        mov.l   @r0, r4                 ! take the walk-hit miss

        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off

        ! ================= 5: the walk must have actually run =============
        mov.l   p_walkcnt_p2, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #5, r9
        bt      _fail_at

        ! ================= 6: TSBCNT alias vs P2 window (after) ==========
        mov.l   p_walkcnt_p2, r0
        mov.l   @r0, r1
        mov.l   p_walkcnt_p4, r0
        mov.l   @r0, r2
        cmp/eq  r1, r2
        mov     #6, r9
        bf      _fail_at

        bra     _done
        nop
_fail_at:
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off (harmless if already off)
        bra     _fail
        nop

        .align 2
p_rbclear:       .long 0xDFFFFFFF
p_vbr_val:       .long _v_fault - 0x400
p_pteh_val:      .long 0x12345000
p_pteh_alias:    .long 0xFF000000
p_ptel_val:      .long 0x000067E9
p_ptel_alias:    .long 0xFF000004
p_asidr_val:     .long 0x000000AB
p_asidr_alias:   .long 0xFF000038
p_walkcnt_p2:    .long 0xABCD0F00
p_walkcnt_p4:    .long 0xFF000054
p_pteh_code:     .long start
p_ptel_code:     .long start + 0x000000C8 ! identity: PPN=start, U cleared (SMEP)
p_data_pa:       .long 0x00042000
p_expect:        .long 0xA5A5A5A5
p_tsb_set:       .long 0x00010060        ! set for VA 0x00042000 (proven, mmuwalkhit.S)
p_vpn:           .long 0x00042000
p_asid:          .long 0x00000000
p_ptel_data:     .long 0x000420E9        ! PA 0x00042000 | V|C|U|X|W (0xE9)
p_tsbbr_addr:    .long 0xFF000014
p_tsbbr_val:     .long 0x00010006
p_tsbcfg_addr:   .long 0xFF000018
p_tsbcfg_val:    .long 0x00000061
p_testva:        .long 0x00042000
p_mmucr:         .long 0xFF000010

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
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400 (should never be hit)
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #9, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
