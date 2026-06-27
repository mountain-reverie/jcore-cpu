! mmupage64k.S -- 64 KB page: a sub-page access hits the one entry and relocates
! (J4+MMU_ARCH, cpu_cache_tb). RED on fixed-4KB RTL (VA 0x21000 unmapped); GREEN
! once PageMask=2 makes one entry cover VA 0x20000-0x2FFFF and relocate per offset.
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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! page 0: identity code, 4 KB, C=1
        mov     #0, r0
        .word   0x405E
        mov.l   p_ptel_p0, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! VPN 0x20 (VA 0x20000) -> PA 0x20000, 64 KB (pm=2), C=1
        mov.l   p_pteh_64k, r0         ! 0x00020000
        .word   0x405E
        mov.l   p_ptel_64k, r0         ! PA 0x20000 | (2<<8) | 0xE8 = 0x000202E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! clear PA 0x20000 and 0x21000 via P2
        mov     #0, r1
        mov.l   p_p2_base, r2          ! 0xA0020000
        mov.l   r1, @r2
        mov.l   p_p2_sub,  r3          ! 0xA0021000
        mov.l   r1, @r3
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! store SENTINEL through translated VA 0x21000 (2nd 4KB sub-region of 64KB page)
        mov.l   p_sentinel, r5         ! sentinel 0x5E91A16C
        mov.l   p_va_sub, r6           ! 0x00021000
        mov.l   r5, @r6
        ! drain write-through buffer
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back via P2: PA 0x21000 == sentinel, PA 0x20000 == 0
        mov.l   @r3, r8                ! PA 0x21000
        mov.l   @r2, r10               ! PA 0x20000
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = sub-page didn't hit/relocate to PA 0x21000
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = base PA 0x20000 wrongly written
        bf      _fail
        bra     _done
        nop
        .align 2
p_ptel_p0:   .long 0x000000E8
p_pteh_64k:  .long 0x00020000
p_ptel_64k:  .long 0x000202E8          ! PA 0x20000 | (2<<8) | 0xE8 (pm=2 at PTEL[11:8])
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A16C
p_p2_base:   .long 0xA0020000
p_p2_sub:    .long 0xA0021000
p_va_sub:    .long 0x00021000
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
        .org 0x22000
