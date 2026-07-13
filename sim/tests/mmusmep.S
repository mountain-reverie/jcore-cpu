! mmusmep.S -- SMEP: kernel fetch of a user-executable page must IPROT.
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
! Modeled on sim/tests/mmufault.S (its IPROT sub-test, and its page-0
! identity map needed to keep executing once AT is enabled) and the
! .vect/SIM_INSTR_MAGIC/_done/_fail/r9 result pattern in
! sim/tests/mmurun.S.
!
! PTEL flag bit layout (core/tlb.vhd, see mmufault.S comment):
!   bit7=W  bit6=X  bit5=U  bit4=D  bit3=C
!   SMEP target page: X|U|C = 0x68  (W=0; forbidden to a kernel fetch
!   because it is a USER page, not because it's non-executable)
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

        .balign 4
p_rbclear:       .long 0xDFFFFFFF       ! clear SR.RB (bit 29)
p_vbr_val:       .long _v_ifetch - 0x400
p_mmucr:         .long 0xFF000010
p_ptel_page0:    .long 0x000000E8       ! W|X|U|C
p_ptel_userx:    .long _user_page + 0x68  ! identity PPN | X|U|C, W=0
c_iprot:         .long 0x000000A0        ! EXPEVT IPROT
p_g_exp_expevt:  .long _g_exp_expevt
p_g_exp_tea:     .long _g_exp_tea
p_g_bad_expevt:  .long _g_bad_expevt
p_g_bad_tea:     .long _g_bad_tea
p_g_resume:      .long _g_resume
p_after:         .long after
p_user_page_addr: .long _user_page
p_start_addr:    .long start
p_pagemask:      .long 0xFFFFF000
p_ownpage_flags: .long 0x000000C8       ! W|X|C, no U (kernel-only)

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

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
