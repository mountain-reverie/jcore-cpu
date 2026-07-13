! mmusmep.S -- SMEP: kernel fetch of a user-executable page must IPROT,
!              and a USER-mode fetch of the same kind of page must NOT.
!
! J4 + MMU_ARCH + PRIV_ARCH. Installs a TLB entry, identity-mapped, for a
! page (_user_page below) with PTEL U=1 (user page), X=1 (executable),
! W=0, C=1 -- i.e. a page a user process is allowed to execute. Then,
! while remaining in KERNEL mode (SR.MD=1, the default), the test jumps
! into that page. Without SMEP enforcement in the I-side TLB protection
! check, this fetch is allowed (the existing check only flags U=0 pages
! accessed by MD=0 -- the opposite direction), and control lands on a
! real (identity-mapped) "detector" stub that cleanly fails the guard
! (r9=1, "no exception") instead of running off into undefined memory.
! With SMEP, a kernel (MD=1) fetch of a U=1 page must raise IPROT
! (EXPEVT=0x0A0) at VBR+0x400, with TEA=&_user_page.
!
! The TLB entry is identity-mapped (PPN = &_user_page) specifically so
! that the RED (pre-fix) case, where the fetch actually completes, lands
! on real, controlled code rather than an arbitrary physical address --
! see the mmu_sim.sh gotcha: a non-fault RED path that instead runs off
! into space must still resolve to a clean FAIL, not a hang/crash.
!
! Negative control (proves SMEP does not over-fire): after the kernel-mode
! sub-test above, the test drops to USER mode (SR.MD=0) and fetches/
! executes a SEPARATE identity-mapped U=1,X=1,W=0,C=1 page (_user_ok_page).
! This must be ALLOWED (no IPROT) -- it proves the RTL predicate is exactly
! `entry.u='1' AND md='1'`, not a broader `entry.u='1'`. The user-mode code
! sets a marker register (r10, unbanked by the RB swap on exception entry)
! and then executes TRAPA to trap back into the kernel (VBR+0x100), which
! records the marker, forces SSR.MD=1, and RTEs back. The kernel then
! checks the marker was actually set -- a positive, non-vacuous assertion
! that the user-mode fetch/execution really happened.
!
! Modeled on sim/tests/mmufault.S (its IPROT sub-test and user-mode MD=0
! drop, and its page-0 identity map needed to keep executing once AT is
! enabled) and the .vect/SIM_INSTR_MAGIC/_done/_fail/r9 result pattern in
! sim/tests/mmurun.S. The TRAPA round-trip machinery mirrors
! sim/tests/trapatest.S.
!
! PTEL flag bit layout (core/tlb.vhd, see mmufault.S comment):
!   bit7=W  bit6=X  bit5=U  bit4=D  bit3=C
!   SMEP target pages: X|U|C = 0x68  (W=0; forbidden to a KERNEL fetch
!   because it is a USER page, not because it's non-executable; allowed
!   to a USER fetch)
!
! J4 overlay opcodes (same encodings as mmufault.S):
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E
!   STC EXPEVT,r0=0x0052
!   STC SPC,r0=0x0042   LDC r0,SPC=0x404E
!
! Result codes:
!   0  pass
!   1  no exception taken (SMEP not enforced -- the RED-state failure)
!   2  EXPEVT != 0x0A0 (IPROT)
!   3  TEA != &_user_page
!   4  negative control: unexpected IPROT in user mode (SMEP over-fired
!      for MD=0, i.e. enforced on U=1 alone instead of U=1 AND MD=1)
!   5  negative control: user-mode code never trapped back (TRAPA lost)
!   6  negative control: marker not set (user-mode fetch/exec did not
!      actually run before trapping back)

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

        ! ---- VBR = _v_ifetch - 0x400 (so VBR+0x400=_v_ifetch). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map our own code's page: identity, KERNEL-ONLY (no U bit) so
        ! this mapping itself can never trip SMEP: W|X|C = 0xC8. Computed at
        ! runtime (mask &start down to its page) rather than hardcoded, since
        ! the .balign 4096 before _user_page (below) forces this whole
        ! object's .text into its own page-aligned region and its base is
        ! not an assemble-time constant. Needed so our own code (and the
        ! handler + globals that follow it) keeps fetching/loading once AT
        ! is enabled. ----
        mov.l   p_start_addr, r0
        mov.l   p_pagemask, r1
        and     r1, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN = start's page, ASID=0)
        mov.l   p_start_addr, r0
        and     r1, r0
        mov.l   p_ownpage_flags, r2
        or      r2, r0
        .word   0x406E                  ! LDC r0, PTEL = (start & pagemask) | W|X|C
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map _user_page: identity, user-executable, X|U|C = 0x68. ----
        mov.l   p_user_page_addr, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=&_user_page, ASID=0)
        mov.l   p_ptel_userx, r0
        .word   0x406E                  ! LDC r0, PTEL = &_user_page | 0x68
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Set up expected fault info. Stay in KERNEL mode (SR.MD=1). ----
        mov.l   p_g_exp_expevt, r0
        mov.l   c_iprot, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x0A0
        mov.l   p_g_exp_tea, r0
        mov.l   p_user_page_addr, r1
        mov.l   r1, @r0                 ! g_exp_tea = &_user_page
        mov.l   p_g_bad_expevt, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 2
        mov.l   p_g_bad_tea, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! TEA wrong -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_after, r1
        mov.l   r1, @r0                 ! resume -> after

        mov     #1, r9                  ! sentinel: no exception -> result 1
        mov.l   p_user_page_addr, r0
        jmp     @r0                     ! kernel fetch of U=1 page: should IPROT
        nop
        bra     _fail
        nop
ENTRY(after)
        ! _v_ifetch disabled AT on entry (kernel-mode sub-test above); re-enable
        ! it so the negative-control sub-test below actually exercises the MMU.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! MMUCR = 1 (AT=1)

        ! ==============================================================
        ! Negative control: a USER-mode (MD=0) fetch/execution of a
        ! U=1,X=1 page must be ALLOWED (no IPROT). Uses a SEPARATE
        ! identity-mapped page (_user_ok_page) that runs a marker then
        ! TRAPAs back -- _user_page's stub above unconditionally fails
        ! and must not be reused here.
        ! ==============================================================
        ! ---- Map _user_ok_page: identity, user-executable, X|U|C = 0x68. ----
        mov.l   p_userok_page_addr, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=&_user_ok_page, ASID=0)
        mov.l   p_ptel_userok, r0
        .word   0x406E                  ! LDC r0, PTEL = &_user_ok_page | 0x68
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! Any IPROT landing at _v_ifetch during this sub-test IS the
        ! failure under test (SMEP over-firing in user mode): force a
        ! guaranteed EXPEVT mismatch so it falls straight through to a
        ! distinct fail code instead of comparing against the stale
        ! kernel-mode sub-test's expectations.
        mov.l   p_g_exp_expevt, r0
        mov.l   c_bogus_expevt, r1
        mov.l   r1, @r0                  ! g_exp_expevt = impossible value
        mov.l   p_g_bad_expevt, r0
        mov     #4, r1
        mov.l   r1, @r0                  ! unexpected IPROT -> result 4

        ! Clear the marker the user-mode code is expected to set.
        mov.l   p_g_user_marker, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! Drop to user mode (clear SR.MD = bit 30 = 0x40000000).
        stc     sr, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr                  ! MD=0 after this
        nop
        nop
        nop
        nop

        mov     #5, r9                  ! sentinel: user code never trapped back
        mov.l   p_userok_page_addr, r0
        jmp     @r0                     ! ALLOWED: user fetch of U=1,X=1 page
        nop
        bra     _fail
        nop

ENTRY(after_ok)
        ! Positive, non-vacuous assertion: the user-mode code actually
        ! ran and set the marker before trapping back.
        mov.l   p_g_user_marker, r0
        mov.l   @r0, r1
        mov.l   c_marker_expect, r2
        cmp/eq  r2, r1
        bt      after_ok_pass
        mov     #6, r9                  ! marker not set -> user code didn't run
        bra     _fail
        nop
after_ok_pass:
        bra     _done
        nop

        ! ================================================================
        ! Pointer/constant literal pool for the main test body above. Kept
        ! close to it (rather than down by the vector handlers) since the
        ! mov.l @(disp,PC) encoding has a limited (+-1020 byte) reach.
        ! ================================================================
        .balign 4
p_rbclear:       .long 0xDFFFFFFF       ! clear SR.RB (bit 29)
p_mdmask:        .long 0xBFFFFFFF       ! clear SR.MD (bit 30) -> user mode
p_vbr_val:       .long _v_ifetch - 0x400
p_mmucr:         .long 0xFF000010
p_ptel_userx:    .long _user_page + 0x68  ! identity PPN | X|U|C, W=0
c_iprot:         .long 0x000000A0        ! EXPEVT IPROT
c_bogus_expevt:  .long 0xFFFFFFFF        ! guaranteed EXPEVT mismatch sentinel
c_marker_expect: .long 0x0000005A        ! expected _g_user_marker value
p_g_exp_expevt:  .long _g_exp_expevt
p_g_exp_tea:     .long _g_exp_tea
p_g_bad_expevt:  .long _g_bad_expevt
p_g_bad_tea:     .long _g_bad_tea
p_g_resume:      .long _g_resume
p_g_user_marker: .long _g_user_marker
p_after:         .long after
p_user_page_addr: .long _user_page
p_userok_page_addr: .long _user_ok_page
p_ptel_userok:   .long _user_ok_page + 0x68  ! identity PPN | X|U|C, W=0
p_start_addr:    .long start
p_pagemask:      .long 0xFFFFF000
p_ownpage_flags: .long 0x000000E8       ! W|X|U|C -- must be U=1: the negative-
                                         ! control sub-test's MD-drop sequence
                                         ! (stc/and/ldc sr + nops + jmp) executes
                                         ! FROM this page, and once MD flips to 0
                                         ! mid-sequence a U=0 mapping here would
                                         ! itself fault (user access to a
                                         ! supervisor-only page) before ever
                                         ! reaching _user_ok_page.

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

        ! ================================================================
        ! TRAPA handler at VBR+0x100 (_v_trapa), used only by the negative-
        ! control sub-test's user-mode->kernel round trip. Records the
        ! marker set by the user-mode code (r10, unbanked -- only R0-R7
        ! are RB-swapped on exception entry), forces SSR.MD=1 so RTE
        ! resumes in KERNEL mode, and resumes at after_ok.
        !
        ! Placed exactly 0x300 bytes before _v_ifetch (VBR+0x400) so a
        ! single VBR value (p_vbr_val = _v_ifetch - 0x400) covers both
        ! fixed vectors.
        ! ================================================================
        .balign 4
_v_trapa:                              ! = VBR + 0x100 = _v_ifetch - 0x300
        mov.l   Htrapa_marker, r0
        mov.l   r10, @r0                ! g_user_marker = r10 (set by user code)
        .word   0x0132                  ! STC SSR, r1
        mov.l   Htrapa_mdbit, r2
        or      r2, r1
        .word   0x413E                  ! LDC r1, SSR  (force MD=1 -> kernel on RTE)
        mov.l   Htrapa_resume, r0
        mov.l   @r0, r0                 ! r0 = after_ok address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

        .balign 4
Htrapa_marker:  .long _g_user_marker
Htrapa_mdbit:   .long 0x40000000        ! SR.MD bit, forced onto SSR before RTE
Htrapa_resume:  .long after_ok

        .space  0x300 - (. - _v_trapa), 0

        ! ================================================================
        ! Single vector handler at VBR+0x400 (_v_ifetch). Disable AT,
        ! read EXPEVT and TEA, compare against expected, resume via SPC.
        ! ================================================================
        .balign 4
_v_ifetch:                             ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Htea_addr, r0
        mov.l   @r0, r2
        mov.l   Hexp_tea, r1
        mov.l   @r1, r1
        cmp/eq  r1, r2
        bf      _h_bad_tea
        mov.l   Hresume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_expevt:
        mov.l   Hbad_expevt, r0
        mov.l   @r0, r9                 ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

_h_bad_tea:
        mov.l   Hbad_tea, r0
        mov.l   @r0, r9                 ! r9 = fail code (TEA mismatch)
        bra     _fail
        nop

        .balign 4
Hmmucr:         .long 0xFF000010        ! P4 MMUCR
Hexp_expevt:    .long _g_exp_expevt
Htea_addr:      .long 0xFF00000C        ! P4 TEA register address
Hexp_tea:       .long _g_exp_tea
Hresume:        .long _g_resume
Hbad_expevt:    .long _g_bad_expevt
Hbad_tea:       .long _g_bad_tea

        ! ================================================================
        ! Handler globals.
        ! ================================================================
        .balign 4
_g_exp_expevt:  .long 0
_g_exp_tea:     .long 0
_g_resume:      .long 0
_g_bad_expevt:  .long 0
_g_bad_tea:     .long 0
_g_user_marker: .long 0                 ! set by _user_ok_page, checked by after_ok

        ! ================================================================
        ! Identity-mapped "user" page. In the GREEN (SMEP-enforced) case
        ! this code never runs -- IPROT fires on the fetch attempt itself.
        ! In the RED (pre-fix) case the kernel fetch succeeds and lands
        ! here; the stub deterministically fails the guard (r9=1) instead
        ! of running off into undefined memory.
        ! ================================================================
        .balign 4096
_user_page:
        mov     #1, r9
        bra     _fail
        nop

        ! ================================================================
        ! Identity-mapped "user-ok" page: same U=1,X=1,W=0,C=1 permissions,
        ! but used ONLY by the negative-control sub-test, executed in USER
        ! mode (MD=0), where this fetch must be ALLOWED. Sets a marker
        ! register (r10) then traps back to the kernel via TRAPA. The
        ! trailing self-loop is a safety net only -- TRAPA unconditionally
        ! traps, so it should never be reached.
        ! ================================================================
        .balign 4096
_user_ok_page:
        mov     #0x5A, r10              ! marker: prove this fetch/exec ran
        trapa   #1                      ! -> VBR+0x100 (_v_trapa)
1:      bra     1b
        nop

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
