! mmup4alias.S -- the read-only P4 MMU-CSR aliases are the ONLY way to read
! PTEH/PTEL/ASIDR and the walker counters, so this guard proves each alias
! returns live CSR state.
!
! ORIGINALLY this compared every alias against its `STC <csr>,Rn` counterpart,
! and the walker-counter alias (0xFF000054) against the P2 debug window
! (0xABCD0F00). Both oracles were retired in the same commit as this rewrite:
! the STC MMU-read encodings and the P2 window are gone, and the aliases are
! now the sole readers. The comparison is therefore no longer expressible.
!
! What replaces it is a WRITE-THEN-READ oracle, which needs no second reader:
! drive the CSR through LDC (a distinct, non-trivial bit pattern per register)
! and require the alias to return exactly that value. That still catches the
! defects the STC comparison caught -- a mis-decoded P4 offset, an alias wired
! to the wrong CSR, a latched-instead-of-live read -- because the three values
! are mutually distinct, so any cross-wiring reads back another register's
! pattern. The counter alias keeps a before/after-a-real-walk check, which is
! what proved it live rather than a snapshot.
!
! Checks:
!   1  0xFF000000 (PTEH alias)  != the value LDC wrote to PTEH
!   2  0xFF000004 (PTEL alias)  != the value LDC wrote to PTEL
!   3  0xFF000038 (ASIDR alias) != the value LDC wrote to ASIDR
!   4  0xFF000054 (TSBCNT alias) nonzero BEFORE any walk (must start clean)
!   5  0xFF000054 (TSBCNT alias) still zero AFTER a walk -> the walk that
!      should bump it did not happen (setup defect, not the aliasing)
!   6  0xFF000000 (PTEH alias) does not reflect the LAST LDC PTEH write
!      (the walk sequence rewrote PTEH; proves the alias is live, not latched)
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

        ! ================= 1: PTEH alias vs the value LDC wrote ==========
        mov.l   p_pteh_val, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_pteh_alias, r2
        mov.l   @r2, r3
        cmp/eq  r0, r3
        mov     #1, r9
        bf      _fail_at

        ! ================= 2: PTEL alias vs the value LDC wrote ==========
        mov.l   p_ptel_val, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   p_ptel_alias, r2
        mov.l   @r2, r3
        cmp/eq  r0, r3
        mov     #2, r9
        bf      _fail_at

        ! ================= 3: ASIDR alias vs the value LDC wrote =========
        mov.l   p_asidr_val, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p_asidr_alias, r2
        mov.l   @r2, r3
        cmp/eq  r0, r3
        mov     #3, r9
        bf      _fail_at

        ! ================= 4: TSBCNT alias reads clean before any walk ====
        mov.l   p_walkcnt_p4, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #4, r9
        bf      _fail_at

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

        ! ---- Code page: the identity mapping LDTLB used to install is now a
        ! ---- GLOBAL TSB entry the walker installs on the first fetch after AT
        ! ---- goes on. Set address from the P4 slot helper, way 1. The
        ! ---- `LDC r0, PTEH` below is KEPT: check 6 requires that a PTEH write
        ! ---- really happened during setup so it can prove the P4 PTEH alias
        ! ---- is live rather than a latched snapshot. It is now only a register
        ! ---- write -- it installs nothing. ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6         ! VA = PA = start (4 KB-aligned)
        mov     #0, r7
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill_way r10, 16, r6, r7, r8

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on

        ! Snapshot cnt_hits first: the code page is now itself resolved by a
        ! walk, so "the counter is non-zero" no longer says anything about THIS
        ! access -- check 5 needs a delta. r11 is unbanked.
        mov.l   p_walkcnt_p4, r0
        mov.l   @r0, r11
        extu.w  r11, r11                ! r11 = cnt_hits before

        mov.l   p_testva, r0
        mov.l   @r0, r4                 ! take the walk-hit miss

        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off

        ! ================= 5: the walk must have actually run =============
        ! cnt_hits must have advanced ACROSS the access above
        ! happened, which would make check 4 vacuous.
        mov.l   p_walkcnt_p4, r0
        mov.l   @r0, r1
        extu.w  r1, r1                  ! cnt_hits now
        cmp/eq  r11, r1
        mov     #5, r9
        bt      _fail_at

        ! ================= 6: PTEH alias is live, not a latched snapshot ==
        ! The walk sequence above did `LDC r0, PTEH` with p_pteh_code. If the
        ! alias were latched at check 1 it would still return p_pteh_val.
        mov.l   p_pteh_alias, r0
        mov.l   @r0, r1
        mov.l   p_pteh_code, r2
        cmp/eq  r2, r1
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
p_walkcnt_p4:    .long 0xFF000054
p_pteh_code:     .long start
p_ptel_code:     .long start + 0x000000CD ! identity: PPN=start, U cleared (SMEP)
p_tsbslot_reg:   .long 0xFF000048       ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
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
