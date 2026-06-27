! mmupagemix2.S -- mixed-page-size coexistence: 4KB entry installed FIRST, then
! 16KB. Identical semantics to mmupagemix.S but reversed install order, proving
! resolution depends on each entry's own PageMask, not slot position.
! (J4+MMU_ARCH, cpu_cache_tb)
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
        ! --- page 0: identity code page, 4 KB, C=1 ---
        mov     #0, r0
        .word   0x405E          ! ldc r0,PTEH
        mov.l   p_ptel_p0, r0
        .word   0x406E          ! ldc r0,PTEL
        mov     #0, r0
        .word   0x407E          ! ldc r0,PTEA
        .word   0x0038          ! LDTLB

        ! --- 4KB page (install FIRST): VPN 0x14 -> VA 0x14000, PA 0x44000, pm=0 ---
        mov.l   p_pteh_4k, r0   ! 0x00014000
        .word   0x405E
        mov.l   p_ptel_4k, r0   ! 0x000440E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038          ! LDTLB

        ! --- 16KB page (install SECOND): VPN 0x10 -> VA 0x10000, PA 0x10000, pm=1 ---
        mov.l   p_pteh_16k, r0  ! 0x00010000
        .word   0x405E
        mov.l   p_ptel_16k, r0  ! 0x000101E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038          ! LDTLB

        ! --- seed sentinels via P2 ---
        mov.l   p_sa, r5
        mov.l   p_p2_12k, r1   ! 0xA0012000
        mov.l   r5, @r1
        mov.l   p_sb, r6
        mov.l   p_p2_44k, r2   ! 0xA0044000
        mov.l   r6, @r2

        ! --- enable AT ---
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0

        ! --- drain write-through buffer ---
        mov     #20, r0
1:      dt      r0
        bf      1b

        ! --- check A: load VA 0x12000 -> must return SA ---
        mov.l   p_va_12k, r7
        mov.l   @r7, r8
        mov.l   p_sa, r0
        cmp/eq  r8, r0
        mov     #1, r9
        bf      _fail

        ! --- check B: load VA 0x14000 -> must return SB ---
        mov.l   p_va_14k, r7
        mov.l   @r7, r8
        mov.l   p_sb, r0
        cmp/eq  r8, r0
        mov     #2, r9
        bf      _fail

        bra     _done
        nop

        .align 2
p_ptel_p0:  .long 0x000000E8
p_pteh_4k:  .long 0x00014000
p_ptel_4k:  .long 0x000440E8
p_pteh_16k: .long 0x00010000
p_ptel_16k: .long 0x000101E8
p_mmucr:    .long 0xFF000010
p_sa:       .long 0xAAAA0001
p_sb:       .long 0xBBBB0002
p_p2_12k:   .long 0xA0012000
p_p2_44k:   .long 0xA0044000
p_va_12k:   .long 0x00012000
p_va_14k:   .long 0x00014000
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
        .org 0x45000
