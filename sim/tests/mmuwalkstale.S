! mmuwalkstale.S -- STALE and V=0 entries must NOT install.
!
! Two distinct livelock/aliasing defects, neither of which today's software
! handler checks:
!
!   STALE: installing a soft-invalidated entry that then fails to match
!          re-misses immediately -- an unbounded loop. Same shape as the COW
!          livelock.
!   V=0:   a zeroed TSB has tag_hi = 0, which aliases a legitimate VPN 0.
!
! Both sub-tests are bounded: if the walker livelocks, the guard times out
! rather than reporting, so the CI wall-timeout IS the failure signal for
! those -- each sub-test also arms Larmed so the shared VBR+0x400 stub can
! tell which sub-test's fault it is resuming, without a second exception
! ever needing to occur.
!
! Uses the same TSBBR/TSBCFG identity-mapped-code-page setup as the
! proven-correct mmuwalkhit.S. Sub-test A hashes VA 0x00042000 to TSBPTR
! 0x00010060 (same arithmetic as mmuwalkhit/mmuwalkmiss); sub-test B uses
! VA 0x00000000, which hashes to TSBPTR 0x00010000 (VPN 0 in the base slot).
!
! Result codes:
!   1  sub-test A (STALE=1): walker installed it -- no exception arrived
!   2  sub-test B (V=0 at VPN 0): walker installed it -- no exception arrived
!   3  the VBR+0x400 stub was entered but Larmed matched neither sub-test
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

        ! ---- VBR = _v_fault - 0x400 ----
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

        ! ---- Configure the TSB (base/size/hash). ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! --- sub-test A: fill the probed slot with a STALE entry
        ! --- (V=1, STALE=1) for VA 0x00042000. ---
        mov.l   p_tsb_slot_a, r0
        mov.l   p_vpn_a,  r1
        mov.l   p_asid,   r2
        mov.l   p_ptel_stale, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov.l   p_armed, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov.l   p_testva_a, r0
        mov.l   @r0, r4                 ! must fault, NOT install (STALE)

        mov     #1, r9                  ! fell through: walker installed it
        bra     _fail_at
        nop

_after_a:
        ! ---- Disable AT to seed sub-test B's TSB slot with plain stores. ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! --- sub-test B: TSB slot for VPN 0 left fully ZEROED (V=0). ---
        mov.l   p_tsb_slot_b, r0
        mov.l   p_zero, r1
        mov.l   r1, @(8, r0)
        mov.l   r1, @(4, r0)
        mov.l   r1, @(0, r0)

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov.l   p_armed, r0
        mov     #2, r1
        mov.l   r1, @r0

        mov.l   p_testva_b, r0          ! VA 0x00000000
        mov.l   @r0, r4                 ! must fault, NOT install (V=0)

        mov     #2, r9                  ! fell through: walker installed it
        bra     _fail_at
        nop

_after_b:
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

_v_miss:
        mov.l   p_armed, r0
        mov.l   @r0, r1
        mov     #1, r2
        cmp/eq  r1, r2
        bt      _resume_a
        mov     #2, r2
        cmp/eq  r1, r2
        bt      _resume_b
        mov     #3, r9
        bra     _fail
        nop

_resume_a:
        mov.l   p_after_a, r0
        .word   0x404E                  ! LDC r0, SPC
        .word   0x002B                  ! RTE
        nop

_resume_b:
        mov.l   p_after_b, r0
        .word   0x404E                  ! LDC r0, SPC
        .word   0x002B                  ! RTE
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
p_tsb_slot_a:   .long 0x00010060        ! hash(0x00042000) -- see mmutsb.S header
p_vpn_a:        .long 0x00042000
p_testva_a:     .long 0x00042000
p_tsb_slot_b:   .long 0x00010000        ! hash(0x00000000) -- base slot, VPN 0
p_testva_b:     .long 0x00000000
p_ptel_stale:   .long 0x000420EB        ! PA 0x00042000 | V|STALE|C|U|X|W (0xEB)
p_asid:         .long 0x00000000
p_zero:         .long 0x00000000
p_armed:        .long 0x80002D04
p_after_a:      .long _after_a
p_after_b:      .long _after_b

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
