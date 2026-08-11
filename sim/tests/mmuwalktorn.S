! mmuwalktorn.S -- the walker must never wrongly install a torn TSB entry;
!                   a fixed-order writer's only crossable window is safe.
!
! ---- the defect (arch/sh/mm/tlb-jcore.c, both TSB writers) -----------------
! A TSB slot is three words: tag_hi (VPN), tag_lo (ASID_TAG), data (PTEL).
! core/tlb_walk.vhd's hardware walker treats tag_hi as the sole commit point:
! it compares tag_hi first, then tag_lo, and only then reads data and installs
! it if V=1/STALE=0 (st_tag_hi/st_tag_lo/st_data). Nothing in that FSM can
! tell a freshly, fully-committed entry apart from one caught mid-write -- both
! are just "tag_hi matches, tag_lo matches, here is data". tlb-jcore.c used to
! write tag_hi FIRST, so a reader landing between its first and third store
! would see tag_hi already matching a new VPN while tag_lo/data still held a
! different, older translation: a torn read that installs a wrong translation
! with no exception and no diagnostic.
!
! ---- what a single-core guard can and cannot prove -------------------------
! A single-core cosim cannot interleave a second, concurrent writer against
! the walker's multi-cycle FSM -- cpu.vhd stalls/withholds ack for the whole
! walk, so nothing else runs on this core while it probes. Constructing the
! DANGEROUS intermediate state directly (tsb_fill an OLD entry, then overwrite
! ONLY tag_hi to the new VPN, leaving tag_lo/data stale) and asserting the
! walker does not install it is exactly what step 2 of this task did against
! the unmodified tree -- and it failed, deterministically, with result code 1
! (load returned the OLD, wrong page's data, no exception -- confirmed
! @79860000ps, see task-1-report.md). But that construction can never be made
! to PASS by any kernel-only fix: it pokes tag_hi/tag_lo/data directly and
! never executes tlb-jcore.c, so its outcome is a fixed function of the RTL
! alone (core/tlb_walk.vhd has no field that could ever distinguish the two
! cases) -- unfixable without an RTL change, which this task does not make.
!
! What DOES depend on the fix is which intermediate states are ever reachable
! in the first place. The fixed commit order is data, tag_lo, tag_hi LAST,
! with a barrier before the tag_hi store -- so the ONLY crossable window a
! reader can ever land in is: data and tag_lo already updated to the NEW
! translation, tag_hi STILL the OLD, stale VPN (not yet committed). That is
! what this guard constructs and checks:
!
!   1. tsb_fill() a fully valid, self-consistent OLD entry (VPN_OLD/ASID 0/
!      PTEL_OLD, pointing at a distinguishable OLD physical page).
!   2. Advance the slot to exactly the fixed order's one crossable point:
!      overwrite data and tag_lo to the NEW translation (PTEL_NEW/ASID 0),
!      leaving tag_hi = VPN_OLD, stale and NOT YET committed.
!   3. Fault on VPN_NEW. tag_hi (VPN_OLD) cannot match VPN_NEW, so the walker
!      MUST fail closed to a real miss exception -- not install anything --
!      landing at the VBR+0x400 stub. Reaching any OTHER outcome (a silent
!      resolve, or resolving to PA_OLD's data) would mean a reader can still
!      observe a match at this crossable point, which the commit-order fix is
!      supposed to make impossible.
!   4. The stub completes the deferred commit (writes tag_hi := VPN_NEW, the
!      barrier'd store tlb-jcore.c makes last) and RTEs back to retry the
!      faulting load.
!   5. The retry must now resolve, with no further exception, to PTEL_NEW's
!      data (PA_NEW, 0xA5A5A5A5) -- proving the walker installs the CORRECT,
!      fully-consistent entry once the real commit point is crossed.
!
! Result codes:
!   1  the first fault installed PA_OLD's data directly (0x5A5A5A5A) instead
!      of taking the miss exception -- the walker matched on a stale tag_hi,
!      which should be structurally impossible at this crossable point.
!   2  the first access did not fault at all (SPC/SSR sentinels survived) --
!      no miss exception was taken where one was required.
!   3  after the stub completes the commit and retries, the load returned the
!      wrong data (neither exception path nor correct resolution).
!   4  the VBR+0x400 stub was entered on the RETRY too (should have resolved
!      the walk cleanly, no exception).
!
! PASS: fault #1 lands cleanly in the stub (no silent wrong install), the
! stub finishes the commit, and the retried load returns PTEL_NEW's data with
! no further exception.
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

        ! ---- Map the code page identity (W+X+U+C, V forced by LDTLB). ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Seed the two distinguishable data pages (AT off, direct
        ! ---- physical writes). PA_NEW == VA_NEW (identity); PA_OLD is a
        ! ---- different page entirely. ----
        mov.l   p_data_pa_new, r2
        mov.l   p_expect_new, r3
        mov.l   r3, @r2                 ! [PA_NEW] = 0xA5A5A5A5

        mov.l   p_data_pa_old, r2
        mov.l   p_expect_old, r3
        mov.l   r3, @r2                 ! [PA_OLD] = 0x5A5A5A5A

        ! ---- Configure the TSB via MMIO. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- 1: fill the slot with a fully valid, self-consistent OLD
        ! ---- entry (tag_hi/tag_lo/data all committed, tsb_fill's order). ----
        mov.l   p_tsb_slot, r0
        mov.l   p_vpn_old,  r1
        mov.l   p_asid,     r2
        mov.l   p_ptel_old, r3
        tsb_fill r0, r1, r2, r3

        ! ---- 2: advance to the fixed order's one crossable point: data and
        ! ---- tag_lo already the NEW translation, tag_hi still VPN_OLD. ----
        mov.l   p_tsb_slot, r0
        mov.l   p_ptel_new, r1
        mov.l   r1, @(8, r0)            ! data   := PTEL_NEW
        mov.l   p_asid, r1
        mov.l   r1, @(4, r0)            ! tag_lo := ASID 0 (unchanged)
                                         ! tag_hi left at VPN_OLD -- NOT committed

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Seed sentinels: fault #1 below MUST take the miss exception. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC
        mov.l   p_sent_ssr, r0
        .word   0x403E                  ! LDC r0, SSR

        mov.l   p_armed, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Fault #1: must NOT resolve silently. ----
        mov.l   p_testva_new, r0
        mov.l   @r0, r4

        ! Fell through: no exception was taken at all.
        .word   0x0042                  ! STC SPC, r0
        mov.l   p_sent_spc, r1
        cmp/eq  r0, r1
        mov     #2, r9
        bt      _fail_at

        ! An exception WAS taken but we fell back here without going through
        ! the stub's RTE path (should be unreachable) -- treat as install of
        ! the torn data if it matches PA_OLD, else generic mismatch.
        mov.l   p_expect_old, r5
        cmp/eq  r4, r5
        mov     #1, r9
        bt      _fail_at
        mov     #3, r9
        bra     _fail_at
        nop

_after_retry:
        ! ---- Retry (post-stub) must resolve cleanly to PTEL_NEW's data. ----
        mov.l   p_testva_new, r0
        mov.l   @r0, r4

        mov.l   p_expect_new, r5
        cmp/eq  r4, r5
        mov     #3, r9
        bf      _fail_at

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

_v_miss:
        ! Reaching here at all IS the required outcome for fault #1: the
        ! walker correctly failed closed on the stale tag_hi. Complete the
        ! deferred commit (the barrier'd tag_hi store tlb-jcore.c makes
        ! last) and resume at the retry.
        mov.l   p_armed, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #4, r9                  ! unexpected second entry
        bt      _fail

        ! AT must be OFF for this direct physical write to the TSB region --
        ! same convention tsb_fill uses everywhere else in these guards.
        ! With AT still 1 (as it is here, mid-handler) this store would
        ! itself be translated as a virtual access to unmapped VA 0x00010030
        ! instead of landing in the TSB.
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov.l   p_tsb_slot, r0
        mov.l   p_vpn_new, r1
        mov.l   r1, @(0, r0)            ! tag_hi := VPN_NEW -- commit point

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov.l   p_armed, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov.l   p_after_retry, r0
        .word   0x404E                  ! LDC r0, SPC
        .word   0x002B                  ! RTE
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C8 ! identity: PPN=start, U cleared (SMEP)
p_data_pa_new:  .long 0x00042000
p_expect_new:   .long 0xA5A5A5A5
p_data_pa_old:  .long 0x00043000
p_expect_old:   .long 0x5A5A5A5A
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsb_slot:     .long 0x00010030        ! hash(0x00042000) -- see mmutsb.S header
p_vpn_old:      .long 0x00043000        ! a DIFFERENT VPN than the one faulted
p_vpn_new:      .long 0x00042000        ! the VPN actually faulted on
p_asid:         .long 0x00000000        ! SAME ASID for old and new
p_ptel_old:     .long 0x000430E9        ! PA 0x00043000 | V|C|U|X|W (0xE9)
p_ptel_new:     .long 0x000420E9        ! PA 0x00042000 | V|C|U|X|W (0xE9)
p_testva_new:   .long 0x00042000
p_sent_spc:     .long 0xDEADBE00
p_sent_ssr:     .long 0x40000000
p_armed:        .long 0x80002D08
p_after_retry:  .long _after_retry

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

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
