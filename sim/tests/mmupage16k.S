! mmupage16k.S -- 16 KB page: a sub-page access hits the one entry and relocates
! (J4, cpu_cache_tb). RED on fixed-4KB RTL (VA 0x11000 unmapped); GREEN
! once PageMask=1 makes one entry cover VA 0x10000-0x13FFF and relocate per offset.
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
        ! page 0: identity code, 4 KB, C=1
        mov     #0, r0
        .word   0x405E
        mov.l   p_ptel_p0, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! VPN 0x10 (VA 0x10000) -> PA 0x10000, 16 KB (pm=1), C=1
        mov.l   p_pteh_16k, r0         ! 0x00010000
        .word   0x405E
        mov.l   p_ptel_16k, r0         ! PA 0x10000 | (1<<8) | 0xE8 = 0x000101E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! clear PA 0x10000 and 0x11000 via P2
        mov     #0, r1
        mov.l   p_p2_base, r2          ! 0xA0010000
        mov.l   r1, @r2
        mov.l   p_p2_sub,  r3          ! 0xA0011000
        mov.l   r1, @r3
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! store SENTINEL through translated VA 0x11000 (2nd 4KB sub-region)
        mov.l   p_sentinel, r5         ! sentinel 0x5E91A16C
        mov.l   p_va_sub, r6           ! 0x00011000
        mov.l   r5, @r6
        ! drain write-through buffer
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back via P2: PA 0x11000 == sentinel, PA 0x10000 == 0
        mov.l   @r3, r8                ! PA 0x11000
        mov.l   @r2, r10               ! PA 0x10000
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = sub-page didn't hit/relocate to PA 0x11000
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = base PA 0x10000 wrongly written
        bf      _fail
        bra     _done
        nop
        .align 2
p_ptel_p0:   .long 0x000000E8
p_pteh_16k:  .long 0x00010000
p_ptel_16k:  .long 0x000101E8          ! PA 0x10000 | (1<<8) | 0xE8 (pm=1 at PTEL[11:8])
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A16C
p_p2_base:   .long 0xA0010000
p_p2_sub:    .long 0xA0011000
p_va_sub:    .long 0x00011000
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
        .org 0x12000
