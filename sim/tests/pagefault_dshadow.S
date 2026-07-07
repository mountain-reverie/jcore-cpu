! pagefault_dshadow.S -- PAGE_FAULT_ARCH data-read fault where the instruction
! IMMEDIATELY BEHIND the faulting load overwrites the load's BASE register in the
! fault shadow. This is the case the precise-exception SQUASH exists for: if the
! shadow write commits, the RTE-restart re-reads a corrupted base and loads the
! wrong value. If the base J1 needs no squash (clean pipeline flush) OR the squash
! is enabled, r1 ends == magic.
!
! Flow:
!   - pre-store magic to 0x00050000 (WRITE, not faulted)
!   - r7 = 0x00040000 (a DIFFERENT, non-faulting address holding 0)
!   - r0 = 0x00050000; mov.l @r0,r1 (faults) ; mov r7,r0 (SHADOW: clobbers base)
!   - handler disarms, RTE -> restart re-executes the load with r0.
!   - CORRECT: load re-reads 0x50000 -> r1 = magic -> PASS.
!   - BUGGY (shadow write persisted): load re-reads 0x40000 -> r1 = 0 -> FAIL(#3).

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
        ldc     r0, vbr                 ! VBR -> _vbr_table
        mov.l   c_dwin, r0
        mov.l   c_magic, r2
        mov.l   r2, @r0                 ! pre-store magic (WRITE -> not faulted)
        mov.l   c_other, r7             ! r7 = 0x00040000 (holds 0, non-faulting)
        mov.l   c_dwin, r0              ! r0 = 0x00050000 (load base)
        mov.l   @r0, r1                 ! FAULTS (PF_DREAD)
        mov     r7, r0                  ! SHADOW: clobber the load's base register
        ! after restart the load re-runs; r1 must be magic (base not corrupted)
        mov.l   c_magic, r2
        cmp/eq  r2, r1
        bt      _done                   ! r1 == magic -> PASS
        mov     #3, r9
        bra     _fail
        nop

        .align 2
p_vbr:      .long _vbr_table
c_dwin:     .long 0x00050000
c_other:    .long 0x00040000
c_magic:    .long 0x12345678
        .align 2
_vbr_table: .long _pf_handler

        .align 2
_pf_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   hd_disarm, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! disarm D-window
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
