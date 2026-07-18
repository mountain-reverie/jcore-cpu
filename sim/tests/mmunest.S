! mmunest.S -- S-I4 family safety net: a TLB fault CONDITION arising INSIDE a
! handler (SR.RB=1) must NOT dispatch a nested exception -- it is suppressed --
! so the outer fault's saved context (SPC/SSR/bank) stays intact and the
! handler resumes cleanly.
!
! Mechanism under test (core/cpu.vhd, tlb_exc process): every TLB-exception
! dispatch arm is gated on `dp_sr.rb = '0'` (I-side ~line 493, D-side ~line
! 509). SR.RB=1 is this design's "in a handler" indicator (entry sets RB=1,
! LDTLB.R/RTE restores it). So a miss/prot condition that occurs while RB=1 is
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
! Flow (single D-load-miss handler at VBR+0x420, minimal LDTLB install):
!   setup (RB=0, AT off): VBR; pre-install VA_Y=0x00200000 as a READ-ONLY
!     (W=0), identity page via a direct LDTLB; seed backing pages; zero the
!     handler entry counter. Enable AT.
!   outer: RB=0 code loads VA_X=0x00100000 (UNMAPPED) -> D-load miss -> 0x420.
!   handler (RB=1): (1) entry_count++ (via P1 alias -- untranslated);
!     (2) PROBE: STORE to VA_Y (a translated P0 access to the R/O page). At
!     MD=1 the kernel still honours W, so this is a DPROT_W condition -- which,
!     because RB=1, must be SUPPRESSED (no nested 0x440 entry). (3) LDC the
!     precomputed PTEL for VA_X and LDTLB.RN -- installs VA_X (PTEH already
!     holds the faulting VPN) and returns atomically.
!   resume (RB=0): the VA_X load re-executes and now HITS -> r8 = seed_X.
!
!   PASS requires: entry_count == 1 (the in-handler DPROT_W did NOT re-enter
!   the handler -- suppression held), and r8 == seed_X (SPC/SSR were intact, so
!   the outer instruction re-ran and read the freshly-installed page).
!
!   BROKEN core (suppression gate removed): the in-handler probe store
!   dispatches a DPROT_W -> vector 0x440 -> _h_store_fault -> deterministic
!   Result=3 (and, in practice, SPC/SSR clobber would also corrupt the resume).
!
! Non-vacuity (verified): dropping the `dp_sr.rb = '0'` term from cpu.vhd's
! D-side dispatch gate makes this guard fail (the probe store's DPROT_W then
! dispatches to 0x440).
!
! PTEL flag bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G
!                                 bit1=STALE bit0=V.  Identity PTE PA==VA.
!
! Result codes:
!   0  pass
!   1  entry_count != 1  -- handler not entered exactly once
!   2  r8 != seed_X      -- outer fault did not resume cleanly (context lost)
!   3  in-handler DPROT_W dispatched to 0x440 -- RB=1 suppression is broken

#include "sim_instr.h"
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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

        ! ---- Map page 0 (VA 0x0..0xFFF, holds ALL code+vectors) identity,
        ! kernel-exec (W|X|C, U=0) so code fetches HIT once AT is on. Main code
        ! runs MD=1/RB=0; a U=0 page is fetchable and avoids SMEP. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN 0)
        mov.l   p_ptel_code, r0        ! PA 0 | W|X|C, kernel
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Pre-install VA_Y=0x00200000 as READ-ONLY (W=0) identity page,
        ! directly, AT off. ----
        mov.l   p_pteh_y, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN of VA_Y)
        mov.l   p_ptel_y, r0            ! PA 0x00200000 | X|U|C|V (NO W) = read-only
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= OUTER FAULT =================
        ! VA_X is unmapped -> D-load miss -> vector 0x420 -> handler.
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
p_ptel_code:.long 0x000000C8            ! PA 0 | W|X|C (kernel code page)
p_pteh_y:  .long 0x00200000            ! VPN of VA_Y
p_ptel_y:  .long 0x00200071            ! PA 0x00200000 | X|U|D|V (W=0 -> read-only, C=0)
va_x:      .long 0x00100000
p_ptel_x:  .long 0x001000F1            ! PA 0x00100000 | W|X|U|D|V (C=0)
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! ===================== Exception vector base =====================
        ! VBR -> P1 alias of _vbase; hardware adds 0x420 (D-load miss) or, ONLY
        ! on a broken core, 0x440 (D-store miss/prot). On the correct core the
        ! in-handler probe store's DPROT_W is suppressed (RB=1), so 0x440 is
        ! NEVER taken; wiring it to a deterministic fail makes the non-vacuity
        ! case a clean Result=3 rather than a derail.
        .balign 4
_vbase:
        .space 0x420, 0
_v_load:                                ! _vbase + 0x420  (DMISS_R)
        bra     _h_common
        nop
        .space (0x440 - 0x420 - 4), 0
_v_store:                               ! _vbase + 0x440  (DMISS_W / DPROT_W)
        bra     _h_store_fault          ! reached only if RB=1 suppression is broken
        nop

        ! ---- Minimal miss handler (bank-1 scratch; RB=1; AT stays on). ----
_h_common:
        ! entry_count++ (P1 alias, untranslated).
        mov.l   H_ecnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4

        ! PROBE: store to VA_Y (translated P0, read-only page) -> DPROT_W that
        ! must be SUPPRESSED because RB=1 (no nested 0x440 entry).
        mov.l   H_va_y, r0
        mov.l   H_probeval, r1
        mov.l   r1, @r0                 ! in-handler prot-violating store

        ! Install VA_X from the precomputed PTEL (PTEH holds the faulting VPN).
        mov.l   H_ptel_x, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0078                  ! LDTLB.RN (install + return atomically)

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
H_mmucr:   .long 0xFF000010
H_result:  .long TEST_RESULT_ADDRESS
#endif
