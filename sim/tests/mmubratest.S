! mmubratest.S -- minimal diagnostic: does a taken 'bra' to a far label work
! after AT is enabled? (isolates the mmuidslot harness hang). No fault.
!   marker 0x11 = AT enabled ; 0x22 = after near bra ; 0x33 = after far bra.
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
        stc     sr, r0                  ! RB=0 clear (as mmuidslot does)
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR (as mmuidslot does)
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! Map page 1 NO-EXECUTE (as mmuidslot does) -- suspect for the hang.
        mov.l   p_pteh_page1, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=1)
        mov.l   p_ptel_nx, r0
        .word   0x406E                  ! LDC r0, PTEL = 0xA8 (no-execute)
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        mov.l   p_pio, r14
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on

        mov     #0x11, r13             ! marker: AT enabled
        mov.b   r13, @r14

        bra     near1                  ! near taken bra
        nop
near1:
        mov     #0x22, r13             ! marker: near bra worked
        mov.b   r13, @r14

        bra     far1                   ! far taken bra (into .org gap)
        nop

        .align 2
p_vbr_val:      .long 0x00000000
p_rbclear:      .long 0xDFFFFFFF
p_ptel_page0:   .long 0x000000E8
p_mmucr:        .long 0xFF000010
p_pteh_page1:   .long 0x00001000
p_ptel_nx:      .long 0x000000A8
p_pio:          .long 0xABCD0000

        .org 0x0400
far1:
        mov     #0x33, r13             ! marker: reached 0x0400
        mov.b   r13, @r14
        .rept (0x0F00-0x040C)/2        ! huge nop sled (as mmuidslot)
        nop
        .endr
        mov     #0x44, r13             ! marker: sled fell through
        mov.b   r13, @r14
        bra     _done
        nop
        .org 0x1000

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov     #99, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS
#endif
