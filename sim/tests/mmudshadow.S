! mmudshadow.S -- the shadow fill is ONE-WAY, and it never duplicates work.
!
! Companion to mmuishadow.S, which proves the I->D shadow fill HAPPENS. This
! guard pins the two properties that bound it, both of which a naive "always
! write both arrays on an I-side install" would violate while leaving
! mmuishadow green:
!
!   LEG 1 -- D DOES NOT SHADOW INTO I.
!     Load from a page that has never been executed. That is a D-side miss, so
!     the walker installs into the DTLB. Then JUMP to that page: the ITLB must
!     still have to walk. A D->I shadow would make the jump hit, and every
!     data page would burn one of the ITLB's 8 entries for a mapping it can
!     never legally use.
!
!   LEG 2 -- I->D ON AN ALREADY-RESIDENT PAGE WRITES NOTHING.
!     Continue from leg 1: the page is now resident in BOTH arrays -- demand
!     in the DTLB (leg 1's load) and demand in the ITLB (leg 1's jump). The
!     ITLB install in leg 1 fired the shadow fill, and the shadow fill found
!     the DTLB entry already there. It must have done NOTHING: no second DTLB
!     slot (which would be a duplicate, i.e. a fatal S-I5 multi-hit on the next
!     D access), and no rewrite of the existing slot (which would demote a hot
!     demand entry to the speculative NRU-victim state -- see tlb.vhd `spec`).
!
!     THE OBSERVABLE IS EXACT, not statistical: P4 TLBINST (0xFF000058,
!     [31:16]=ITLB slot writes [15:0]=DTLB slot writes) counts slots ACTUALLY
!     written, so a skipped speculative install is absent from it. Across
!     leg 1's jump the required delta is EXACTLY +1 ITLB write and +0 DTLB
!     writes. Note that a duplicate-entry defect would ALSO be caught by the
!     multi-hit check on the leg-3 load below, independently of the counter --
!     the two observations are deliberately not the same mechanism.
!
!   LEG 3 -- the page still translates correctly afterwards.
!     Read the page again and check the value. This is what makes leg 2's
!     "nothing happened" a statement about a WORKING TLB rather than about a
!     TLB that lost the entry: skipping the install must not have dropped it.
!
! The page is `.tlbtext` at VA 0x00008000 (identity), linked by
! sim/tests/sh32_tlbtext.x -- same arrangement as mmuwalkiside.S/mmusplit.S.
! Leg 1's load happens BEFORE anything on that page is fetched, which is the
! whole construction: the DTLB entry must predate the ITLB entry.
!
! ORDER-CRITICALITY, inherited from mmuishadow.S: once execution moves onto the
! observed page, a PC-relative literal load is itself a D-side access to it.
! The counter snapshots around the jump are therefore taken from P4 addresses
! built out of IMMEDIATES, never loaded from a literal pool on that page.
!
! Slot arithmetic, using mmutsb.S's documented hash:
!   VA 0x00008000 -> vpn 0x08, hash 0x08^(0x08>>6)=0x08, idx 0x08 -> 0x00010100
!
! Result codes:
!   1  the target page never executed -- the jmp was lost, or we fell through
!   2  an exception was taken (SPC moved) where the walker should have resolved
!   3  LEG 1 setup: the initial D load did not walk -- nothing was installed,
!      so the rest of the guard would be vacuous
!   4  LEG 1 DEFECT: the jump to the page did NOT walk. The D-side install had
!      already populated the ITLB -- a D->I shadow exists and must not
!   5  LEG 2 DEFECT: the DTLB write count moved across the jump. The shadow
!      fill rewrote (or duplicated) an entry that was already resident
!   6  LEG 2 DEFECT: the ITLB write count did not advance by exactly 1
!   7  LEG 3: the page no longer reads back correctly -- the skipped install
!      lost the translation
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

        mov     #0, r9                  ! known result-code state, see the stub

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

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the slot both sides will probe for VA 0x00008000. W and X
        ! ---- are both set: leg 1 reads the page and then executes it. ----
        mov.l   p_tsb_slot, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_wx, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Seed the SPC sentinel, then enable AT. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC

        ! ---- This text's own code page, GLOBAL, way 1 (cannot displace the
        ! ---- way-0 entry above). U=0 for SMEP. Same helper-derived set
        ! ---- address as every other walker guard. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================= LEG 1a: load from a NEVER-EXECUTED page ==========
        ! This is the D side's first touch of VA 0x00008000, and the I side has
        ! never fetched from it. The walker must install into the DTLB only.
        mov.l   p_walkcnt, r0
        mov.l   @r0, r11                ! walk counters BEFORE
        mov.l   p_target_val, r1        ! address of the probe word on the page
        mov.l   @r1, r2                 ! <- the D-side miss
        mov.l   p_walkcnt, r0
        mov.l   @r0, r3                 ! walk counters AFTER
        cmp/eq  r11, r3
        bf      1f
        mov     #3, r9                  ! the load did not walk: vacuous
        bra     _fail
        nop
1:
        ! ---- Snapshot the INSTALL counters, then jump onto the page. The
        ! ---- snapshot must be taken here, on THIS page, while literal loads
        ! ---- are still free -- see the header. ----
        mov.l   p_tlbinst, r0
        mov.l   @r0, r13                ! install counters BEFORE the jump
        mov.l   p_walkcnt, r0
        mov.l   @r0, r11                ! walk counters BEFORE the jump
        mov.l   p_target, r0
        jmp     @r0                     ! <- the I-side miss
        nop

        mov     #1, r9                  ! fell through: target never executed
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD
p_tsbslot_reg:  .long 0xFF000048
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
p_tsb_slot:     .long 0x00010100
p_vpn:          .long 0x00008000
p_asid:         .long 0x00000000
p_ptel_wx:      .long 0x000080C9        ! PA 0x00008000 | W|X|C|V, U=0 (SMEP)
p_sent_spc:     .long 0xDEADBE00
p_walkcnt:      .long 0xFF000054
p_tlbinst:      .long 0xFF000058
p_target:       .long _target
p_target_val:   .long t_probe_val

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
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        tst     r9, r9
        bf      1f
        mov     #2, r9
1:
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

! ======================================================================
! The observed page. Linked at VA 0x00008000 by sh32_tlbtext.x. Reached by
! a LOAD first (leg 1a, above) and only then by a fetch.
! ======================================================================
        .section .tlbtext, "ax"
        .balign 4
_target:
        mov     #7, r9                  ! default code if anything below faults

        ! ---- LEG 1b: the jump had to walk. r11 holds the pre-jump walk
        ! ---- counters. Address from immediates only -- no literal touched
        ! ---- yet, so the counters still describe the jump alone.
        ! ---- -1 -> 0xFFFFFFFF, <<16 -> 0xFFFF0000, <<8 -> 0xFF000000.
        mov     #-1, r0
        shll16  r0
        shll8   r0
        mov     r0, r14                 ! r14 = 0xFF000000
        mov     r14, r0
        add     #0x54, r0
        mov.l   @r0, r1                 ! walk counters AFTER the jump
        cmp/eq  r11, r1
        bf      1f
        mov     #4, r9                  ! DEFECT: the fetch did not walk ->
        bra     _t_exit_fail            ! the D-side install had filled the ITLB
        nop
1:
        ! ---- LEG 2: install counters across the jump. Exactly +1 ITLB write
        ! ---- and +0 DTLB writes. r13 holds the pre-jump value.
        mov     r14, r0
        add     #0x58, r0
        mov.l   @r0, r2                 ! install counters AFTER the jump

        ! DTLB half first: it is the property this guard exists for.
        mov     r2, r3
        extu.w  r3, r3                  ! r3 = DTLB writes AFTER
        mov     r13, r4
        extu.w  r4, r4                  ! r4 = DTLB writes BEFORE
        cmp/eq  r3, r4
        bt      2f
        mov     #5, r9                  ! DEFECT: the shadow fill wrote the DTLB
        bra     _t_exit_fail            ! for a page already resident there
        nop
2:
        ! ITLB half: exactly one write, the demand install for the fetch.
        mov     r2, r3
        shlr16  r3                      ! r3 = ITLB writes AFTER
        mov     r13, r4
        shlr16  r4                      ! r4 = ITLB writes BEFORE
        sub     r4, r3
        mov     #1, r4
        cmp/eq  r3, r4
        bt      3f
        mov     #6, r9                  ! DEFECT: not exactly one ITLB write
        bra     _t_exit_fail
        nop
3:
        ! ---- LEG 3: the page still translates. A duplicated DTLB entry would
        ! ---- also surface here, as a fatal multi-hit rather than a value
        ! ---- mismatch -- deliberately a different mechanism from leg 2.
        mov.l   t_probe_val, r1
        mov     #0x7B, r2
        cmp/eq  r1, r2
        bt      4f
        mov     #7, r9
        bra     _t_exit_fail
        nop
4:
        ! ---- 2: SPC untouched -> no exception was entered on the way here.
        .word   0x0042                  ! STC SPC, r0
        mov.l   t_sent_spc, r1
        cmp/eq  r0, r1
        bt      5f
        mov     #2, r9
        bra     _t_exit_fail
        nop
5:
        mov.l   t_mmucr, r0             ! AT off; identity below, so execution
        mov     #0, r1                  ! continues at PA == VA unchanged
        mov.l   r1, @r0
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
t_probe_val:    .long 0x0000007B
t_sent_spc:     .long 0xDEADBE00
t_mmucr:        .long 0xFF000010
t_done:         .long _done
t_fail:         .long _fail

#endif  ! CONFIG_PRIV_ARCH
