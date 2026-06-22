! mmufault.S -- TLB miss exception injection test (J4+MMU_ARCH).
!
! Verifies a D-side TLB miss raises DMISS_R (EXPEVT=0x060), captures
! TEA=faulting VA, and vectors to VBR+0x420.
!
! Addressing model in cpu_tb: the C memory model maps the image to a single
! low range and rejects out-of-range accesses with a bus error (which would
! mask the TLB exception). cpu_tb has no cache, so the CPU drives the virtual
! address straight onto the bus -- the TLB only produces hit/miss/prot for
! exception generation, it does not retranslate the bus address. The linker
! places .text at origin 0x0 (.vect then code), so the whole image (~0x1b0
! bytes of code) lives in page 0 [0x0000-0x0FFF]. Therefore:
!   * page 0 (VA 0x0000-0x0FFF) is identity-mapped so every instruction fetch
!     and PC-relative literal load hits once AT is enabled;
!   * the image is padded into page 1 so VA 0x1000 is *in range* for the bus
!     model yet *unmapped* in the TLB -- a clean D-miss, no bus error.
!
! TLB exceptions vector by access type: I-fetch->VBR+0x400, load->VBR+0x420,
! store->VBR+0x440 (EXPEVT disambiguates miss vs protection). This test drives
! a data-load miss (DMISS_R, EXPEVT=0x060) -> VBR+0x420. We set
! VBR = dmiss_r_handler - 0x420 so the entry's VBR+0x420 lands on the handler.
!
! result 0 = pass; nonzero = failure:
!   1  exception never fired (ran past the faulting load)
!   2  EXPEVT != 0x060
!   3  TEA != 0x1000
!
! Overlay opcodes (.word them):
!   LDC r0,PTEH   = 0x405E   LDC r0,PTEL  = 0x406E   LDC r0,ASIDR = 0x407E
!   LDTLB         = 0x0038   STC EXPEVT,r0 = 0x0052

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
        ! Set VBR so VBR+0x420 == dmiss_r_handler (DMISS_R vector offset).
        mov.l   p_vbr_dmiss, r0
        .word   0x402E                  ! LDC r0, VBR

        ! Identity-map page 0 (VA 0x0000-0x0FFF -> PA identity), where all code
        ! and the handler live, perms w+x+u+c = 0xE8, ASID=0.
        ! PTEH = VPN<<12 | ASID = 0. PTEL = PPN | flags = 0x000000E8.
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH   (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! Enable AT: MMUCR.AT = 1 (P4 MMIO 0xFF000010).
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! Load from VA 0x1000 (page 1): in range via padding, unmapped in TLB.
        mov.l   p_unmapped_va, r2
        mov.l   @r2, r3                 ! FAULTS here -> dmiss_r_handler

        ! Reaching here means no exception fired.
        mov     #1, r9
        bra     _fail
        nop

        .align 2
p_vbr_dmiss:   .long dmiss_r_handler - 0x420
p_ptel_page0:  .long 0x000000E8
p_mmucr:       .long 0xFF000010
p_unmapped_va: .long 0x00001000

ENTRY(dmiss_r_handler)
        ! Disable AT so handler bookkeeping is unambiguous.
        mov.l   h_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! EXPEVT == 0x060 ?
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   h_expevt, r1
        cmp/eq  r0, r1
        bf      h_bad_expevt

        ! TEA == 0x1000 ?  (P4 MMIO 0xFF00000C)
        mov.l   h_tea_addr, r0
        mov.l   @r0, r2
        mov.l   h_fault_va, r1
        cmp/eq  r1, r2
        bf      h_bad_tea

        mov.l   h_result, r0
        mov     #0, r1
        mov.l   r1, @r0
h_pass: bra     h_pass
        nop
h_bad_expevt:
        mov.l   h_result, r0
        mov     #2, r1
        mov.l   r1, @r0
h_be:   bra     h_be
        nop
h_bad_tea:
        mov.l   h_result, r0
        mov     #3, r1
        mov.l   r1, @r0
h_bt:   bra     h_bt
        nop

        .align 2
h_mmucr:    .long 0xFF000010
h_tea_addr: .long 0xFF00000C
h_expevt:   .long 0x00000060
h_fault_va: .long 0x00001000
h_result:   .long TEST_RESULT_ADDRESS
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
        ! Extend the image into page 1 so VA 0x1000 is in range for the bus
        ! model (page 1 is never installed in the TLB -> the load D-misses).
        ! Use .space (not .balign, which would raise the whole .text section's
        ! alignment to 0x1000 and push the code itself into page 1). The load
        ! reads this zero-fill on the bus while the TLB miss raises the
        ! exception in parallel.
_fault_page:
        .space 0x1000, 0
#endif
