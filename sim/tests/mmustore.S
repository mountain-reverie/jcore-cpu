! mmustore.S -- minimal RED guard for the store-side TLB-miss protection hole.
!
! Proven defect (.superpowers/sdd): a D-side STORE that misses the TLB raises
! NO exception -- the store silently completes to the bus, bypassing
! W^X/CoW/dirty-bit/page-fault-on-write. The IDENTICAL access as a LOAD faults
! correctly (covered by mmurte.S). This test isolates the STORE case.
!
! Flow:
!   - map page 0 identity (W|X|U|C), enable AT
!   - STORE to VA 0x1000 (page 1, unmapped) -> must raise DMISS_W (EXPEVT 0x080),
!     vector VBR+0x440
!   - handler (the ONLY pass path): disable AT, write "Test Passed", spin
!   - if the store silently completes (the defect): main path spins WITHOUT
!     writing any result -> run times out -> RED.
!
! VBR = _v_store - 0x440 so the DMISS_W vector (VBR+0x440) hits _v_store.

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

        ! ---- VBR = _v_store - 0x440 (so VBR+0x440 = _v_store). ----
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

        ! ---- Take a DMISS_W: STORE to VA 0x1000 (page 1, unmapped). ----
        mov.l   c_page1_va, r2
        mov     #0x55, r3
        mov.l   r3, @r2                 ! FAULTS -> _v_store (VBR+0x440), DMISS_W

        ! If the store silently completes (the defect), we reach here. Spin
        ! WITHOUT writing any result so RED = run times out (no "Test Passed").
_silent_spin:
        bra     _silent_spin
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_store - 0x440
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C8
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
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- DMISS_W handler at VBR+0x440 ----
        ! Pad so _v_store lands at >= 0x440.
        .balign 4
        .space 0x640, 0
        .balign 4
_v_store:                               ! = VBR + 0x440
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        ! The store faulted as required: write PASS (result 0) directly. AT is
        ! now off so this P-region store is reliable. This is the ONLY path that
        ! writes a result -> reaching it == GREEN.
        mov.l   Hresult, r0
        mov     #0, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hresult:        .long TEST_RESULT_ADDRESS

        ! ---- Fault-page padding: VA 0x1000. ----
_fault_pages:
        .space 0x2000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
