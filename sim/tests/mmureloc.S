! mmureloc.S -- MMU address relocation pin (J4+MMU_ARCH, cpu_cache_tb).
! Maps VPN 0x4 (VA 0x4000) -> PPN 0x6 (PA 0x6000), NON-identity, coloring-aligned
! (VA[12]=0 == PA[12]=0). Stores SENTINEL through the translated VA; asserts it
! landed at PA 0x6000 (the PPN) and PA 0x4000 (the VA's identity location) is
! untouched. RED on master (no relocation -> store lands at PA 0x4000); GREEN
! once translated accesses relocate VA->PA.
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
        ! page 0: identity code, C=1
        mov     #0, r0
        .word   0x405E
        mov.l   p_ptel_p0, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! VPN 0x4 (VA 0x4000) -> PPN 0x6 (PA 0x6000), C=1
        mov.l   p_pteh_x, r0           ! 0x00004000
        .word   0x405E
        mov.l   p_ptel_y, r0           ! PA 0x6000 | 0xE8 = 0x000060E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! clear both physical pages via P2 (uncached, AT-independent)
        mov     #0, r1
        mov.l   p_p2_x, r2             ! 0xA0004000 -> PA 0x4000
        mov.l   r1, @r2
        mov.l   p_p2_y, r3             ! 0xA0006000 -> PA 0x6000
        mov.l   r1, @r3
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! store SENTINEL through translated VA 0x4000 (-> PA 0x6000 if relocated)
        mov.l   p_sentinel, r5         ! 0x5E1A1107
        mov.l   p_va_x, r6             ! 0x00004000
        mov.l   r5, @r6
        ! drain the write-through buffer before the uncached read-back
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back both physical pages uncached via P2
        mov.l   @r3, r8                ! PA 0x6000: expect SENTINEL (relocated)
        mov.l   @r2, r10               ! PA 0x4000: expect 0 (untouched)
        ! check
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = store did NOT relocate to PPN
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = store ALSO hit the VA's PA (bug)
        bf      _fail
        bra     _done
        nop
        .align 2
p_ptel_p0:   .long 0x000000E8
p_pteh_x:    .long 0x00004000
p_ptel_y:    .long 0x000060E8          ! PA 0x6000, C=1
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E1A1107
p_p2_x:      .long 0xA0004000
p_p2_y:      .long 0xA0006000
p_va_x:      .long 0x00004000
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
        .org 0x7000
