! mmupage1m.S -- 1 MB page: a sub-page access hits the one entry and relocates
! (J4+MMU_ARCH, cpu_cache_tb). RED on fixed-4KB RTL (VA 0x101000 unmapped); GREEN
! once PageMask=4 makes one entry cover VA 0x100000-0x1FFFFF and relocate per offset.
! Sub-region at offset 0x1000 into the 1MB page (keeps image at ~1 MB).
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
        ! VPN 0x100 (VA 0x100000) -> PA 0x100000, 1 MB (pm=4), C=1
        mov.l   p_pteh_1m, r0          ! 0x00100000
        .word   0x405E
        mov.l   p_ptel_1m, r0          ! PA 0x100000 | (4<<8) | 0xE8 = 0x001004E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! clear PA 0x100000 and 0x101000 via P2
        mov     #0, r1
        mov.l   p_p2_base, r2          ! 0xA0100000
        mov.l   r1, @r2
        mov.l   p_p2_sub,  r3          ! 0xA0101000
        mov.l   r1, @r3
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! store SENTINEL through translated VA 0x101000 (2nd 4KB sub-region of 1MB page)
        mov.l   p_sentinel, r5         ! sentinel 0x5E91A16C
        mov.l   p_va_sub, r6           ! 0x00101000
        mov.l   r5, @r6
        ! drain write-through buffer
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back via P2: PA 0x101000 == sentinel, PA 0x100000 == 0
        mov.l   @r3, r8                ! PA 0x101000
        mov.l   @r2, r10               ! PA 0x100000
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = sub-page didn't hit/relocate to PA 0x101000
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = base PA 0x100000 wrongly written
        bf      _fail
        bra     _done
        nop
        .align 2
p_ptel_p0:   .long 0x000000E8
p_pteh_1m:   .long 0x00100000
p_ptel_1m:   .long 0x001004E8          ! PA 0x100000 | (4<<8) | 0xE8 (pm=4 at PTEL[11:8])
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A16C
p_p2_base:   .long 0xA0100000
p_p2_sub:    .long 0xA0101000
p_va_sub:    .long 0x00101000
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
        .org 0x102000
