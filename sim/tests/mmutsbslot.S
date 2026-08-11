! mmutsbslot.S -- P4 TSB-slot-address helper (core/datapath.vhm P4_TSBSLOT,
! 0xFF000048; docs/soc/p4-mmio-map.md 0x048 "TSBSLOT") returns tsb_ptr(VA)
! for a spread of VAs.
!
! This is the ONE-TIME oracle check for Phase-2 Task 2: Linux's
! jcore_tsb_slot_offset() (a from-scratch C mirror of core/datapath_pkg.vhd
! tsb_ptr()) is deleted in this same change, in favour of the kernel asking
! this hardware register directly. Before that mirror is gone there is no
! other way to prove the new register agrees with the formula it used to
! duplicate -- so this guard hand-computes tsb_ptr() for 5 VAs (spanning
! low/mid/high VPN bits) against TSBBR=0x00010000/TSB_SIZE_LOG=6,
! TSBCFG HASH_SHIFT=6/HASH_MODE=1 (same config as mmuwalkmiss.S/mmuwalkhit.S)
! and compares against the register's answer.
!
!   vpn  = VA >> 12
!   hash = (vpn xor (vpn >> HASH_SHIFT)) xor amix(ASID)   [amix(0) == 0]
!   idx  = hash and ((1 << TSB_SIZE_LOG) - 1)
!   slot = (TSBBR and not 0xF) or (idx << 4)
!
! Result codes:
!   1  VA 0x00042000 -> expected 0x00010030 (cross-checked against
!      mmuwalkmiss.S/mmuwalkhit.S's own independently-derived expectation)
!   2  VA 0x00001000 -> expected 0x00010010
!   3  VA 0x0004F000 -> expected 0x000100E0
!   4  VA 0x12345000 -> expected 0x00010080
!   5  VA 0xFFFFF000 -> expected 0x00010000
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
#if CONFIG_PRIV_ARCH

        ! ---- Configure TSBBR/TSBCFG (no AT needed -- the helper reads the
        ! ---- CSRs directly, it does not translate anything). ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- ASID is folded into the index (datapath_pkg tsb_ptr(), Phase-2
        ! ---- Task 3), so the expectations below are only meaningful for a
        ! ---- KNOWN ASID. Pin it to 0, for which amix == 0 and the formula in
        ! ---- the header reduces to the pre-fold one -- which is why all five
        ! ---- expected values are unchanged by that task. mmuwalkasid.S is the
        ! ---- guard that covers non-zero ASIDs.
        mov     #0, r0
        .word   0x407E                  ! LDC R0,ASIDR
        nop
        nop

        mov.l   p_slot_reg, r8          ! r8 = &JCORE_TSB_SLOT, kept live

        mov.l   p_va1, r0
        mov.l   r0, @r8
        mov.l   @r8, r1
        mov.l   p_exp1, r2
        cmp/eq  r1, r2
        mov     #1, r9
        bf      _fail

        mov.l   p_va2, r0
        mov.l   r0, @r8
        mov.l   @r8, r1
        mov.l   p_exp2, r2
        cmp/eq  r1, r2
        mov     #2, r9
        bf      _fail

        mov.l   p_va3, r0
        mov.l   r0, @r8
        mov.l   @r8, r1
        mov.l   p_exp3, r2
        cmp/eq  r1, r2
        mov     #3, r9
        bf      _fail

        mov.l   p_va4, r0
        mov.l   r0, @r8
        mov.l   @r8, r1
        mov.l   p_exp4, r2
        cmp/eq  r1, r2
        mov     #4, r9
        bf      _fail

        mov.l   p_va5, r0
        mov.l   r0, @r8
        mov.l   @r8, r1
        mov.l   p_exp5, r2
        cmp/eq  r1, r2
        mov     #5, r9
        bf      _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_slot_reg:    .long 0xFF000048        ! core/datapath.vhm P4_TSBSLOT

p_va1:  .long 0x00042000
p_exp1: .long 0x00010030
p_va2:  .long 0x00001000
p_exp2: .long 0x00010010
p_va3:  .long 0x0004F000
p_exp3: .long 0x000100E0
p_va4:  .long 0x12345000
p_exp4: .long 0x00010080
p_va5:  .long 0xFFFFF000
p_exp5: .long 0x00010000
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
