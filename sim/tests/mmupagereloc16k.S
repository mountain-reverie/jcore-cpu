! mmupagereloc16k.S -- 16 KB page with a NON-IDENTITY frame (J4+MMU_ARCH, cpu_cache_tb).
! Closes the coverage gap that every other large-page guard is identity (PA==VA):
! maps VA 0x10000 -> PA 0x40000 (frame != VA), pm=1. A store through a sub-region
! VA 0x12000 (offset 0x2000 within the 16 KB page) must relocate to PA 0x42000
! (frame 0x40000 + offset 0x2000). Asserts: PA 0x42000 == sentinel (variable
! frame/offset split works for a real frame substitution), PA 0x12000 == 0 (the
! VA's identity location is NOT written -> relocation actually moved it), and
! PA 0x40000 == 0 (frame base untouched). Exercises the pm>=1 (ppn_lo and not offm)
! path against a frame that differs from the VA -- which the identity guards do not.
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
        ! VPN 0x10 (VA 0x10000) -> PA 0x40000 (NON-identity), 16 KB (pm=1), C=1
        mov.l   p_pteh_16k, r0         ! 0x00010000
        .word   0x405E
        mov.l   p_ptel_16k, r0         ! PA 0x40000 | (1<<8) | 0xE8 = 0x000401E8
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038
        ! clear PA 0x40000 (frame base), 0x42000 (frame sub), 0x12000 (VA identity)
        mov     #0, r1
        mov.l   p_p2_frame, r2         ! 0xA0040000 -> PA 0x40000
        mov.l   r1, @r2
        mov.l   p_p2_fsub,  r3         ! 0xA0042000 -> PA 0x42000
        mov.l   r1, @r3
        mov.l   p_p2_vid,   r7         ! 0xA0012000 -> PA 0x12000 (VA's identity loc)
        mov.l   r1, @r7
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! store SENTINEL through translated VA 0x12000 (offset 0x2000 in the 16KB page)
        mov.l   p_sentinel, r5         ! sentinel 0x5E91A140
        mov.l   p_va_sub, r6           ! 0x00012000
        mov.l   r5, @r6
        ! drain write-through buffer
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back via P2
        mov.l   @r3, r8                ! PA 0x42000: expect sentinel (relocated frame+offset)
        mov.l   @r7, r10               ! PA 0x12000: expect 0 (VA identity loc untouched)
        mov.l   @r2, r11               ! PA 0x40000: expect 0 (frame base untouched)
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = sub-page did not relocate to frame+offset PA 0x42000
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = VA identity loc PA 0x12000 wrongly written (no relocation)
        bf      _fail
        mov     #0, r0
        cmp/eq  r11, r0
        mov     #3, r9                 ! fail 3 = frame base PA 0x40000 wrongly written
        bf      _fail
        bra     _done
        nop
        .align 2
p_ptel_p0:   .long 0x000000E8
p_pteh_16k:  .long 0x00010000
p_ptel_16k:  .long 0x000401E8          ! PA 0x40000 | (1<<8) | 0xE8 (pm=1, non-identity frame)
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A140
p_p2_frame:  .long 0xA0040000
p_p2_fsub:   .long 0xA0042000
p_p2_vid:    .long 0xA0012000
p_va_sub:    .long 0x00012000
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
        .org 0x43000
