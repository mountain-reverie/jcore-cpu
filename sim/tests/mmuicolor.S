! mmuicolor.S -- I-side cacheability staleness pin (J4+MMU_ARCH, runs on cpu_cache_tb).
!
! Proves the PTE C-bit DISTINGUISHES I-side caching from bypass. Two legs, AT on:
!   Leg A (C=1 page, PA 0x1000): first call caches the stub in the icache; a P2
!     uncached self-modify mutates backing RAM; second call serves the STALE line
!     (r0 == 11).
!   Leg B (C=0 page, PA 0x2000): fetch bypasses the icache; after the identical P2
!     self-modify the second call serves the FRESH instruction (r0 == 22).
! PASS iff (leg A stale) AND (leg B fresh) -- non-vacuous by construction: if the
! C-bit did nothing both legs would behave identically and one assertion fails.
!
! The stubs live INSIDE the linked image at absolute PA 0x1000 / 0x2000 (the data
! bus and the icache share mmap_ptr1 only for PA < image size). They are placed in
! the .vect section (linker VMA 0) via .org so the addresses are absolute; page-0
! code/literals stay below 0x1000. The co-sim registers a P2 alias of the image
! (mem_bus_p2_map), so a store to 0xA0000000+X writes mmap_ptr1[X].
!
! Overlay opcodes: LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!                  LDTLB=0x0038
! Stub encodings (BE): mov #11,r0=0xE00B  mov #22,r0=0xE016  rts=0x000B  nop=0x0009
! Self-modify word = 0xE016000B (word@0 = mov #22,r0 ; word@2 = rts).

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

        ! --- page 1: stub A, identity, C=1 ---
        mov.l   p_pteh_p1, r0
        .word   0x405E
        mov.l   p_ptel_p1, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- page 2: stub B, identity, C=0 ---
        mov.l   p_pteh_p2, r0
        .word   0x405E
        mov.l   p_ptel_p2, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- AT on ---
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! --- Leg A: C=1 -> expect STALE (11) ---
        mov.l   p_p2_p1, r3             ! 0xA0001000 (preload)
        mov.l   p_stub_v2, r5           ! 0xE016000B (preload)
        mov.l   p_va_p1, r1             ! 0x00001000
        jsr     @r1                     ! first call: caches stub A
        nop
        mov.l   r5, @r3                 ! P2 uncached self-modify -> RAM (1-instr gap)
        jsr     @r1                     ! second call: STALE if cached
        nop
        mov     r0, r8                  ! leg A result

        ! --- Leg B: C=0 -> expect FRESH (22) ---
        mov.l   p_va_p2, r1             ! 0x00002000
        jsr     @r1                     ! first call: bypass
        nop
        mov.l   p_p2_p2, r3             ! 0xA0002000
        mov.l   p_stub_v2, r0
        mov.l   r0, @r3                 ! P2 uncached self-modify -> RAM
        jsr     @r1                     ! second call: FRESH (bypass)
        nop
        mov     r0, r10                 ! leg B result

        ! --- check: r8 == 11 (stale) AND r10 == 22 (fresh) ---
        mov     #11, r0
        cmp/eq  r8, r0
        mov     #1, r9                  ! fail 1 = caching not observed
        bf      _fail
        mov     #22, r0
        cmp/eq  r10, r0
        mov     #2, r9                  ! fail 2 = bypass not fresh
        bf      _fail
        bra     _done
        nop

        .align 2
p_ptel_p0:  .long 0x000000E8
p_pteh_p1:  .long 0x00001000
p_ptel_p1:  .long 0x000010E8
p_pteh_p2:  .long 0x00002000
p_ptel_p2:  .long 0x000020E0
p_mmucr:    .long 0xFF000010
p_va_p1:    .long 0x00001000
p_va_p2:    .long 0x00002000
p_p2_p1:    .long 0xA0001000
p_p2_p2:    .long 0xA0002000
p_stub_v2:  .long 0xE016000B
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

        ! --- stubs at absolute PA inside the image (shared with data buffer) ---
        .org 0x1000
stubA:  mov     #11, r0
        rts
        nop
        .org 0x2000
stubB:  mov     #11, r0
        rts
        nop
        .org 0x3000             ! ensure image extends past stub B
