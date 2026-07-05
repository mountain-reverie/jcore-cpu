! pagefault_i.S -- PAGE_FAULT_ARCH instruction-fetch page fault.
!
! Flow (mirrors mmuimiss.S's fault->map->retry, but for the base J1 external
! page-fault, no MMU/PRIV):
!   - set VBR so mem[VBR+0] = _pf_handler (base J-core reads the handler address
!     from VBR + U*4, U = d8 = 0, i.e. VBR+0)
!   - jmp into the I-window (0x00010000) -> the testbench asserts page_fault_i
!     (PF_IFETCH) on that fetch -> Page Fault I exception
!   - handler disarms the window (store to 0x00030000) and RTEs -> the faulting
!     fetch is re-issued; now served, the window code runs and writes PASS (0).
!   - if the restart PC is wrong / the fault never fires, the window code never
!     runs, TEST_RESULT stays unwritten, and the run times out (RED).

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
#if CONFIG_PAGE_FAULT_ARCH
        ! Initialise the registers the handler saves/restores (reset leaves them
        ! undefined; the sim flags a U write to the exception stack as a bus error).
        mov     #0, r0
        mov     #0, r1
        mov.l   p_vbr, r0
        ldc     r0, vbr                 ! VBR -> _vbr_table (mem[VBR+0]=_pf_handler)
        mov.l   c_window, r0
        jmp     @r0                     ! fetch 0x00010000 -> PF_IFETCH fault
        nop
        mov     #7, r9                  ! not reached
        bra     _fail
        nop

        .align 2
p_vbr:      .long _vbr_table
c_window:   .long 0x00010000
        .align 2
_vbr_table: .long _pf_handler           ! VBR+0: single page-fault entry point

! Page-fault handler. Saves r0/r1 (SH-2 shares registers with interrupted code),
! disarms the I-window, restores, and RTEs to re-fetch the faulting address.
        .align 2
_pf_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   h_disarm, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! store 0x00030000 -> tb disarms I-window
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop
        .align 2
h_disarm:   .long 0x00030000
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

#if CONFIG_PAGE_FAULT_ARCH
        ! I-window code, linked at VMA 0x00010000 (.window in sh32.x). Reached
        ! only after the page fault is serviced and RTE re-fetches 0x00010000.
        .section .window, "ax"
        .balign 4
_window_entry:
        mov.l   w_test_result, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! 0 -> TEST_RESULT_ADDRESS = PASS
1:      bra     1b
        nop
        .align 2
w_test_result: .long TEST_RESULT_ADDRESS
#endif
