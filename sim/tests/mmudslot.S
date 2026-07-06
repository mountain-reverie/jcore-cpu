! mmudslot.S -- DMISS in a branch delay slot must restart at the BRANCH,
! not the delay-slot instruction (J4 + MMU_ARCH).
!
! Repro for the handover finding "MMU data-access fault in a branch delay slot
! restarts the delay slot, not the branch"
! (docs/superpowers/handover-mmu-delay-slot-data-fault.md).
!
! Scenario:
!   mov.l  c_page1_va, r2      ! r2 = 0x1000 (page 1, NOT in TLB)
!   bra    taken_target        ! branch executes
!   mov.l  @r2, r3             ! DELAY SLOT: load DMISSes (page 1 unmapped)
!
! The DMISS_R handler installs a full-access mapping for page 1 and RTEs to the
! hardware-saved SPC WITHOUT overriding it (a realistic page-fault handler).
! The re-executed load now succeeds; where control lands afterwards is the test:
!
!   CORRECT: SPC = branch PC  -> branch re-issues its delay slot -> taken_target -> PASS (0)
!   BUGGY  : SPC = delay-slot PC -> load re-executes, then falls THROUGH the
!            (already-executed) branch -> fall-through path -> FAIL (2)
!
! VBR layout: VBR = _v_load - 0x420 so VBR+0x420 = _v_load (D-load handler).
!
! Result codes:
!   0  PASS  (branch taken after fault serviced)
!   1  no exception fired (page 1 was reachable without faulting -- setup bug)
!   2  FAIL  (fell through the branch -- the handover bug)
!
! J4 overlay opcodes:
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E

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

        ! ---- VBR = _v_load - 0x420 (so VBR+0x420 = _v_load). ----
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

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ==============================================================
        ! The faulting delay slot.
        ! ==============================================================
        mov     #1, r9                  ! sentinel: no-exception = result 1
        mov     #0x5A, r3               ! sentinel: delay-slot load must overwrite this with 0
        mov.l   c_page1_va, r2          ! r2 = 0x1000 (page 1, unmapped)
        bra     taken_target
        mov.l   @r2, r3                 ! DELAY SLOT: DMISS_R -> _v_load (loads 0 from page 1)

        ! Fall-through path (BUGGY landing): branch was skipped.
        mov     #2, r9
        bra     _fail
        nop

ENTRY(taken_target)
        ! CORRECT landing: branch was taken after the fault was serviced.
        ! Also verify the delay-slot LOAD actually executed: r3 must be 0 (loaded
        ! from zero-filled page 1), not the 0x5A sentinel. If r3==0x5A the delay
        ! slot was SKIPPED on the restart -> result 3.
        mov     #0x5A, r0
        cmp/eq  r0, r3
        bt      _dslot_skipped
        mov     #0, r9
        bra     _done
        nop
_dslot_skipped:
        mov     #3, r9
        bra     _fail
        nop

        ! ============================================================
        ! Literals.
        ! ============================================================
        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x420
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000E8        ! W|X|U|C
c_page1_va:     .long 0x00001000

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
p_test_result:  .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ================================================================
        ! DMISS_R / DPROT_R handler at VBR+0x420 = _v_load.
        ! Installs a full-access mapping for page 1 and RTEs to the
        ! hardware-saved SPC (NO manual SPC override).
        ! ================================================================
        .balign 4
_v_load:                                ! = VBR + 0x420
        mov.l   Hpteh1, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=1, ASID=0)
        mov.l   Hptel1, r0
        .word   0x406E                  ! LDC r0, PTEL  = 0xE8 (full access)
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        rte                             ! PC <- SPC (hardware value)
        nop

        .balign 4
Hpteh1:         .long 0x00001000        ! VPN = 1
Hptel1:         .long 0x000010E8        ! PA 0x1000 (identity) | W|X|U|C

        ! ================================================================
        ! Fault-page padding: VA 0x1000-0x1FFF (page 1, zero-filled so the
        ! bus does not fault before the TLB exception fires).
        ! ================================================================
        .balign 4
_fault_pages:
        .space 0x1000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
