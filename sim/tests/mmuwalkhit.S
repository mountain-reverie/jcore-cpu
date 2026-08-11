! mmuwalkhit.S -- a TSB hit resolves with NO exception (Task 4).
!
! The whole point of stall-and-walk is that a TLB miss whose translation is
! already in the TSB never becomes an exception: cpu.vhd withholds ack while
! the hardware walker (core/tlb_walk.vhd) probes the TSB, installs the entry
! on a hit, and the faulting access simply replays. Checking only that the
! load returns the right data would ALSO pass if a software miss handler had
! run instead -- so this guard seeds SPC, SSR and EXPEVT with sentinels
! BEFORE the access and asserts they are unchanged AFTER it: that is positive
! proof no exception entry occurred (SPC<-PC / SSR<-SR happens on every
! exception entry, unconditionally, before any handler runs).
!
! It also asserts the walker's cnt_hits counter advanced (read back at the
! debug MMIO word 0xABCD0F00, wired in cpu.vhd Task 4 Step 2), so a walker
! that never runs at all cannot pass quietly just because the load data
! happens to look right.
!
! Setup mirrors mmutsb.S (proven-correct RB-clear / VBR / identity code-page
! mapping / TSBBR+TSBCFG config): same TSBBR=0x00010006, TSBCFG=0x00000061,
! and the same fault VA 0x00042000, which hashes to TSBPTR 0x00010060
! (see mmutsb.S's header comment for the arithmetic). This guard additionally
! fills that TSB slot with a valid entry (mmuwalk_common.inc's tsb_fill)
! before AT is enabled, so the walker can resolve the miss instead of a
! software handler ever running.
!
! If translation truly is not resolved (walker AND software both absent /
! broken), the miss exception fires for real and control diverts to the
! VBR+0x400 stub below, which reports code 2 directly -- reaching it at all
! is itself proof an exception was taken.
!
! Result codes:
!   1  load returned wrong data (translation wrong or never installed)
!   2  an exception was taken (either the VBR+0x400 stub was entered, or
!      -- belt and braces -- SPC no longer matches its seeded sentinel)
!   3  SSR changed  -> an exception was taken
!   4  EXPEVT changed -> an exception was taken
!   5  walk counter did not advance -> the walker never ran. UNREACHABLE BY
!      CONSTRUCTION: any defect that stops the hit install leaves the miss
!      condition true, which fires the miss-exception vector (caught by codes
!      2-4 above) before this check ever executes. Kept as belt-and-braces
!      only -- it names no coverage codes 2-4 do not already provide.
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

        ! ---- VBR = _v_fault - 0x400 (so a real MISS exception, if one is
        ! ---- ever taken, vectors to the stub below). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page identity (W+X+U+C = 0xE8; V forced by
        ! ---- LDTLB). `start` is forced 4 KB-aligned by the .balign 0x1000
        ! on _pad_page below (which raises the .text section's alignment),
        ! so PTEH/PTEL must use the `start` symbol (its PPN), exactly as
        ! mmutsb.S does. ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Seed the data page (AT off, direct physical write). Identity:
        ! ---- PA == VA == the fault address used below. ----
        mov.l   p_data_pa, r2
        mov.l   p_expect, r3
        mov.l   r3, @r2                 ! [0x00042000] = 0xA5A5A5A5

        ! ---- Configure the TSB via MMIO (cold-path config registers) and
        ! ---- fill the slot the walker will hash to for VA 0x00042000. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR  = 0x00010006
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG = 0x00000061

        mov.l   p_tsb_slot, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_data, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Seed the sentinels we will prove are untouched. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC
        mov.l   p_sent_ssr, r0
        .word   0x403E                  ! LDC r0, SSR

        ! ---- Take the miss: walker must resolve it with NO exception. ----
        mov.l   p_testva, r0
        mov.l   @r0, r4                 ! <-- TLB miss; walker installs & replays

        ! ---- 1: did we get the right data? ----
        mov.l   p_expect, r5
        cmp/eq  r4, r5
        mov     #1, r9
        bf      _fail_at

        ! ---- 2: SPC untouched? ----
        .word   0x0042                  ! STC SPC, r0  (0000 nnnn 0100 0010)
        mov.l   p_sent_spc, r1
        cmp/eq  r0, r1
        mov     #2, r9
        bf      _fail_at

        ! ---- 3: SSR untouched? ----
        .word   0x0032                  ! STC SSR, r0  (0000 nnnn 0011 0010)
        mov.l   p_sent_ssr, r1
        cmp/eq  r0, r1
        mov     #3, r9
        bf      _fail_at

        ! ---- 4: EXPEVT still at its reset value (never latched)? ----
        mov.l   p_expevt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #4, r9
        bf      _fail_at

        ! ---- 5: did the walker actually run? UNREACHABLE BY CONSTRUCTION --
        ! see the result-codes comment in the header. Kept as belt-and-braces. ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #5, r9
        bt      _fail_at

        ! all checks passed: disable AT, PASS.
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
p_tsb_slot:     .long 0x00010060        ! hash(0x00042000, TSBCFG, TSBBR) -- see header
p_vpn:          .long 0x00042000
p_asid:         .long 0x00000000
p_ptel_data:    .long 0x000420E9        ! PA 0x00042000 | V|C|U|X|W (0xE9)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_testva:       .long 0x00042000
p_sent_spc:     .long 0xDEADBE00
p_sent_ssr:     .long 0x40000000
p_expevt:       .long 0xFF000024
p_walkcnt:      .long 0xABCD0F00        ! cpu.vhd-local walker counter window (P2)

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
        ! hit -- report code 2 directly (same class as the inline SPC check:
        ! "an exception was taken").
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

        ! Force .text section alignment to 4 KB so `start` is page-aligned
        ! (mapped as one identity page above). The faulting VA 0x00042000 is
        ! never backed by code -- the TLB miss / TSB hit fires before any
        ! bus access reaches it via the fetch path.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
