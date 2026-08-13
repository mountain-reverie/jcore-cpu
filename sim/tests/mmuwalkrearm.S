! mmuwalkrearm.S -- the walker's one-shot is per-REQUEST, not per-`req'-LEVEL.
!
! REGRESSION LOCK for commit e6ee313 ("the walker one-shot is per-REQUEST, not
! per-req-LEVEL", core/tlb_walk.vhd). Reverting that commit turns this guard
! RED with Result=2. Read this header before reshaping anything below.
!
! ---- the defect ------------------------------------------------------------
! `tried' in core/tlb_walk.vhd exists so that a walk which gives up leaves the
! miss exception a cycle with `busy' = '0'. It used to be cleared only when
! `req' falls -- i.e. it was one-shot per `req' LEVEL. But `req' is the OR of
! the I-side and D-side miss terms, and ONE CONTINUOUS `req' assertion can span
! TWO DIFFERENT misses: a younger I-side fetch miss gives up and sets `tried',
! and then the OLDER instruction's D-side miss arrives while `req' is still
! high. `arm' was gated on `tried = '0'', so that second, entirely unrelated
! miss never got a walk of its own -- it was denied on the strength of a
! give-up recorded for a DIFFERENT VA.
!
! The fix makes the one-shot per REQUEST: `may_arm' re-arms when the requested
! VPN(31:12) differs from the one `tried' was set for, bounded by a saturating
! `giveups' counter (generic giveup_limit) that is cleared only when `req'
! falls. `may_arm' drives BOTH the `arm' output and the ST_IDLE arming branch,
! so the two cannot disagree -- the decision must be combinational, because
! cpu.vhd's exception process sees the miss in the very cycle the walk is
! denied.
!
! ---- why this needed a purpose-built guard ---------------------------------
! The defect was SOFTWARE-INVISIBLE for as long as guards still installed TLB
! entries themselves: a denied walk simply fell through to a software miss
! handler that ended in LDTLB.RN -- same architectural result, more cycles. So
! no guard that asserts "the right value came back" could ever see it, and
! indeed the entire 103-guard suite passed identically with the fix reverted.
! Now that the guards install via the walker alone, a denied walk that is never
! re-armed is a permanent fault loop rather than a slow path.
!
! What must be asserted is therefore not the VALUE but WHO RESOLVED IT: the
! re-armed D-side miss must be resolved BY THE WALKER, not by a software fault.
! The positive witness is the walker counter window at P4 0xFF000054
! ([31:16] = cnt_walks, [15:0] = cnt_hits), snapshotted before the act and
! required to advance -- the mmusplit / mmuirun / mmutsbcoh idiom. This guard
! also uses a stronger, cheaper witness: with the D-side miss resolved by the
! walker the D side takes NO EXCEPTION AT ALL, so the fault that reaches
! VBR+0x400 is the YOUNGER I-side IMISS (0x040) rather than the older
! DMISS_R (0x060). EXPEVT alone separates the two RTL states.
!
! ---- construction ----------------------------------------------------------
! mmuwalkorder.S's proven dispatch boundary -- a `jmp' whose target page misses
! with a faulting load in its delay slot -- with ONE change: the D-side VA now
! has a VALID TSB row on a DIFFERENT VPN from the I-side one.
!
!     jmp   @r14              ! target VA 0x00050000 -- absent from TLB and TSB
!     mov.l @r1, r4           ! delay slot: VA 0x00042000 -- VALID TSB row
!
! MEASURED on this tree (recorded in mmuwalkorder.S's header): the I-fetch
! becomes eligible first, the walker walks the I side, finds the zeroed slot
! for VPN 0x00050, and gives up -- setting `tried'. The OLDER D-side miss for
! VPN 0x00042 then arrives with `req' STILL HIGH. That is exactly the cycle the
! fix is about:
!
!   without e6ee313  `tried' = '1' denies the D-side walk. The D-side miss
!                    takes an exception, and because the older fault wins
!                    dispatch, EXPEVT = DMISS_R (0x060) -> Result=2.
!   with    e6ee313  VPN 0x00042 /= VPN 0x00050 and giveups < giveup_limit, so
!                    `may_arm' re-arms. The walker finds the valid row,
!                    installs, and the load replays with no exception. The
!                    only fault left is the younger I-side IMISS (0x040), and
!                    cnt_hits has advanced.
!
! The D-side row maps VA 0x00042000 -> PPN `start', the identity code page.
! That is deliberate: the walker reads the TSB and the installed page BY
! PHYSICAL ADDRESS, and physical aliases are backed by SRAM only inside the
! loaded image extent. Pointing the mapping at a page the image already
! contains removes any dependence on padding out to PA 0x00042000.
!
! Slot arithmetic is never hand-computed here: both set addresses are asked of
! the P4 slot helper at 0xFF000048 (the single tsb_ptr() implementation the
! walker and TSBPTR also use). The code page goes in WAY 1 and the D-side entry
! in WAY 0, so they cannot displace each other even on a set collision. The
! I-side slot for VA 0x00050000 is left ZEROED, which is what makes its walk
! give up and set `tried'.
!
! ---- anti-vacuity ----------------------------------------------------------
! Check 4 requires cnt_hits to have ADVANCED past a snapshot taken immediately
! before the jmp. A delta is required rather than "non-zero", because the code
! page itself is now resolved by a walk, so the absolute counter says nothing
! about THIS access. If the walker never runs at all -- e.g. clear V in the
! D-side row -- the D side faults and the guard fails at check 2 first, so
! this guard cannot pass with a dead walker in either direction.
!
! Result codes:
!   1  no exception at all -- the I-side jmp target did not miss, so the
!      dispatch boundary this guard is built on never formed
!   2  EXPEVT is not IMISS (0x040). Reverting e6ee313 lands here with
!      DMISS_R (0x060): the re-armed D-side miss was DENIED its walk and took
!      a software fault instead
!   3  TEA is not the I-side VA -- the fault reaching the vector is not the
!      I-side miss this guard expects to be the only survivor
!   4  cnt_hits did not advance across the boundary: the D-side access was not
!      resolved by the walker, so check 2 proves nothing
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

        ! ---- Ensure RB=0 (bank 0). walk_req is gated on dp_sr.rb = '0' and
        ! ---- the cosim starts in bank 1, so without this no walk ever arms.
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

        ! ---- ASID 0 for every entry below. ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

        ! ---- Code page, WAY 1: identity mapping the walker installs on the
        ! ---- first fetch after AT goes on. GLOBAL, U=0 (SMEP). ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6         ! VA = PA = start (4 KB-aligned)
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- D-side page, WAY 0: the entry the RE-ARMED walk must find. Its
        ! ---- VPN differs from the I-side one, which is the whole point. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_vpn_d, r6
        mov     #0, r7
        mov.l   p_ptel_d, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill r10, r6, r7, r8

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Snapshot cnt_hits immediately before the boundary. r13 is
        ! ---- unbanked, so it survives the RB=1 switch on exception entry. ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r13
        extu.w  r13, r13

        ! ---- The dispatch boundary: younger I-fetch miss on the jmp target
        ! ---- (zeroed slot -> walk gives up, `tried' set), older D-side miss
        ! ---- in the delay slot on a DIFFERENT VPN with a VALID row. ----
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

        ! ---- 2: the ONLY surviving fault must be the younger I-side IMISS.
        ! ---- DMISS_R here means the D-side miss was denied its walk.
        mov.l   p_expevt, r0
        mov.l   @r0, r1
        mov.l   p_exp_imiss, r2
        cmp/eq  r1, r2
        mov     #2, r9
        bf      _fail_at

        ! ---- 3: and it must be the I-side VA. ----
        mov.l   p_tea, r0
        mov.l   @r0, r1
        mov.l   p_target, r2
        cmp/eq  r1, r2
        mov     #3, r9
        bf      _fail_at

        ! ---- 4: anti-vacuity -- cnt_hits must have ADVANCED, i.e. the D-side
        ! ---- access really was resolved by the walker and not by software.
        extu.w  r12, r12
        cmp/eq  r13, r12
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
p_ptel_code:    .long start + 0x000000CD ! identity: PPN=start, W|X|C|G|V, U=0
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_vpn_d:        .long 0x00042000        ! D side VPN -- VALID row, way 0
p_ptel_d:       .long start + 0x000000CD ! PPN = the code page (backed by SRAM)
p_va_d:         .long 0x00042000
p_target:       .long 0x00050000        ! I side; slot zeroed -> walk gives up
p_expevt:       .long 0xFF000024
p_exp_imiss:    .long 0x00000040        ! IMISS -- the only fault that survives
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
        tst     r9, r9                  ! integrity net: 0 is the harness PASS
        bf      1f                      ! token, so _fail must never write it.
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
