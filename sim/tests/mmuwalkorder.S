! mmuwalkorder.S -- a live walker does not disturb older-instruction-first
!                   fault dispatch.
!
! READ THE "WHAT THIS GUARD CANNOT DO" SECTION BELOW BEFORE EXTENDING IT. This
! file is a REGRESSION LOCK with an anti-vacuity assertion, not a differential
! ordering test, and that is a measured conclusion rather than a shortcut.
!
! The ORDERING INVARIANT ITSELF is not checked here -- no software can check it
! (see "WHAT THIS GUARD CANNOT DO" below). It is checked by a permanent RTL
! assertion, `p_walk_order_assert' in core/cpu.vhd, which is live in every
! simulation and fires if the gate on walk_i_miss is removed. See "WHERE THE
! REAL ORDERING CHECK LIVES" at the end of this header.
!
! ---- the gap ---------------------------------------------------------------
! The machine's rule is that the EARLIEST instruction in program order has its
! fault processed first. A D-side access is in MA and is therefore OLDER than
! the I-fetch running ahead of it, which is why the pipeline drains outstanding
! load/stores before processing an IMISS.
!
! The existing ordering guards -- mmuidorder, mmudrain, mmumhorder -- observe
! that on the EXCEPTION path, but none of them places a WALK in flight at the
! dispatch boundary. A walker hit takes no exception at all, so they cannot see
! anything the walker does; and because they contain no anti-vacuity assertion
! about the walker, they pass identically whether a walk happened or not.
!
! This guard puts a walk in flight AT the boundary and then asserts the
! ordering is unchanged, and asserts (cnt_walks >= 1) that the walk really did
! happen -- so it cannot pass vacuously with a dead walker.
!
! ---- construction ----------------------------------------------------------
! mmudrain.S's proven older-D/younger-I shape: a `jmp' whose TARGET page misses
! with a faulting LOAD in its delay slot.
!
!     jmp   @r14              ! target VA 0x00050000 -- absent from TLB and TSB
!     mov.l @r1, r4           ! delay slot: VA 0x00042000 -- absent from both
!
! Both sides miss. MEASURED on this tree: the I-fetch becomes eligible first
! (it reaches the bus before the delay-slot load does, so sig_db_o.en is still
! '0' and walk_i_miss's gate is satisfied), the walker walks the I side, finds
! the zeroed slot, and gives up. The D-side miss then arrives, and what this
! guard asserts is that the OLDER D-side fault is nevertheless the one that
! reaches VBR+0x400, with its own EXPEVT and TEA -- the younger I-side miss
! does not overtake it, and the I-side walk does not suppress it.
!
!
! Slot arithmetic, using mmutsb.S's documented hash:
!   VA 0x00042000 -> vpn 0x42, hash 0x42^(0x42>>6)=0x43, idx 0x03 -> 0x00010060
!   VA 0x00050000 -> vpn 0x50, hash 0x50^(0x50>>6)=0x51, idx 0x11 -> 0x00010110
! Both slots are left ZEROED: this guard is about which fault is dispatched,
! not about installs, and a zeroed slot makes every walk fail open so both
! misses survive to the exception path where they can be told apart.
!
! ---- WHAT THIS GUARD CANNOT DO: walker ordering is software-unobservable ----
! It does not assert "the walker served the D side first", because no software
! can. That is a measured result, not an assumption. Four mutations of the
! walker's ordering logic were applied to core/cpu.vhd, each rebuilt WITHOUT
! -n, and ALL FOUR left this guard -- and the third of them the ENTIRE 92-guard
! MMU suite -- GREEN:
!
!  1. walk_va flipped to prefer i_va_32.  GREEN, and necessarily so: the mux is
!     STRUCTURALLY UNREACHABLE. walk_i_miss requires sig_db_o.en = '0' and
!     walk_d_miss requires sig_db_o.en = '1', so the two are mutually exclusive
!     by construction and walk_va never chooses between them. Any guard that
!     "went red" on this mutation would be reacting to something else.
!
!  2. Per-side suppression collapsed to global
!     (walk_supp_i = walk_supp_d = walk_arm or walk_busy).  GREEN.
!
!  3. The ordering gate itself -- `and sig_db_o.en = '0' and d_fault_held = '0''
!     -- DELETED from walk_i_miss.  GREEN, and so was every other guard in the
!     suite. Its stated purpose (cpu.vhd) is that a walker takeover borrows the
!     data bus and would let an unrelated live D access commit externally and
!     then be replayed -- "harmless on plain SRAM, NOT harmless on MMIO or
!     TAS". Every address reachable under translation from this suite IS plain
!     SRAM, so a replayed transaction is by definition invisible.
!
!  4. walk_supp_i forced to '0' (the I-side miss exception no longer suppressed
!     during its own walk).  GREEN: the older D-side fault still wins dispatch,
!     because that ordering is decided by decode_core's next_op priority, not
!     by the walker.
!
! Walker-internal ordering is therefore an internal bus-ownership property, not
! an architectural one. This guard asserts the architectural consequence it CAN
! see -- and pins that the walker was demonstrably RUNNING while it saw it --
! rather than a counter pattern it cannot justify. Making walker ordering
! properly differential would need a translated MMIO or TAS target that a
! replayed transaction perturbs; there is none in this suite today.
!
! ---- WHERE THE REAL ORDERING CHECK LIVES: an RTL assertion ------------------
! Because software cannot observe it, the ordering gate is instead protected by
! a permanent RTL assertion -- `p_walk_order_assert' in core/cpu.vhd, inside
! the g_tlb_walk generate (so PRIV_ARCH/MMU_WALKER-gated, and inert in J1/J2
! and in synthesis). It re-states the invariant from the RAW, UNGATED miss
! conditions (walk_i_miss_raw / walk_i_arm_raw), deliberately NOT from
! walk_i_miss, so it is not tautological: deleting the gate makes it fire.
!
! It is active in EVERY simulation, not just this guard. VERIFIED: with the
! gate deleted (mutation 3 above) it fires with severity FAILURE and the
! harness reports the affected guard FAILED.
!
! For a long time the ONLY image that reached the violating cycle was
! `m8_dsdslot_0' -- a GENERATED fault-permutation axis that crosses it by
! accident, twice in 29 cases. That is not coverage: reshape or skip that case
! and the invariant goes unguarded. `mmuwalkorderhit.S' now builds the window
! ON PURPOSE (a stream of back-to-back HITTING stores draining across a page
! boundary into an unmapped page), and is the guard to keep in step with the
! gate. Read its header before touching either.
!
! If you are extending walker ordering, change the assertion together with the
! gate; if you tripped it, read the comment above p_walk_order_assert.
!
! ---- HISTORY recorded here so it is not rediscovered -----------------------
! This guard's I->D handover once exposed a walker defect: the failed I-side
! walk POISONED the D-side miss that followed it, because tlb_walk.vhd's
! `tried' one-shot cleared only when `req' fell, and `req' is the OR of both
! sides' miss terms, so it stayed high across the handover and the D-side miss
! never got a walk of its own. At the time that was fail-OPEN (the software
! miss handler resolved it), so it was written off here as a performance
! defect and this guard deliberately did not encode a counter pattern.
!
! That defect is FIXED (commit e6ee313: the one-shot is per-REQUEST, not per-
! `req'-LEVEL) and LOCKED by `sim/tests/mmuwalkrearm.S', which builds this same
! handover on purpose and requires the re-armed D-side miss to be resolved BY
! THE WALKER. Read that header before touching walker re-arm; the behaviour
! this paragraph used to describe as expected is what mmuwalkrearm now forbids.
!
! This guard still asserts only cnt_walks >= 1 -- not because the poisoning is
! tolerated, but because its subject is fault DISPATCH ORDER, and both of its
! probed TSB slots are deliberately zeroed, so every walk here fails open by
! construction and the exact count is not the property under test.
!
! Result codes:
!   1  no exception at all -- neither side faulted (the scenario did not run)
!   2  EXPEVT is not DMISS_R (0x060): the younger I-side fault overtook the
!      older D-side one, or the I-side walk suppressed the D-side miss arm
!      (per-side suppression collapsed to global)
!   3  TEA is not the D-side VA -- the fault dispatched is not the older one
!   4  cnt_walks == 0: no walk was in flight at the dispatch boundary, so the
!      ordering above was observed with a dead walker and proves nothing
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

        ! ---- Configure the TSB. Both probed slots stay zeroed on purpose. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Code page: the identity mapping that LDTLB used to install is
        ! ---- now a GLOBAL TSB entry that the walker installs on the first
        ! ---- instruction fetch after AT goes on. GLOBAL so no ASID change can
        ! ---- perturb it; U=0 (SMEP). The set address is asked of the P4 slot
        ! ---- helper (0xFF000048 -- the single tsb_ptr() implementation the
        ! ---- walker and TSBPTR also use), never hand-computed. WAY 1, so it
        ! ---- cannot displace the entries this guard places in way 0. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6         ! VA = PA = start (4 KB-aligned)
        mov     #0, r7
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- The dispatch boundary: younger I-fetch miss on the jmp target,
        ! ---- older D-side miss in the delay slot. ----
        mov.l   p_target, r14
        mov.l   p_va_d, r1
        jmp     @r14
        mov.l   @r1, r4                 ! delay slot: OLDER D-side miss

        mov     #1, r9                  ! no exception at all
        bra     _fail_at
        nop

! ---- Fault handler. Read the walker counters FIRST. Nothing below may itself
! ---- miss: the handler and its literals sit on the identity code page, and
! ---- 0xFF0000xx is P4, untranslated. ----
_v_miss:
        mov.l   p_walkcnt, r0
        mov.l   @r0, r12

        mov.l   p_expevt, r0
        mov.l   @r0, r1
        mov.l   p_exp_dmiss_r, r2
        cmp/eq  r1, r2
        mov     #2, r9
        bf      _fail_at

        mov.l   p_tea, r0
        mov.l   @r0, r1
        mov.l   p_va_d, r2
        cmp/eq  r1, r2
        mov     #3, r9
        bf      _fail_at

        ! ---- 4: anti-vacuity -- cnt_walks (bits 31:16) must be non-zero, so
        ! ---- the ordering above was observed with the walker actually live.
        shlr16  r12
        tst     r12, r12
        mov     #4, r9
        bt      _fail_at

        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

_fail_at:
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
p_ptel_code:    .long start + 0x000000CD ! identity: PPN=start, U cleared (SMEP)
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_va_d:         .long 0x00042000        ! D side; slot 0x00010060, zeroed
p_target:       .long 0x00050000        ! I side; slot 0x00010220, zeroed
p_expevt:       .long 0xFF000024
p_exp_dmiss_r:  .long 0x00000060        ! DMISS_R -- the OLDER fault
p_tea:          .long 0xFF00000C
p_walkcnt:      .long 0xFF000054        ! cnt_walks(31:16) : cnt_hits(15:0)

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
        bra     _v_miss
        nop

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
