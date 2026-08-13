! mmurelocbp.S -- MMU address relocation pin -- uncacheable bypass (C=0) (J4, cpu_cache_tb).
! Maps VPN 0x4 (VA 0x4000) -> PPN 0x6 (PA 0x6000), NON-identity, coloring-aligned
! (VA[12]=0 == PA[12]=0). Stores SENTINEL through the translated VA; asserts it
! landed at PA 0x6000 (the PPN) and PA 0x4000 (the VA's identity location) is
! untouched. RED on master (no relocation -> store lands at PA 0x4000); GREEN
! once translated accesses relocate VA->PA.
!
! ---- walker-install version (retire-LDTLB) --------------------------------
! Both mappings now reach the TLB through the hardware TSB walker instead of
! LDTLB. The property under test is unchanged, so strength is SAME: the PTELs
! are byte-identical to the LDTLB versions apart from bit 0 (V), which the
! walker requires and LDTLB did not.
!
! The TSB lives at PA 0x00008000 (256 sets x 32 B -> 0x8000..0x9FFF) and the
! image is padded past it: the walker reads the TSB BY PHYSICAL ADDRESS and the
! cosim backs SRAM only within the loaded image, so a TSB past the image end
! reads as nothing and every walk silently misses with no fault at all. Set
! addresses come from the P4 TSB-slot helper (0xFF000048), never a hand hash.
!
! Two setup requirements that LDTLB did not impose:
!   * RB MUST be 0. core/cpu.vhd's walk_req is gated on dp_sr.rb = '0', and the
!     cosim starts in bank 1, so without the clear at the top of start NO walk
!     is ever armed -- AT comes on, nothing installs, and the guard wanders.
!   * The code page MUST be U=0. Once an entry reaches the ITLB the SMEP rule
!     (core/tlb.vhd:247, "kernel fetch of a user page") rejects a U=1 fetch, so
!     the identity code row is 0x...C9, not 0x...E9. The MAPPING UNDER TEST is
!     unaffected -- only the code page's U bit moved.
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
        ! ---- Ensure RB=0 (bank 0). The walker's request is gated on
        ! ---- dp_sr.rb = '0' (core/cpu.vhd walk_req), and the cosim starts in
        ! ---- bank 1, so without this NO walk is ever armed and every
        ! ---- translation silently fails to install.
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
        ! ---- hash is hand-computed. AT is off, so these are plain P0 stores.
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

        ! ---- Literal pool 1 (setup). SH-2 `mov.l @(disp,PC)` is FORWARD-only
        ! ---- and reaches +1020 bytes, hence two pools.
        .align 2
p_rbclear:     .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00008008        ! base=0x00008000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! identity code page, W|X|C|V (U=0: SMEP)
        .long 0x00004000, 0x00000000, 0x000060E1  ! VA 0x4000 -> PA 0x6000, C=0 bypass
_tsb_tab_end:

ENTRY(_run)
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
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E1A1107
p_p2_x:      .long 0xA0004000
p_p2_y:      .long 0xA0006000
p_va_x:      .long 0x00004000
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
        ! Pad past the TSB (0x8000..0x9FFF); see the header note.
        .org 0xA000
