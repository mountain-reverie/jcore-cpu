! pagefault_dinc.S -- PAGE_FAULT_ARCH data-read page fault on a POST-INCREMENT
! load (mov.l @Rm+,Rn). The reliability case that needs the @Rm+ base-restore:
! the faulting load must restart AND leave Rm incremented exactly once.
!
! Flow:
!   - pre-store magic (0x12345678) to 0x00050000 (a WRITE, not faulted)
!   - r0 = 0x00050000; mov.l @r0+,r1 -> the tb faults the READ (PF_DREAD).
!     Without base-restore r0 would double-increment (0x50008) after RTE.
!   - handler disarms the D-window (store to 0x00060000), preserving r0/r1, RTEs
!   - the faulting load re-executes: r1 = magic AND r0 = 0x00050004 (single inc)
!   - PASS iff r1==magic AND r0==0x00050004.

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
        mov     #0, r1
        mov.l   p_vbr, r0
        ldc     r0, vbr                 ! VBR -> _vbr_table (mem[VBR+0]=_pf_handler)
        mov.l   c_dwin, r0              ! r0 = 0x00050000 (D-window)
        mov.l   c_magic, r2
        mov.l   r2, @r0                 ! pre-store magic (WRITE -> not faulted)
        mov.l   c_dwin, r0              ! reload r0 = 0x00050000
        mov.l   @r0+, r1                ! READ 0x50000 -> PF_DREAD; restart must
                                        ! leave r1=magic and r0=0x50004 (one inc)
        mov.l   c_dend, r3             ! r3 = expected post-increment 0x00050004
        cmp/eq  r3, r0
        bf      _fail_r0                ! r0 wrong (double-inc?) -> FAIL
        mov.l   c_magic, r2
        cmp/eq  r2, r1
        bt      _done                   ! r1 == magic -> PASS
        mov     #9, r9
        bra     _fail
        nop
_fail_r0:
        mov     #7, r9
        bra     _fail
        nop

        .align 2
p_vbr:      .long _vbr_table
c_dwin:     .long 0x00050000
c_dend:     .long 0x00050004
c_magic:    .long 0x12345678
        .align 2
_vbr_table: .long _pf_handler

! Handler: preserve r0 (the load's base) and r1, disarm the D-window, RTE.
        .align 2
_pf_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   hd_disarm, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! store 0x00060000 -> tb disarms D-window
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop
        .align 2
hd_disarm:  .long 0x00060000
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
