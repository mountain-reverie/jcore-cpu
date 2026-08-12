! mmusplit.S -- the ITLB and the DTLB are two INDEPENDENT arrays.
!
! WHY THIS GUARD EXISTS. Splitting the one dual-ported TLB into `u_itlb` and
! `u_dtlb` (core/cpu.vhd) is a structural change made for placement/fanout, not
! for behaviour. Its failure mode is therefore INERTNESS, not breakage: a split
! that quietly served both lookups from one array -- or that routed every
! walker install into both arrays -- would be functionally correct and would
! leave the entire rest of the guard suite green while delivering none of the
! locality the split was made for. Nothing else in the suite can tell the two
! apart. This guard can.
!
! THE OBSERVABLE. A HARDWARE-WALKER install is the only side-selective write
! into the TLBs (cpu.vhd routes it by walk_side_i; LDTLB deliberately writes
! BOTH). So: make one side fault a VA in, then touch the SAME VA from the other
! side and require that the other side ALSO has to walk. Under a shared array
! the second access hits and no walk occurs. The walker's own cnt_walks counter
! (0xFF000054[31:16]) is the witness, so the check is a positive count, never an
! absence.
!
! Both directions are tested, because install routing can be wrong in either:
!   D -> I : a D load walks the page into the DTLB, then a jmp to that VA must
!            STILL walk (into the ITLB).  [code 3]
!   I -> D : after a TI flush, the I-fetch walks the page into the ITLB, then a
!            D load from that VA must STILL walk (into the DTLB).  [code 4]
! Each direction is paired with a positive sanity check that the FIRST access
! really walked (codes 2 and 6), so neither direction can pass by nothing
! happening at all.
!
! The target page lives in its own `.tlbtext` output section, linked by
! sim/tests/sh32_tlbtext.x at VA 0x00008000 -- identity (VMA == LMA), above the
! stack, and NOT covered by the identity code-page mapping installed at startup.
! Same arrangement as mmuwalkiside.S; see that guard's header for the rationale.
!
! Slot arithmetic, using mmutsb.S's documented hash:
!   VA 0x00008000 -> vpn 0x08, hash 0x08^(0x08>>6)=0x08, idx 0x08 -> 0x00010100
!
! The PTEL sets W (the D side reads and the I side fetches the same page) and X,
! and CLEARS U (bit 5): a kernel fetch of a U=1 page is an SMEP violation, which
! would present as a protection fault rather than a walk.
!
! Result codes:
!   1  the target page never executed -- the jmp was lost, or we fell through
!   2  D->I setup: the initial D load did NOT walk (nothing was installed)
!   3  D->I INDEPENDENCE FAILED: after the D-side walk installed the page, the
!      I-fetch of the same VA did not walk -- it was served from the D array,
!      so the two arrays are not independent (or the walker installs into both)
!   4  I->D INDEPENDENCE FAILED: the mirror image of 3
!   5  SPC moved -- an exception was taken where the walker should have resolved
!   6  I->D setup: after the TI flush the I-fetch did NOT walk
!   7  the TLB-miss vector was reached at all
!
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

        .text
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_fault - 0x400 ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page identity (W+X+C, U cleared for SMEP). This is
        ! ---- an LDTLB, so it lands in BOTH arrays -- which is exactly what
        ! ---- this code needs, since it both executes from and PC-relative-
        ! ---- loads out of that page.
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the slot both walks will probe for VA 0x00008000. The TSB
        ! ---- is never cleared, so every walk below is a warm TSB hit and no
        ! ---- software handler is ever needed.
        mov.l   p_tsb_slot, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_x, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Seed the SPC sentinel, then enable AT. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================= DIRECTION 1: D -> I ================================
        ! Baseline cnt_walks, then a D-side LOAD from VA 0x00008000. The DTLB
        ! does not hold it, so this walks and the install goes to the D side
        ! ONLY (cpu.vhd routes walker installs by walk_side_i).
        mov.l   p_walkcnt, r4
        mov.l   @r4, r8
        shlr16  r8                      ! r8 = cnt_walks before the D load

        mov.l   p_target_va, r6
        mov.l   @r6, r7                 ! D READ of VA 0x00008000 -> D-side walk

        mov.l   @r4, r13
        shlr16  r13                     ! r13 = cnt_walks after the D load

        ! ---- 2: the D load really walked (+1). Positive half of direction 1:
        ! ---- without it, check 3 could "pass" because nothing was installed.
        mov     r13, r2
        sub     r8, r2
        mov     #1, r3
        cmp/eq  r3, r2
        bt      1f
        mov     #2, r9
        bra     _fail
        nop
1:
        ! r13 now carries the D-side-only-installed baseline INTO the target
        ! page; registers survive the jmp, so no memory hand-off is needed.
        ! If the ITLB were the same array as the DTLB, the fetch below would
        ! HIT and cnt_walks would not move -- that is check 3, made in _target.
        mov.l   p_target, r0
        jmp     @r0
        nop

        mov     #1, r9                  ! fell through -> target never executed
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_walkcnt:      .long 0xFF000054        ! [31:16]=cnt_walks [15:0]=cnt_hits
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C8 ! identity: PPN=start, U cleared (SMEP)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsb_slot:     .long 0x00010100        ! hash(0x00008000) -- see header
p_vpn:          .long 0x00008000
p_asid:         .long 0x00000000
p_ptel_x:       .long 0x000080C9        ! PA 0x00008000 | W|X|C|V, U=0 (SMEP)
p_sent_spc:     .long 0xDEADBE00
p_target:       .long _target
p_target_va:    .long 0x00008000

#else
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! MISS-vector stub at VBR+0x400. Reaching it means an exception was
        ! taken where the walker should have resolved the access -- code 7.
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #7, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

! ======================================================================
! Translated-only code at VA 0x00008000 (sh32_tlbtext.x). Reaching it at all
! required an I-side walk, because the only prior install of this page went
! to the D side.
!
! _done/_fail are ~28 KB away, well outside bra's +/-4 KB displacement, so the
! exits use mov.l + jmp.
! ======================================================================
        .section .tlbtext, "ax"
        .balign 4
_target:
        ! ---- 5: SPC untouched -> no exception was entered on the way here;
        ! ---- the fetch was resolved by the walker, not by a miss vector.
        .word   0x0042                  ! STC SPC, r0
        mov.l   t_sent_spc, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #5, r9
        bra     _t_exit_fail
        nop
1:
        ! ---- 3: D -> I INDEPENDENCE. r13 is cnt_walks measured AFTER the
        ! ---- D-side load walked this very page in. Getting here required
        ! ---- another walk -- the I side had to fault the SAME VA in
        ! ---- separately. A shared array (or a walker install broadcast to
        ! ---- both arrays) makes this delta 0 and everything else still pass.
        mov.l   t_walkcnt, r4
        mov.l   @r4, r2
        shlr16  r2
        sub     r13, r2
        mov     #1, r3
        cmp/eq  r3, r2
        bt      2f
        mov     #3, r9
        bra     _t_exit_fail
        nop
2:
        ! ================= DIRECTION 2: I -> D ==============================
        ! Mirror image. Flush BOTH arrays (MMUCR.TI, AT kept on; the TSB is
        ! untouched so both walks below are warm hits), let the I side fault
        ! this page back in, then read from it and require a SECOND walk.
        !
        ! EVERYTHING from the flush to the last counter read uses REGISTERS
        ! ONLY. A PC-relative literal load is a D-side access to this very
        ! page, so it would consume the D-side miss the check is trying to
        ! observe. Preload the pointers first.
        mov.l   t_mmucr, r0             ! r0 = MMUCR
        mov.l   t_target_va, r6         ! r6 = 0x00008000
        mov     #5, r1                  ! TI | AT
        mov.l   @r4, r8
        shlr16  r8                      ! r8 = cnt_walks before the flush

        mov.l   r1, @r0                 ! FLUSH both arrays

        ! Outrun anything already fetched: the next translated fetch must
        ! really re-translate, and must do so BEFORE the counter read below.
        ! (The page is one TLB entry, so it walks exactly once however many
        ! instructions follow.)
        .rept 24
        nop
        .endr

        mov.l   @r4, r10                ! P4 read -- untranslated, no D walk
        shlr16  r10

        mov.l   @r6, r11                ! D READ of the same VA -> D-side walk

        mov.l   @r4, r12                ! P4 read -- untranslated, no D walk
        shlr16  r12

        ! ---- 6: the post-flush I-fetch really walked (+1). Positive half of
        ! ---- direction 2.
        mov     r10, r2
        sub     r8, r2
        mov     #1, r3
        cmp/eq  r3, r2
        bt      3f
        mov     #6, r9
        bra     _t_exit_fail
        nop
3:
        ! ---- 4: I -> D INDEPENDENCE. The I-side walk above installed this
        ! ---- page into the ITLB only, so the D read had to walk it in again.
        mov     r12, r2
        sub     r10, r2
        mov     #1, r3
        cmp/eq  r3, r2
        bt      4f
        mov     #4, r9
        bra     _t_exit_fail
        nop
4:
        mov.l   t_mmucr, r0             ! AT off (identity below, so execution
        mov     #0, r1                  ! continues at PA == VA unchanged)
        mov.l   r1, @r0
        mov     #0, r9
        mov.l   t_done, r0
        jmp     @r0
        nop

_t_exit_fail:
        mov.l   t_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   t_fail, r0
        jmp     @r0
        nop

        .align 2
t_sent_spc:     .long 0xDEADBE00
t_walkcnt:      .long 0xFF000054
t_mmucr:        .long 0xFF000010
t_target_va:    .long 0x00008000
t_done:         .long _done
t_fail:         .long _fail

#endif  ! CONFIG_PRIV_ARCH
