! mmuwalkmiss.S -- a TSB miss still raises the exception, unchanged.
!
! The walker has no failure wire: when it gives up, busy drops and the
! still-true miss condition raises the fault through cpu.vhd's normal path.
! This guard proves that path is byte-identical to the pre-walker behaviour --
! right vector, right EXPEVT, right TEA, and TSBPTR pointing at the slot the
! walker just probed and rejected.
!
! Uses the same TSBBR/TSBCFG/VA/slot arithmetic as the proven-correct
! mmuwalkhit.S (VA 0x00042000 -> TSBPTR 0x00010030) rather than re-deriving
! the hash by hand.
!
! Result codes:
!   1  no exception at all -- the load fell through (walker wrongly installed
!      the empty/rejected slot, or the miss condition never fired)
!   2  EXPEVT wrong
!   3  TEA is not the faulting VA
!   4  TSBPTR does not match the probed slot
!   5  walk counter did not advance -- the walker never even tried
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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_miss - 0x400 ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page identity (W+X+U+C, V forced by LDTLB). ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Configure the TSB (base/size/hash), but leave the slot the
        ! ---- walker will probe ZEROED -- the walker must fail on V=0. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov.l   p_testva, r0
        mov.l   @r0, r4                 ! <-- miss; TSB slot empty; must fault

        mov     #1, r9                  ! fell through: no exception at all
        bra     _fail_at
        nop

_v_miss:
        mov.l   p_expevt, r0
        mov.l   @r0, r1
        mov.l   p_exp_dmiss_r, r2
        cmp/eq  r1, r2
        mov     #2, r9
        bf      _fail_at

        mov.l   p_tea, r0
        mov.l   @r0, r1
        mov.l   p_testva, r2
        cmp/eq  r1, r2
        mov     #3, r9
        bf      _fail_at

        mov.l   p_tsbptr, r0
        mov.l   @r0, r1
        mov.l   p_expect_slot, r2
        cmp/eq  r1, r2
        mov     #4, r9
        bf      _fail_at

        mov.l   p_walkcnt, r0
        mov.l   @r0, r1
        tst     r1, r1
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
p_ptel_code:    .long start + 0x000000C8 ! identity: PPN=start, U cleared (SMEP)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_testva:       .long 0x00042000        ! same VA as mmuwalkhit
p_expevt:       .long 0xFF000024
p_exp_dmiss_r:  .long 0x00000060
p_tea:          .long 0xFF00000C
p_tsbptr:       .long 0xFF00001C
p_expect_slot:  .long 0x00010030        ! hash(0x00042000) -- see mmutsb.S header
p_walkcnt:      .long 0xABCD0F00

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
        tst     r9, r9
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
_v_fault:                                ! = VBR + 0x400
        bra     _v_miss
        nop

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
