! mmuicolor.S -- I-side cacheability staleness pin (J4, runs on cpu_cache_tb).
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
! Stub encodings (BE): mov #11,r0=0xE00B  mov #22,r0=0xE016  rts=0x000B  nop=0x0009
! Self-modify word = 0xE016000B (word@0 = mov #22,r0 ; word@2 = rts).

!
! ---- walker-install version (retire-LDTLB) --------------------------------
! All three mappings now reach the TLB through the hardware TSB walker. The
! property under test is untouched -- the PTE C bit must decide I-side
! cacheability per page, so stub A (C=1) must run stale after an uncached P2
! self-modify and stub B (C=0) must run fresh. Strength: SAME.
!
! This guard is now an ITLB-only test by construction: under walker-only
! install a miss is routed by SIDE, and both stub pages are reached only by
! FETCH, so they never enter the DTLB at all. Under LDTLB they entered both
! arrays. That is a truer model of what the guard claims to measure.
!
! BOTH STUB PAGES needed U cleared (0x...C9 / 0x...C1, was 0x...E8 / 0x...E0):
! they are jsr targets, so SMEP applies to them exactly as it does to the code
! page. Only the U bit moved; C, W, X and the PPNs are unchanged.
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
        .long 0x00001000, 0x00000000, 0x000010C9  ! stub A page, C=1, U=0 (executed)
        .long 0x00002000, 0x00000000, 0x000020C1  ! stub B page, C=0, U=0 (executed)
_tsb_tab_end:

ENTRY(_run)
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
p_mmucr:    .long 0xFF000010
p_va_p1:    .long 0x00001000
p_va_p2:    .long 0x00002000
p_p2_p1:    .long 0xA0001000
p_p2_p2:    .long 0xA0002000
p_stub_v2:  .long 0xE016000B
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

        ! --- stubs at absolute PA inside the image (shared with data buffer) ---
        .org 0x1000
stubA:  mov     #11, r0
        rts
        nop
        .org 0x2000
stubB:  mov     #11, r0
        rts
        nop
        ! Pad past the TSB (0x4000..0x5FFF); see the header note.
        .org 0x6000
