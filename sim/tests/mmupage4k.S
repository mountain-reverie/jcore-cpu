! mmupage4k.S -- 4 KB page (pm=0) control guard: two adjacent 4 KB entries with
! distinct frames must NOT merge under masked compare. VA 0x10000 -> PA 0x10000
! (SA), VA 0x11000 -> PA 0x55000 (SB). With AT on, load from 0x10000 must return
! SA (fail 1) and load from 0x11000 must return SB (fail 2). RED if the match
! logic ignores pm=0 and merges them; GREEN once the pm=0 masked compare keeps
! adjacent 4 KB entries distinct.
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
        ! --- page 0: identity code page, 4 KB, pm=0, C=1 ---
        mov     #0, r0
        .word   0x405E          ! LDC r0, PTEH  (VA 0x0)
        mov.l   p_ptel_p0, r0   ! 0x000000E8
        .word   0x406E          ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E          ! LDC r0, ASIDR
        .word   0x0038          ! LDTLB

        ! --- entry A: VA 0x10000 -> PA 0x10000, 4 KB (pm=0), C=1 ---
        mov.l   p_pteh_a, r0    ! 0x00010000
        .word   0x405E
        mov.l   p_ptel_a, r0    ! 0x000100E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- entry B: VA 0x11000 -> PA 0x55000, 4 KB (pm=0), C=1 ---
        mov.l   p_pteh_b, r0    ! 0x00011000
        .word   0x405E
        mov.l   p_ptel_b, r0    ! 0x000550E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- seed SA at PA 0x10000 and SB at PA 0x55000 via P2 ---
        mov.l   p_sa,     r5    ! sentinel A 0x4A000001
        mov.l   p_sb,     r6    ! sentinel B 0x4B000002
        mov.l   p_p2_a,   r2    ! 0xA0010000  (P2 alias of PA 0x10000)
        mov.l   p_p2_b,   r3    ! 0xA0055000  (P2 alias of PA 0x55000)
        mov.l   r5, @r2
        mov.l   r6, @r3

        ! --- enable AT ---
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0

        ! --- drain write-through buffer ---
        mov     #20, r0
1:      dt      r0
        bf      1b

        ! --- load via translated VA 0x10000 -> must return SA ---
        mov.l   p_va_a, r7      ! 0x00010000
        mov.l   @r7, r8
        mov.l   p_sa, r0
        cmp/eq  r8, r0
        mov     #1, r9          ! fail 1 = VA 0x10000 did not return SA
        bf      _fail

        ! --- load via translated VA 0x11000 -> must return SB ---
        mov.l   p_va_b, r7      ! 0x00011000
        mov.l   @r7, r8
        mov.l   p_sb, r0
        cmp/eq  r8, r0
        mov     #2, r9          ! fail 2 = VA 0x11000 did not return SB
        bf      _fail

        bra     _done
        nop
        .align 2
p_ptel_p0: .long 0x000000E8
p_pteh_a:  .long 0x00010000    ! VA 0x10000, pm=0
p_ptel_a:  .long 0x000100E8    ! PA 0x10000 | 0xE8  (pm=0: bits[11:8]=0)
p_pteh_b:  .long 0x00011000    ! VA 0x11000, pm=0
p_ptel_b:  .long 0x000550E8    ! PA 0x55000 | 0xE8
p_mmucr:   .long 0xFF000010
p_sa:      .long 0x4A000001
p_sb:      .long 0x4B000002
p_p2_a:    .long 0xA0010000
p_p2_b:    .long 0xA0055000
p_va_a:    .long 0x00010000
p_va_b:    .long 0x00011000
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
        .org 0x56000
