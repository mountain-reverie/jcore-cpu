! mmuwalkway1.S -- the actual associativity case: way 0 holds a DIFFERENT,
! VALID entry (a different VPN, not zero/empty), and the walker still finds
! the target translation in way 1 and installs it, with no exception.
!
! mmutsbvictim.S (Phase-2 Task 4) already proves "way 1 is reachable when way
! 0 is empty" (its check A) and that the victim selector varies. It does NOT
! prove the case that actually motivates a 2-way TSB: two DIFFERENT VPNs
! landing in the same set, one already resident in way 0, and a walk for the
! second one still succeeding out of way 1 without disturbing or being
! confused by way 0's live entry. That is the gap this guard closes.
!
! Setup: same set as mmutsbvictim/mmuwalkhit (TSBBR=0x00010006, TSBCFG=
! 0x00000061, set 0x00010060 = idx 3 << 5). Way 0 gets a VALID entry for VA
! 0x00043000 (a different VPN that also happens to want to sit in this set --
! same idx-3 set is not required for the guard's point, any distinct valid
! way-0 entry proves it, but choosing a real neighbour page keeps the fixture
! honest about what "conflict" means). Way 1 gets the target entry for VA
! 0x00042000. The walk is for 0x00042000: the walker must probe way 0 (tag_hi
! mismatch, VALID data, not garbage), then way 1 (match), install, and
! replay -- no exception.
!
! cnt_hits (0xFF000054[15:0]) is asserted as a DELTA across the walk, not
! an absolute -- an absolute is satisfied by hits earlier in the run.
!
! Mutation-verify: force tsb_ways back to 1 (core/cpu.vhd) and rebuild
! without -n. Expected: FAIL with code 2 (miss exception, way 1 unreachable)
! -- the same code mmutsbvictim reports for the same mutation, because both
! guards are exercising the same "is way 1 actually probed" property; what
! distinguishes this guard is code 1/6, which only THIS guard's way-0-conflict
! construction can produce.
!
! Result codes:
!   1  load returned wrong data (way-1 entry never installed, installed
!      wrong, or the walker got confused by way 0's live-but-mismatched entry)
!   2  an exception was taken (VBR+0x400 stub entered, or SPC changed)
!   3  SSR changed  -> an exception was taken
!   4  EXPEVT changed -> an exception was taken
!   5  walk counter never advanced -> the walker never ran
!   6  cnt_hits delta across the walk was not exactly 1
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

        ! ---- VBR = _v_fault - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page identity (SMEP-safe: U cleared). ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Seed the target data page (AT off, direct physical write). ----
        mov.l   p_data_pa, r2
        mov.l   p_expect, r3
        mov.l   r3, @r2                 ! [0x00042000] = 0xA5A5A5A5

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR  = 0x00010006
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG = 0x00000061

        ! ---- Zero the whole 32-byte set first, then install a REAL entry in
        ! ---- way 0 for a DIFFERENT VPN -- this is the case mmutsbvictim
        ! ---- does not build (its way 0 stays all-zero). ----
        mov.l   p_tsb_set, r0
        mov     #8, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        mov.l   p_tsb_set, r0
        mov.l   p_vpn_other, r1
        mov.l   p_asid,      r2
        mov.l   p_ptel_other, r3
        tsb_fill_way r0, 0, r1, r2, r3  ! way 0: valid entry, different VPN

        mov.l   p_tsb_set, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_data, r3
        tsb_fill_way r0, 16, r1, r2, r3 ! way 1: the target entry

        ! ---- Enable AT (MMUCR.AT=1). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Seed the no-exception sentinels. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC
        mov.l   p_sent_ssr, r0
        .word   0x403E                  ! LDC r0, SSR

        ! ---- Snapshot cnt_hits before the walk. ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r13
        mov.l   p_mask16, r1
        and     r1, r13

        ! ---- Take the miss: the walker probes way 0 (VALID entry, VPN
        ! ---- mismatch -- must not be treated as a hit or a fault), then
        ! ---- way 1 (match), install, and replay -- with NO exception. ----
        mov.l   p_testva, r0
        mov.l   @r0, r4

        ! ---- 1: right data? ----
        mov.l   p_expect, r5
        cmp/eq  r4, r5
        mov     #1, r9
        bf      _fail_at

        ! ---- 2: SPC untouched? ----
        .word   0x0042                  ! STC SPC, r0
        mov.l   p_sent_spc, r1
        cmp/eq  r0, r1
        mov     #2, r9
        bf      _fail_at

        ! ---- 3: SSR untouched? ----
        .word   0x0032                  ! STC SSR, r0
        mov.l   p_sent_ssr, r1
        cmp/eq  r0, r1
        mov     #3, r9
        bf      _fail_at

        ! ---- 4: EXPEVT still at its reset value? ----
        mov.l   p_expevt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #4, r9
        bf      _fail_at

        ! ---- 5: did the walker actually run? ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #5, r9
        bt      _fail_at

        ! ---- 6: cnt_hits advanced by EXACTLY 1 over this one walk. Delta,
        ! ---- never an absolute -- earlier guards in the same run already
        ! ---- moved this counter. ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r2
        mov.l   p_mask16, r3
        and     r3, r2
        sub     r13, r2
        mov     #1, r3
        cmp/eq  r3, r2
        mov     #6, r9
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

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C8 ! identity: PPN=start, U cleared (SMEP)
p_data_pa:      .long 0x00042000
p_expect:       .long 0xA5A5A5A5
p_tsb_set:      .long 0x00010060        ! set for VA 0x00042000: idx 3 << 5
p_vpn:          .long 0x00042000
p_vpn_other:    .long 0x00043000        ! different VPN, way-0 occupant
p_asid:         .long 0x00000000
p_ptel_data:    .long 0x000420E9        ! PA 0x00042000 | V|C|U|X|W (0xE9)
p_ptel_other:   .long 0x000430E9        ! PA 0x00043000 | V|C|U|X|W (0xE9) -- never dereferenced, just VALID
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6 (SETS)
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_testva:       .long 0x00042000
p_sent_spc:     .long 0xDEADBE00
p_sent_ssr:     .long 0x40000000
p_expevt:       .long 0xFF000024
p_walkcnt:      .long 0xFF000054        ! walker counter window (P4, RO)
p_mask16:       .long 0x0000FFFF

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
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ================================================================
        ! MISS-vector stub at VBR+0x400. Reaching this at all means a real
        ! exception was taken during what should have been a stall-and-walk
        ! hit on WAY 1 -- report code 2 directly.
        ! ================================================================
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #2, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text section alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
