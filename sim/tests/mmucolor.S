! mmucolor.S -- VIPT page-coloring staleness pin (J4+MMU_ARCH, runs on cpu_cache_tb).
!
! The L1 D-cache is 8 KB direct-mapped (index = VA[12:5]); bit 12 is ABOVE the
! 4 KB page offset, so a mis-colored synonym (VA[12] != PA[12]) lands in a
! different cache set. Hardware does NOT detect synonyms (SW page-coloring
! contract). This test installs a mis-colored mapping and proves staleness.
!
!   PA_BUF      = 0x00010000  (PA[12]=0)
!   P1 write VA = 0x80010000  (untranslated -> PA_BUF, color-correct: set 0)
!   P0 read  VA = 0x00011000  (translated -> PA_BUF, VA[12]=1: set 1)
!
! Steps: identity-map page 0 (code/literals) AND map VA page 0x11 -> PPN 0x10,
! enable AT, write PATTERN via P1 (cached, dirty in set 0, memory NOT updated),
! read via mis-colored P0 VA (miss in set 1 -> fills a different physical line
! -> stale). result 0 = pass (stale observed); 1 = fresh data (synonym handled).
!
! Overlay opcodes: LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!                  LDTLB=0x0038

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! --- TLB entry 1: identity-map page 0 (code + literals), w+x+u+c=0xE8 ---
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL  (PPN=0 | 0xE8)
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! --- TLB entry 2: VA page 0x11 -> PPN page 0x10 (mis-colored data) ---
        mov.l   p_pteh_va11, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0x11)
        mov.l   p_ptel_pa10, r0
        .word   0x406E                  ! LDC r0, PTEL  (PPN=0x10 | 0xE8)
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! --- enable AT ---
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! --- color-correct write via P1 (untranslated, cached, set 0) ---
        mov.l   p_p1_buf, r0            ! 0x80010000
        mov.l   p_pattern, r1           ! 0xC010C010
        mov.l   r1, @r0                 ! dirty in set 0; memory NOT updated

        ! --- mis-colored read via P0 (translated, set 1, same PA) ---
        mov.l   p_p0_miscolor, r2       ! 0x00011000
        mov.l   @r2, r3                 ! miss in set 1 -> stale fill

        ! --- compare: r3 == pattern => synonym handled => FAIL ---
        mov.l   p_pattern, r4
        cmp/eq  r3, r4
        mov     #1, r9
        bt      _fail                   ! fresh data: coloring NOT observed
        bra     _done                   ! stale: contract holds
        nop

        .align 2
p_ptel_page0:  .long 0x000000E8         ! PPN=0, flags w+x+u+c
p_pteh_va11:   .long 0x00011000         ! VPN page 0x11 (VA[31:12] in place), ASID=0
p_ptel_pa10:   .long 0x000100E8         ! PA=0x00010000, PTEL[31:10]=PA[31:10], flags w+x+u+c
p_mmucr:       .long 0xFF000010
p_p1_buf:      .long 0x80010000
p_p0_miscolor: .long 0x00011000
p_pattern:     .long 0xC010C010
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
