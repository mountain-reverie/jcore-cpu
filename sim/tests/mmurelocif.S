! mmurelocif.S -- MMU I-fetch address relocation pin (J4+MMU_ARCH, cpu_cache_tb).
! Maps VPN 0x4 (VA 0x4000) -> PPN 0x6 (PA 0x6000), NON-identity, C=1 exec. A stub
! at PA 0x6000 returns 0x42; a DECOY stub at PA 0x4000 (the VA's identity location)
! returns 0x11. Under AT, jsr to VA 0x4000: if the I-fetch relocates it executes
! PA 0x6000 -> r0=0x42; if not it executes PA 0x4000 -> r0=0x11. Assert r0==0x42.
! RED on master (no I-fetch relocation -> 0x11); GREEN once I-fetches relocate.
! Stubs live INSIDE the image at absolute PA via .org (the cosim loads PA[0,size)).
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
        ! --- page 0: code+literals, identity, C=1 ---
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=0)
        mov.l   p_ptel_p0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        ! --- VPN 0x4 (VA 0x4000) -> PPN 0x6 (PA 0x6000), C=1 exec ---
        mov.l   p_pteh_x, r0            ! 0x00004000
        .word   0x405E
        mov.l   p_ptel_y, r0           ! PA 0x6000 | 0xE8 = 0x000060E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! --- AT on ---
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        ! --- jsr to VA 0x4000 -> PA 0x6000 if I-fetch relocates ---
        mov.l   p_va_x, r1             ! 0x00004000
        jsr     @r1
        nop
        ! --- check r0 == 0x42 (executed the relocated stub at PA 0x6000) ---
        mov     #0x42, r4
        cmp/eq  r0, r4
        mov     #1, r9                 ! fail 1 = I-fetch did NOT relocate
        bf      _fail
        bra     _done
        nop
        .align 2
p_ptel_p0:   .long 0x000000E8
p_pteh_x:    .long 0x00004000
p_ptel_y:    .long 0x000060E8          ! PA 0x6000, C=1 exec
p_mmucr:     .long 0xFF000010
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

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! --- decoy stub at PA 0x4000 (VA's identity location): returns 0x11 ---
        .org 0x4000
        mov     #0x11, r0
        rts
        nop
        ! --- relocated stub at PA 0x6000 (the PPN): returns 0x42 ---
        .org 0x6000
        mov     #0x42, r0
        rts
        nop
#endif
        .org 0x7000
