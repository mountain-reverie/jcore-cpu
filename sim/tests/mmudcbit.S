! mmudcbit.S -- D-side PTE C-bit cacheability pin (J4, runs on cpu_cache_tb).
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
! SEED=0x11111111  NEW=0xC0DEC0DE

!
! ---- walker-install version (retire-LDTLB) --------------------------------
! All three mappings now reach the TLB through the hardware TSB walker. The
! property under test is untouched -- the PTE C bit must decide cacheability
! per page, so leg A (C=1) must go stale behind an uncached P2 self-modify and
! leg B (C=0) must see it immediately. Strength: SAME. The two DATA PTELs are
! byte-identical to the LDTLB ones apart from bit 0 (V), and they keep U=1;
! SMEP is an I-side rule, so only the code page's U bit moved.
!
! Setup requirements walker-only install adds, none of which LDTLB had:
!   * RB MUST be 0 -- core/cpu.vhd's walk_req is gated on dp_sr.rb = '0' and
!     the cosim starts in bank 1, so without the clear nothing ever walks and
!     the failure is silent (MMUCR reads back 1, the walk counter stays 0).
!   * Every page the CPU FETCHES from must be U=0: once an entry reaches the
!     ITLB, SMEP (core/tlb.vhd:247, kernel fetch of a user page) rejects it.
!   * The image is padded past the END of the TSB -- the walker reads the TSB
!     BY PHYSICAL ADDRESS and the cosim backs SRAM only within the loaded
!     image, so a TSB beyond it reads as nothing and every walk silently
!     misses with no fault and no data.
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS. Since the per-sub-test fail-code globals
! start at 0 until a sub-test sets them, a fault reaching _fail BEFORE the first
! sub-test runs would otherwise silently report PASS. _fail now clamps r9==0 to
! 0x7F before the store so 0 can never leave through the fail path. Fail-code
! globals below use loud sentinels (_g_exp_* = 0xFFFFFFFF, _g_bad_* = small
! distinct values) so an early exit still names its cause.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
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
#if CONFIG_PRIV_ARCH
        ! ---- Ensure RB=0 (bank 0). core/cpu.vhd's walk_req is gated on
        ! ---- dp_sr.rb = '0' and the cosim starts in bank 1, so without this
        ! ---- NO walk is ever armed: AT comes on, nothing installs, and the
        ! ---- walk counter at 0xFF000054 never leaves zero.
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
        ! ---- Fill the TSB from the (VA, ASID, PTEL) table; each row's set
        ! ---- address comes from the P4 helper under that row's ASID, so no
        ! ---- hash is hand-computed. AT is off: plain P0 stores.
        mov.l   p_tsbslot, r12
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6              ! VA
        mov.l   @r14+, r7              ! ASID
        mov.l   @r14+, r8              ! PTEL
        mov     r7, r0
        .word   0x407E                 ! LDC r0, ASIDR
        nop
        nop
        mov.l   r6, @r12               ! write VA -> helper
        mov.l   @r12, r10              ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b
        bra     _run
        nop

        ! ---- Literal pool 1 (setup). `mov.l @(disp,PC)` is FORWARD-only and
        ! ---- reaches +1020 bytes, so migrated bodies need two pools.
        .align 2
p_rbclear:     .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00004008        ! base=0x00004000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! identity code page, U=0 (SMEP)
        .long 0x00001000, 0x00000000, 0x000010E9  ! leg A data page, C=1
        .long 0x00002000, 0x00000000, 0x000020E1  ! leg B data page, C=0
_tsb_tab_end:

ENTRY(_run)
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
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

        ! pad the image so PA 0x1000 / 0x2000 are backed by mmap_ptr1 (< image size)
        ! Pad past the TSB (0x4000..0x5FFF); see the header note.
        .org 0x6000
