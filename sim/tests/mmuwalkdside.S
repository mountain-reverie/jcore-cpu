! mmuwalkdside.S -- a faulting STORE walks, installs, and then actually stores,
!                    at the TRANSLATED address.
!
! This is the walker's riskiest interaction. cpu.vhd's d_store_faulting logic
! demotes a faulting store to a READ on the external bus so memory is not
! mutated before the fault resolves, and cpu.vhd withholds dp_db_i.ack while
! the walker borrows that same bus (`and not walk_busy'). If the two interact
! wrongly the store is either LOST (memory never written) or COMMITTED EARLY,
! before the TLB entry exists -- which writes to the UNTRANSLATED VA.
!
! ---- why the mapping here is NOT identity ---------------------------------
! Every other walker guard maps its data page identity (VA == PA). Under an
! identity map an early, undemoted store lands at the same word the correct,
! translated store would, so "memory was mutated before the fault resolved" is
! INVISIBLE -- the guard passes either way. Measured: with the demote deleted
! outright, an identity-mapped version of this guard stayed green.
!
! So both pages here RELOCATE, and the guard checks both ends:
!
!   VA 0x00042000 -> PA 0x00044000     (sub-test A, and A+4 for sub-test B)
!   VA 0x00043000 -> PA 0x00045000     (sub-test B)
!
! The PA words must receive the patterns; the VA-as-physical words must still
! hold their pre-seeded 0x11111111. A store that commits before the walk
! installs shows up as the second of those failing (code 2), which no amount of
! "the data is where I expected it" checking on an identity map can see.
!
! ---- sub-tests ------------------------------------------------------------
! A: a single faulting store. The page is absent from the TLB but present in
!    the TSB with W=1, so the walker must install it and the store must then
!    commit, once, at the translated address.
!
! B: the back-to-back case the d_store_faulting comment explicitly warns about
!    -- an already-resolved store still completing its write on the bus while
!    the NEXT instruction's access faults. A demote keyed on the global
!    tlb_exc_pend would collateral-damage the older store; this guard then
!    reports code 3 (older store lost) while code 4 (younger store lost) stays
!    green, so the two defects cannot be conflated.
!
! All verification runs with AT OFF: the TSB itself lives at an unmapped VA, so
! reading it back under translation would itself miss and walk. With AT off
! every address below is physical.
!
! Setup mirrors the proven-correct mmuwalkhit.S (RB clear / VBR / identity code
! page / TSBBR=0x00010006 / TSBCFG=0x00000061). Slot arithmetic uses mmutsb.S's
! documented hash, which keys on the VA:
!   VA 0x00042000 -> vpn 0x42, hash 0x42^(0x42>>6)=0x43, idx 0x03 -> 0x00010030
!   VA 0x00043000 -> vpn 0x43, hash 0x43^(0x43>>6)=0x42, idx 0x02 -> 0x00010020
!
! Result codes:
!   1  sub-test A: the store never landed at its PA (write lost across the walk)
!   2  a store landed at the UNTRANSLATED VA -- it committed before the walker
!      installed the entry (demote missing/ineffective)
!   3  sub-test B: the OLDER, already-resolved store was lost (collateral
!      damage from a demote keyed on the global fault signal)
!   4  sub-test B: the YOUNGER, faulting store was lost
!   5  an exception was taken (SPC moved) -- the walker did not resolve it
!   6  the walk counters do not read 2 walks / 2 hits
!   7  a TSB tag was overwritten -- the walker's own probe address leaked onto
!      the demoted store's write
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

        ! ---- Map the code page identity (W+X+C, U cleared for SMEP). ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Pre-seed BOTH ends of both mappings (AT off, direct physical
        ! ---- writes) with a "not yet stored" value. ----
        mov.l   p_notyet, r1
        mov.l   p_pa_a, r0
        mov.l   r1, @r0
        mov.l   p_pa_a4, r0
        mov.l   r1, @r0
        mov.l   p_pa_b, r0
        mov.l   r1, @r0
        mov.l   p_va_a, r0
        mov.l   r1, @r0
        mov.l   p_va_a4, r0
        mov.l   r1, @r0
        mov.l   p_va_b, r0
        mov.l   r1, @r0

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill both TSB slots (W=1 so the stores are permitted). ----
        mov.l   p_tsb_slot_a, r0
        mov.l   p_vpn_a,  r1
        mov.l   p_asid,   r2
        mov.l   p_ptel_a, r3
        tsb_fill r0, r1, r2, r3

        mov.l   p_tsb_slot_b, r0
        mov.l   p_vpn_b,  r1
        mov.l   p_asid,   r2
        mov.l   p_ptel_b, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Seed the SPC sentinel, then enable AT. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Pre-load addresses/data so the stores below are adjacent
        ! ---- instructions with no intervening literal loads. ----
        mov.l   p_va_a,  r4
        mov.l   p_va_a4, r5
        mov.l   p_va_b,  r6
        mov.l   p_pat_a,  r7
        mov.l   p_pat_a4, r8
        mov.l   p_pat_b,  r10

        ! ---- sub-test A: one faulting store. ----
        mov.l   r7, @r4                 ! <-- TLB miss on VA 0x00042000; walk #1

        ! ---- sub-test B: an already-resolved store (page A is now installed,
        ! ---- so this one HITS) immediately followed by a faulting one. ----
        mov.l   r8, @r5                 ! hits (VA 0x00042004)
        mov.l   r10, @r6                ! <-- TLB miss on VA 0x00043000; walk #2

        ! ---- Disable AT; everything below is a direct physical access. ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- 1: did sub-test A's store land at its PA, with the right data?
        mov.l   p_pa_a, r0
        mov.l   @r0, r1
        mov.l   p_pat_a, r2
        cmp/eq  r1, r2
        mov     #1, r9
        bf      _fail

        ! ---- 2: are all three VA-as-physical words still untouched? A store
        ! ---- that committed before the install would have landed on one.
        mov.l   p_notyet, r3
        mov     #2, r9
        mov.l   p_va_a, r0
        mov.l   @r0, r1
        cmp/eq  r1, r3
        bf      _fail
        mov.l   p_va_a4, r0
        mov.l   @r0, r1
        cmp/eq  r1, r3
        bf      _fail
        mov.l   p_va_b, r0
        mov.l   @r0, r1
        cmp/eq  r1, r3
        bf      _fail

        ! ---- 3: did the OLDER (hitting) store of sub-test B survive?
        mov.l   p_pa_a4, r0
        mov.l   @r0, r1
        mov.l   p_pat_a4, r2
        cmp/eq  r1, r2
        mov     #3, r9
        bf      _fail

        ! ---- 4: did the YOUNGER (faulting) store of sub-test B land?
        mov.l   p_pa_b, r0
        mov.l   @r0, r1
        mov.l   p_pat_b, r2
        cmp/eq  r1, r2
        mov     #4, r9
        bf      _fail

        ! ---- 5: SPC untouched -> no exception was ever entered.
        .word   0x0042                  ! STC SPC, r0
        mov.l   p_sent_spc, r1
        cmp/eq  r0, r1
        mov     #5, r9
        bf      _fail

        ! ---- 6: exactly two walks, both hits.
        mov.l   p_walkcnt, r0
        mov.l   @r0, r1
        mov.l   p_expect_cnt, r2
        cmp/eq  r1, r2
        mov     #6, r9
        bf      _fail

        ! ---- 7: both TSB tags intact (no leaked walker probe address).
        mov     #7, r9
        mov.l   p_tsb_slot_a, r0
        mov.l   @r0, r1
        mov.l   p_vpn_a, r2
        cmp/eq  r1, r2
        bf      _fail
        mov.l   p_tsb_slot_b, r0
        mov.l   @r0, r1
        mov.l   p_vpn_b, r2
        cmp/eq  r1, r2
        bf      _fail

        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C8 ! identity: PPN=start, U cleared (SMEP)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsb_slot_a:   .long 0x00010030        ! hash(VA 0x00042000) -- see header
p_tsb_slot_b:   .long 0x00010020        ! hash(VA 0x00043000) -- see header
p_vpn_a:        .long 0x00042000
p_vpn_b:        .long 0x00043000
p_ptel_a:       .long 0x000440E9        ! VA 0x00042000 -> PA 0x00044000, W|X|U|C|V
p_ptel_b:       .long 0x000450E9        ! VA 0x00043000 -> PA 0x00045000, W|X|U|C|V
p_asid:         .long 0x00000000
p_va_a:         .long 0x00042000
p_va_a4:        .long 0x00042004
p_va_b:         .long 0x00043000
p_pa_a:         .long 0x00044000
p_pa_a4:        .long 0x00044004
p_pa_b:         .long 0x00045000
p_pat_a:        .long 0x5A5A5A5A
p_pat_a4:       .long 0x3C3C3C3C
p_pat_b:        .long 0x7E7E7E7E
p_notyet:       .long 0x11111111
p_sent_spc:     .long 0xDEADBE00
p_walkcnt:      .long 0xABCD0F00        ! cnt_walks(31:16) : cnt_hits(15:0)
p_expect_cnt:   .long 0x00020002

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
        ! MISS-vector stub at VBR+0x400. Reaching it at all means an exception
        ! was taken during what should have been a stall-and-walk -- same class
        ! as the inline SPC check, so it reports code 5 too.
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #5, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
