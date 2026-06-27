! mmudcbit.S -- D-side PTE C-bit cacheability pin (J4+MMU_ARCH, runs on cpu_cache_tb).
!
! Proves the dcache honors the PTE C-bit on a TRANSLATED data access: a C=1 page
! caches the read line (so a later memory change is NOT seen -> stale) while a C=0
! page bypasses (always sees memory -> fresh). The D-side analogue of mmuicolor
! (same read / P2-self-modify / re-read mechanism, for data instead of code).
! is_cacheable_mmu(addr, at=1, c) returns c, so at=1/c=0 takes the dcache bypass.
!
! Two legs, AT on, both data pages live INSIDE the image (PA < image size) so the
! P2 uncached alias (mem_bus_p2_map, 0xA0000000+X -> mmap_ptr1[X]) mutates the same
! backing RAM the dcache fills from:
!   Leg A (C=1, PA 0x1000): cacheable read loads SEED; P2 store NEW to mem; second
!     cacheable read HITS -> SEED (STALE) -- the dcache cached it (no D-write snoop).
!   Leg B (C=0, PA 0x2000): read bypasses to mem; P2 store NEW to mem; second read
!     bypasses -> NEW (FRESH) -- not cached.
! PASS iff (A stale=SEED) AND (B fresh=NEW) -- non-vacuous: if the C-bit did nothing
! both legs behave alike and one assertion fails.
!
! Overlay opcodes: LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!                  LDTLB=0x0038
! SEED=0x11111111  NEW=0xC0DEC0DE

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
        .word   0x405E
        mov.l   p_ptel_p0, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- page 1: data leg A, identity, C=1 ---
        mov.l   p_pteh_p1, r0
        .word   0x405E
        mov.l   p_ptel_p1, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- page 2: data leg B, identity, C=0 ---
        mov.l   p_pteh_p2, r0
        .word   0x405E
        mov.l   p_ptel_p2, r0
        .word   0x406E
        mov     #0, r0
        .word   0x407E
        .word   0x0038

        ! --- seed both physical pages = SEED via P2 (uncached, AT-independent) ---
        mov.l   p_seed, r1              ! 0x11111111
        mov.l   p_p2_a, r2              ! 0xA0001000
        mov.l   r1, @r2
        mov.l   p_p2_b, r3              ! 0xA0002000
        mov.l   r1, @r3

        ! --- enable AT ---
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0

        mov.l   p_va_a, r6              ! 0x00001000 (C=1)
        mov.l   p_va_b, r7              ! 0x00002000 (C=0)
        mov.l   p_new, r5               ! 0xC0DEC0DE

        ! --- Leg A: cacheable read (load), P2 self-modify, re-read -> STALE ---
        mov.l   @r6, r0                 ! first read: caches SEED (C=1)
        mov.l   r5, @r2                 ! P2 store NEW to mem PA 0x1000
        mov.l   @r6, r8                 ! second read: HIT -> SEED (stale)

        ! --- Leg B: read (bypass), P2 self-modify, re-read -> FRESH ---
        mov.l   @r7, r0                 ! first read: bypass -> mem SEED (C=0)
        mov.l   r5, @r3                 ! P2 store NEW to mem PA 0x2000
        mov.l   @r7, r10                ! second read: bypass -> NEW (fresh)

        ! --- check: r8 == SEED (A stale) AND r10 == NEW (B fresh) ---
        mov.l   p_seed, r0
        cmp/eq  r8, r0
        mov     #1, r9                  ! fail 1 = leg A not cached (saw NEW)
        bf      _fail
        mov.l   p_new, r0
        cmp/eq  r10, r0
        mov     #2, r9                  ! fail 2 = leg B not bypassed (saw stale SEED)
        bf      _fail
        bra     _done
        nop

        .align 2
p_ptel_p0:  .long 0x000000E8
p_pteh_p1:  .long 0x00001000
p_ptel_p1:  .long 0x000010E8           ! PA 0x1000, C=1
p_pteh_p2:  .long 0x00002000
p_ptel_p2:  .long 0x000020E0           ! PA 0x2000, C=0
p_mmucr:    .long 0xFF000010
p_seed:     .long 0x11111111
p_new:      .long 0xC0DEC0DE
p_p2_a:     .long 0xA0001000
p_p2_b:     .long 0xA0002000
p_va_a:     .long 0x00001000
p_va_b:     .long 0x00002000
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

        ! pad the image so PA 0x1000 / 0x2000 are backed by mmap_ptr1 (< image size)
        .org 0x3000
