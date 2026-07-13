! J4-build end-to-end illegal-instruction TRAP test.
!
! Validates Phase 0 of the generator "excluded-overlay-opcodes -> General
! Illegal" feature (commit e148125) end-to-end on a real J4/PRIV cosim run
! (base-J2 cpu_ctb does not fire illegal-instruction exceptions at all -- a
! pre-existing testbench limitation -- so this MUST run under the J4/PRIV
! decoder built by sim/mmu_sim.sh, i.e. `make -C decode generate-j4` +
! CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1).
!
! Two faulting single-word opcodes are exercised, in order, each requiring the
! supervisor exception handler to be reached (sentinel set) before continuing:
!   1. 0xFFFF     - built-in illegal opcode (control case; guards against a
!                    vacuous test / broken handler wiring).
!   2. 0x3211     - SH-2A disp12 word1 ("mov.b @(disp12,Rm),R0"-family first
!                    word). This opcode is part of the sh2a overlay and is
!                    NOT part of the base/J4 instruction set, so Phase 0's
!                    cross-overlay injection must route it to General Illegal
!                    on the J4 build. This is the real assertion.
!
! Both faulting opcodes execute outside any branch delay slot. The handler
! bumps SPC by 2 (each faulting opcode here is a single 16-bit word) and RTEs.
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
        .long _fail_loop
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0
        .text
ENTRY(start)
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
        mov.l   p_vbr_fixed, r0        ! VBR = handler - 0x100
        ldc     r0, vbr

        ! --- Case 1: 0xFFFF (built-in illegal; control) ---
        mov.l   p_sentinel, r1
        mov     #0, r2
        mov.l   r2, @r1                ! sentinel = 0
        .word   0xFFFF                 ! <-- faulting opcode 1
        mov.l   p_sentinel, r1
        mov.l   @r1, r2
        mov     #1, r5
        cmp/eq  r5, r2
        bf      _fail_loop

        ! --- Case 2: 0x3211 (sh2a disp12 word1; excluded from J4) ---
        mov.l   p_sentinel, r1
        mov     #0, r2
        mov.l   r2, @r1                ! sentinel = 0 (reset)
        .word   0x3211                 ! <-- faulting opcode 2
        mov.l   p_sentinel, r1
        mov.l   @r1, r2
        mov     #1, r5
        cmp/eq  r5, r2
        bf      _fail_loop

        bra     _done
        nop
ENTRY(exception_handler)
        .word   0x0042                 ! STC SPC, R0
        add     #2, r0                 ! skip the 1-word faulting opcode (bump SPC by 2)
        .word   0x404E                 ! LDC R0, SPC
        mov.l   p_sentinel, r1
        mov     #1, r2
        mov.l   r2, @r1                ! sentinel = 1 (handler reached = trapped)
        rte
        nop
ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail_loop)
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail_loop
        nop
        .align 2
p_vbr_fixed:   .long exception_handler - 0x100
p_rbclear:     .long 0xDFFFFFFF
p_sentinel:    .long 0x00007800
p_test_result: .long TEST_RESULT_ADDRESS
