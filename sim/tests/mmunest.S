! mmunest.S -- S-I4 family safety net: a TLB fault CONDITION arising INSIDE a
! handler (SR.RB=1) must NOT dispatch a nested exception -- it is suppressed --
! so the outer fault's saved context (SPC/SSR/bank) stays intact and the
! handler resumes cleanly.
!
! Mechanism under test (core/cpu.vhd, tlb_exc process): every TLB-exception
! dispatch arm is gated on `dp_sr.rb = '0'` (I-side ~line 493, D-side ~line
! 509). SR.RB=1 is this design's "in a handler" indicator (entry sets RB=1,
! RTE restores it). So a miss/prot condition that occurs while RB=1 is
! deliberately SUPPRESSED -- no second exception entry re-saves SSR<-SR over
! the first exception's still-live context. (Handlers reach memory through P1
! aliases, which the segment decode leaves untranslated regardless of AT; this
! guard instead probes the *translated* P0 path from inside the handler to
! prove the suppression directly.)
!
! This is the regression net for the S-I4b decoder work (making decode_core's
! next_op RB-aware for nested Slot-Illegal / TRAPA): if that change ever broke
! the RB-gated suppression or clean handler resumption, this guard goes red.
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). SAME strength -- all three
! result codes and both PASS conditions are unchanged. Two consequences of
! walker-only install shape the setup and are worth stating, because both are
! easy to get silently wrong:
!
!   * THE WALKER IS ITSELF GATED ON RB=0 (core/cpu.vhd walk_req), the same
!     gate this guard exists to test. So VA_Y CANNOT be walked in from inside
!     the handler: if it were not already resident the probe store would be a
!     plain miss (also suppressed) and there would be no DPROT_W condition at
!     all -- the guard would pass vacuously. VA_Y is therefore made resident by
!     a LOAD at RB=0 before the outer fault (a load is legal on a W=0 page),
!     and that load's returned seed is checked, so "VA_Y is resident and
!     read-only" is proven rather than assumed.
!   * VA_X's row must NOT pre-exist, or the outer load would walk in silently
!     and never fault. The handler publishes it, exactly as a real miss
!     handler now must: faulting VA from TEA, set address from the P4 helper,
!     row written through the P1 alias, plain RTE.
!
! Flow (single merged TLB-fault handler at VBR+0x400):
!   setup (RB=0, AT off): VBR; publish TSB rows for the identity code page and
!     for VA_Y=0x00200000 as READ-ONLY (W=0); seed backing pages; zero the
!     handler entry counter. Enable AT, then LOAD VA_Y once so it is RESIDENT
!     and read-only before any handler runs (fail 4 if it does not read back).
!   outer: RB=0 code loads VA_X=0x00100000 (UNMAPPED) -> D-load miss -> 0x400.
!   handler (RB=1): (1) entry_count++ (via P1 alias -- untranslated);
!     (2) re-entry check: entry_count>1 means a nested fault re-dispatched to
!     this same 0x400 vector -> suppression broken -> Result=3; (3) PROBE:
!     STORE to VA_Y (a translated P0 access to the R/O page). At MD=1 the kernel
!     still honours W, so this is a DPROT_W condition -- which, because RB=1,
!     must be SUPPRESSED (no re-dispatch to this handler). (4) publish the TSB
!     row for VA_X (faulting VA from TEA, set address from the P4 helper, row
!     written through P1) and RTE.
!   resume (RB=0): the VA_X load re-executes and now HITS -> r8 = seed_X.
!
!   PASS requires: entry_count == 1 (the in-handler DPROT_W did NOT re-enter
!   the handler -- suppression held), and r8 == seed_X (SPC/SSR were intact, so
!   the outer instruction re-ran and read the freshly-installed page).
!
!   BROKEN core (suppression gate removed): the in-handler probe store's DPROT_W
!   re-dispatches to VBR+0x400 -> the handler re-enters -> entry_count becomes 2
!   -> the re-entry check falls to _h_store_fault -> deterministic Result=3.
!
! RESIDUAL, unchanged from the LDTLB version and stated so it is not mistaken
! for something the migration introduced: a SUPPRESSED fault is by definition
! unobservable from software, so nothing in the guard can positively witness
! that the probe store really raised a DPROT_W condition. If VA_Y were mapped
! WRITABLE the probe would be an ordinary store and the guard would pass
! vacuously. What is now proven, and was not before, is that VA_Y is RESIDENT
! and readable with the intended PPN (fail 4); the W=0 term itself still rests
! on the RTL mutation below.
!
! Non-vacuity (verified previously): dropping the `dp_sr.rb = '0'` term from
! cpu.vhd's D-side dispatch gate makes the probe store's DPROT_W re-dispatch,
! re-entering the handler (entry_count>1) -> this guard fails.
!
! PTEL flag bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G
!                                 bit1=STALE bit0=V.  Identity PTE PA==VA.
!
! Result codes:
!   0  pass
!   1  entry_count != 1  -- handler not entered exactly once
!   2  r8 != seed_X      -- outer fault did not resume cleanly (context lost)
!   3  in-handler DPROT_W re-entered handler (entry_count>1) -- RB=1 suppression broken
!   4  the VA_Y warm-up load did not read back its seed -- VA_Y is not resident,
!      so the in-handler probe would not have been a DPROT_W at all (setup error)

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

        ! ---- ASIDR = 0 (single context). ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed backing pages via P1 (untranslated): PA_X and PA_Y. ----
        mov.l   k_bk_x, r0 ; mov.l v_seed_x, r1 ; mov.l r1, @r0   ! PA 0x00100000
        mov.l   k_bk_y, r0 ; mov.l v_seed_y, r1 ; mov.l r1, @r0   ! PA 0x00200000
        mov.l   k_ecnt, r0 ; mov #0, r1 ; mov.l r1, @r0          ! entry_count = 0

        ! ---- Configure the TSB (base 0x00014000, TSB_SIZE_LOG=8 -> 256 sets
        ! ---- x 32 bytes; HASH_SHIFT=6, HASH_MODE=1) and publish two rows:
        ! ---- page 0 (VA 0x0..0xFFF, holds the P0 code) identity kernel-exec
        ! ---- (W|X|C|V, U=0 -- a kernel fetch of a U=1 page is an SMEP
        ! ---- protection fault), and VA_Y as a READ-ONLY identity page.
        ! ---- VA_X deliberately has NO row: the outer load must fault.
        ! ---- AT is off, so these are plain P0 stores.
        mov.l   k_tsbbr_addr, r0
        mov.l   k_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   k_tsbcfg_addr, r0
        mov.l   k_tsbcfg_val, r1
        mov.l   r1, @r0
        mov.l   k_tsbslot, r12
        mov.l   k_tab, r14
        mov.l   k_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
        mov.l   @r14+, r8               ! PTEL
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ---- Make VA_Y RESIDENT at RB=0, where the walker is allowed to run.
        ! ---- A load is legal on a W=0 page, so this installs the entry
        ! ---- without faulting; checking the seed proves the entry really is
        ! ---- there (and is the right one) before the handler relies on it.
        mov.l   k_va_y, r0
        mov.l   @r0, r2
        mov.l   v_seed_y, r1
        cmp/eq  r1, r2
        bt      1f
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov     #4, r9
        bra     _fail
        nop
1:

        ! ================= OUTER FAULT =================
        ! VA_X is unmapped -> D-load miss -> vector 0x400 -> handler.
        mov.l   va_x, r0
        mov.l   @r0, r8                 ! outer load; re-executes after install

        ! ---- Disable AT before touching the sim result register. ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ================= VERIFY =================
        mov.l   k_ecnt, r0 ; mov.l @r0, r2 ; mov #1, r3
        cmp/eq  r3, r2 ; mov #1, r9 ; bf _fail   ! entry_count must be exactly 1

        mov.l   v_seed_x, r1
        cmp/eq  r1, r8 ; mov #2, r9 ; bf _fail   ! outer load resumed cleanly

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear: .long 0xDFFFFFFF
k_vbr:     .long 0x80000000 + _vbase
k_mmucr:   .long 0xFF000010
k_bk_x:    .long 0x00100000            ! identity backing of VA_X
k_bk_y:    .long 0x00200000            ! identity backing of VA_Y
k_ecnt:    .long 0x80002D00            ! handler entry counter (P1 scratch)
v_seed_x:  .long 0xA5A5000A
v_seed_y:  .long 0xC0FFEE01
va_x:      .long 0x00100000
k_va_y:    .long 0x00200000            ! VA_Y, read-only identity page
k_tsbbr_addr:  .long 0xFF000014
k_tsbbr_val:   .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
k_tsbcfg_addr: .long 0xFF000018
k_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
k_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
k_tab:         .long _tsb_tab
k_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! page 0 identity, W|X|C|V, U=0
        .long 0x00200000, 0x00000000, 0x00200071  ! VA_Y | X|U|D|V (NO W, C=0)
_tsb_tab_end:
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

#if CONFIG_PRIV_ARCH
        ! ===================== Exception vector base =====================
        ! VBR -> P1 alias of _vbase; hardware adds 0x400 for ALL TLB faults (the
        ! per-access-type vectors are merged). The outer D-load miss enters the
        ! handler here. On a BROKEN core the in-handler probe store's DPROT_W is
        ! NOT suppressed and re-dispatches to this SAME 0x400 vector -> the
        ! handler re-enters, which the entry_count>1 check below turns into a
        ! deterministic Result=3 (see _h_store_fault). On the correct core RB=1
        ! suppresses it, so the handler is entered exactly once.
        .balign 4
_vbase:
        .space 0x400, 0
_v_tlb:                                 ! _vbase + 0x400  (all TLB faults, merged)
        bra     _h_common
        nop

        ! ---- Minimal miss handler (bank-1 scratch; RB=1; AT stays on). ----
_h_common:
        ! entry_count++ (P1 alias, untranslated).
        mov.l   H_ecnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4

        ! Re-entry detector (replaces the old distinct-0x440 detector): with all
        ! TLB faults merged onto VBR+0x400, a NON-suppressed in-handler DPROT_W
        ! would re-dispatch to THIS handler. entry_count>1 therefore means the
        ! RB=1 suppression is broken -> deterministic fail (Result=3), instead of
        ! an unbounded re-entry loop.
        mov     #1, r6
        cmp/eq  r6, r5
        bf      _h_store_fault

        ! PROBE: store to VA_Y (translated P0, read-only page) -> DPROT_W that
        ! must be SUPPRESSED because RB=1 (no re-dispatch to this handler).
        mov.l   H_va_y, r0
        mov.l   H_probeval, r1
        mov.l   r1, @r0                 ! in-handler prot-violating store

        ! Publish the TSB row for VA_X: faulting VA from TEA, set address from
        ! the P4 helper, row written THROUGH THE P1 ALIAS (AT is on and the TSB
        ! is unmapped, so a P0 store from here would fault inside the handler).
        ! Then a plain RTE: back at RB=0 the load retries, misses, and the
        ! walker -- now ungated -- installs the row.
        mov.l   H_tea, r0
        mov.l   @r0, r1                 ! r1 = faulting VA
        mov.l   H_vpnmask, r2
        and     r2, r1
        mov.l   H_slot, r0
        mov.l   r1, @r0
        mov.l   @r0, r3                 ! r3 = 32-byte-aligned SET address (PA)
        mov.l   H_p1, r0
        or      r0, r3
        mov.l   H_ptel_x, r4            ! PA 0x00100000 | W|X|U|D|V
        mov     #0, r5                  ! ASID_TAG = 0
        mov.l   r4, @(8, r3)            ! data first ...
        mov.l   r5, @(4, r3)            ! ... tag_lo second ...
        mov.l   r1, @(0, r3)            ! ... tag_hi LAST (the commit point)
        rte
        nop

        ! ---- Deterministic non-vacuity fail: reached only if an in-handler
        ! store fault dispatched (i.e. the RB=1 suppression gate is broken). ----
_h_store_fault:
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT
        mov.l   H_result, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! Result = 3 (suppression broken)
1:      bra     1b
        nop

        .align 2
H_ecnt:    .long 0x80002D00
H_va_y:    .long 0x00200000
H_probeval:.long 0xDEADBEEF
H_ptel_x:  .long 0x001000F1            ! PA 0x00100000 | W|X|U|D|V (C=0)
H_tea:     .long 0xFF00000C            ! TEA: the faulting virtual address
H_vpnmask: .long 0xFFFFF000
H_slot:    .long 0xFF000048            ! P4_TSBSLOT
H_p1:      .long 0x80000000
H_mmucr:   .long 0xFF000010
H_result:  .long TEST_RESULT_ADDRESS

        ! ---- The image must reach past the END of the TSB (PA 0x14000..
        ! ---- 0x15FFF): the walker reads the TSB by PHYSICAL address and a
        ! ---- physical alias is backed by SRAM only within the loaded image.
_tsb_backing:
        .space 0x16000, 0
#endif
