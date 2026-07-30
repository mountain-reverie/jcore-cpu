! mmufsr.S -- MMUFSR (MMU Fault Status Register, MMIO 0xFF000028) guard.
!
! THE POINT OF THIS GUARD: DPROT_R and DPROT_W both raise EXPEVT=0x0C0 via
! the single merged vector VBR+0x400, so EXPEVT alone cannot tell a
! write-protect fault from a read-protect fault. MMUFSR carries the
! direction (and other fault-kind detail) that EXPEVT discards. This guard
! asserts the DPROT_W/DPROT_R pair: identical EXPEVT, distinct MMUFSR.
!
! Scaffolding mirrors sim/tests/mmufault.S: same .vect header, same single
! _v_tlb handler at VBR+0x400, same _done/_fail epilogue.
!
! PTEL flag bit layout (core/tlb.vhd lines 120-126):
!   bit7=W  bit6=X  bit5=U  bit4=D  bit3=C
!   page 0 full-access : W|X|U|C = 0xE8
!   page 2 read-only   : X|U|C   = 0x68  (W=0 -> DPROT_W on store)
!   page 4 super-only  : W|X|C   = 0xC8  (U=0 -> DPROT_R on user load)
!
! MMUFSR layout (docs/mmu/hardware-spec.md):
!   [12] VALID  [11:8] KIND  [7:5] rsvd(0)
!   [4] USER  [3] PROT  [2] ITLB  [1] INITIAL(0)  [0] WRITE
!
! Sub-test A: supervisor STORE to page 2 (read-only, W=0) -> DPROT_W, KIND=6
!   expect MMUFSR = 0x1000 | 0x600 | 0x08(PROT) | 0x01(WRITE) = 0x1609
!   USER=0 (supervisor). Also assert EXPEVT == 0x0C0.
! Sub-test B: user-mode LOAD from page 4 (supervisor-only, U=0) -> DPROT_R,
!   KIND=5. expect MMUFSR = 0x1000 | 0x500 | 0x10(USER) | 0x08(PROT) = 0x1518
!   (WRITE=0). Also assert EXPEVT == 0x0C0.
! Also assert MMUFSR reads 0 before any fault occurs (VALID=0, KIND=0).
!
! Result codes:
!   0  all pass
!   1  A: no exception       2  A: MMUFSR != 0x1609    3  A: EXPEVT != 0x0C0
!   4  B: no exception       5  B: MMUFSR != 0x1518     6  B: EXPEVT != 0x0C0
!   7  MMUFSR != 0 before any fault
!
! J4 overlay opcodes:
!   LDC r0,VBR=0x402E  LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E
!   LDC r0,ASIDR=0x407E  LDTLB=0x0038
!   STC EXPEVT,r0=0x0052
!   STC SSR,r1=0x0132  LDC r1,SSR=0x413E  LDC r0,SPC=0x404E

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

        ! ---- VBR = _v_tlb - 0x400 (so VBR+0x400=_v_tlb). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map page 2 (VA 0x2000): read-only, X|U|C = 0x68 (W=0). ----
        mov.l   c_page2_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=2, ASID=0)
        mov.l   p_ptel_ro, r0
        .word   0x406E                  ! LDC r0, PTEL = 0x68
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map page 4 (VA 0x4000): supervisor-only, W|X|C = 0xC8 (U=0). ----
        mov.l   c_page4_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=4, ASID=0)
        mov.l   p_ptel_super, r0
        .word   0x406E                  ! LDC r0, PTEL = 0xC8
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ==============================================================
        ! Assert MMUFSR reads 0 before any fault has occurred. Done here,
        ! BEFORE enabling AT: MMUFSR is P4 MMIO and doesn't depend on AT,
        ! and keeping this check out of the post-AT-enable instruction
        ! stream avoids widening the window between "AT.write" and the
        ! first genuine fault -- once I-fetch translation catches up to a
        ! U=1 page-0 fetch in supervisor mode, SMEP (mmusmep, cpu.vhd/
        ! tlb.vhd: "kernel fetch of user page") legitimately faults, and a
        ! few extra instructions here was enough to cross that window
        ! ahead of sub-test A's intended DPROT_W access.
        ! ==============================================================
        mov.l   p_fsr_addr, r0
        mov.l   @r0, r1
        mov     #0, r2
        cmp/eq  r1, r2
        bt      mmufsr_zero_ok
        mov     #7, r9
        bra     _fail
        nop
mmufsr_zero_ok:

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ==============================================================
        ! Sub-test A: DPROT_W -- supervisor STORE to page 2 (W=0).
        ! ==============================================================
        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_dprot_w, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1609
        mov.l   p_g_bad_fsr, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 2
        mov.l   p_g_bad_expevt, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_after_a, r1
        mov.l   r1, @r0                 ! resume -> after_a

        mov     #1, r9                  ! sentinel: no exception = result 1
        mov     #0x66, r3
        mov.l   c_page2_va, r2
        mov.l   r3, @r2                 ! FAULTS -> _v_tlb (VBR+0x400), DPROT_W

        bra     _fail
        nop

ENTRY(after_a)
        ! ==============================================================
        ! Sub-test B: DPROT_R -- USER-mode LOAD from page 4 (U=0).
        ! ==============================================================
        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_dprot_r, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1518
        mov.l   p_g_bad_fsr, r0
        mov     #5, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 5
        mov.l   p_g_bad_expevt, r0
        mov     #6, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 6
        mov.l   p_g_resume, r0
        mov.l   p_after_b, r1
        mov.l   r1, @r0                 ! resume -> after_b

        ! Re-enable AT: handler disabled MMUCR on entry to sub-test A.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov     #4, r9                  ! sentinel: no exception = result 4
        ! Drop user mode (clear SR.MD, bit 30), as privmode.S does.
        stc     sr, r0
        mov.l   p_mdclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
        mov.l   c_page4_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_tlb (VBR+0x400), DPROT_R (user)

        bra     _fail
        nop

ENTRY(after_b)
        bra     _done
        nop

        ! ============================================================
        ! Pointer literals used by main body.
        ! ============================================================
        .align 2
p_rbclear:          .long 0xDFFFFFFF
p_mdclear:          .long 0xBFFFFFFF   ! clear SR.MD (bit 30)
p_vbr_val:          .long _v_tlb - 0x400
p_ptel_page0:       .long 0x000000E8   ! W|X|U|C, identity page 0
p_ptel_ro:          .long 0x00000068   ! X|U|C  (W=0 -> DPROT_W)
p_ptel_super:       .long 0x000000C8   ! W|X|C  (U=0 -> DPROT_R)
p_mmucr:            .long 0xFF000010
p_fsr_addr:         .long 0xFF000028
p_g_exp_fsr:        .long _g_exp_fsr
p_g_bad_fsr:        .long _g_bad_fsr
p_g_bad_expevt:     .long _g_bad_expevt
p_g_resume:         .long _g_resume
p_after_a:          .long after_a
p_after_b:          .long after_b
c_page2_va:         .long 0x00002000
c_page4_va:         .long 0x00004000
c_page2_pteh:       .long 0x00002000
c_page4_pteh:       .long 0x00004000
c_fsr_dprot_w:       .long 0x00001609
c_fsr_dprot_r:       .long 0x00001518

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
        ! Single handler at exactly VBR+0x400 (all TLB faults land here;
        ! both sub-tests expect EXPEVT=0x0C0, so it's checked against a
        ! fixed constant rather than a per-sub-test global).
        ! ================================================================
        .balign 4
_v_tlb:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0              ! load MMUCR addr
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexpevt_c0, r1
        cmp/eq  r0, r1                  ! T if EXPEVT == 0x0C0
        bf      _h_bad_expevt
        mov.l   Hfsr_addr, r0
        mov.l   @r0, r2                 ! r2 = MMUFSR
        mov.l   Hexp_fsr, r1
        mov.l   @r1, r1                 ! r1 = expected MMUFSR
        cmp/eq  r1, r2
        bf      _h_bad_fsr
        bra     _h_resume
        nop

        .balign 4
Hmmucr:         .long 0xFF000010
Hfsr_addr:      .long 0xFF000028
Hexp_fsr:       .long _g_exp_fsr
Hexpevt_c0:     .long 0x000000C0

_h_resume:
        mov.l   Ph_resume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        ! Force return to supervisor (SSR.MD=1): sub-test B faults in user
        ! mode; without this the RTE resumes in user mode and the next
        ! sub-test's privileged access traps. MD bit = 0x40000000.
        .word   0x0132                  ! STC SSR, r1
        mov.l   Pmd_bit, r2
        or      r2, r1
        .word   0x413E                  ! LDC r1, SSR
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_fsr:
        mov.l   Ph_bad_fsr, r0
        mov.l   @r0, r9                 ! r9 = fail code (MMUFSR mismatch)
        bra     _fail
        nop

_h_bad_expevt:
        mov.l   Ph_bad_expevt, r0
        mov.l   @r0, r9                 ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

        .balign 4
Ph_resume:      .long _g_resume
Ph_bad_fsr:     .long _g_bad_fsr
Ph_bad_expevt:  .long _g_bad_expevt
Pmd_bit:        .long 0x40000000       ! SR.MD bit, set on SSR before RTE

        ! ================================================================
        ! Shared handler globals.
        ! ================================================================
        .balign 4
_g_exp_fsr:     .long 0
_g_resume:      .long 0
_g_bad_fsr:     .long 0
_g_bad_expevt:  .long 0

        ! ================================================================
        ! Fault-page padding: VA 0x1000-0x4FFF.
        ! ================================================================
_fault_pages:
        .space 0x4000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
