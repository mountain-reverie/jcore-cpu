! MMU negative-guard test. Two-directional, in the spirit of excguard.S:
! the SAME code asserts OPPOSITE outcomes per build, so it fails if the MMU
! privilege trap is absent on J4+MMU OR if a MMU opcode executes on J2/non-MMU.
!
! Test A — MD=0 privilege trap (J4 + CONFIG_MMU_ARCH=1):
!   Drop to user mode (clear SR.MD); execute STC PTEH,R1 (.word 0x0153).
!   Must NOT execute but instead vector to VBR+0x100 (General-Illegal handler)
!   with EXPEVT=0x180. Handler reads EXPEVT via STC EXPEVT,R0 (.word 0x0052)
!   and confirms the correct code, then commits PASS.
!   Fall-through without trapping = FAIL (result 5).
!   Wrong EXPEVT value = FAIL (result 2).
!
! Test B — J2-illegal guard (CONFIG_MMU_ARCH=0 / J2):
!   LDC R0,PTEH (.word 0x405E) is not in the J2 base decoder.
!   On J2/non-MMU it must trap as Illegal Instruction via the SH-2 indirect
!   vector table. Landing in the handler is PASS; fall-through is FAIL.
!
! Opcodes (assembler does not know these J4-overlay forms, so .word them):
!   STC PTEH,R1  = 0000 0001 0101 0011 = 0x0153
!   LDC R0,PTEH  = 0100 0000 0101 1110 = 0x405E
!   STC EXPEVT,R0= 0000 0000 0101 0010 = 0x0052
!
! result 0 = pass; 2 = EXPEVT wrong; 5 = MMU instr did not trap.

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
#if CONFIG_MMU_ARCH
        ! J4+MMU path (Test A): set RB=0, set VBR so VBR+0x100 == handler,
        ! drop to user mode, execute privileged STC PTEH,R1.
        stc     sr, r3
        mov.l   p_rbclear, r4
        and     r4, r3
        ldc     r3, sr
        nop
        nop
        nop

        mov.l   p_vbr_fixed, r0       ! VBR+0x100 == exception_handler
        ldc     r0, vbr               ! privileged while MD=1 -> OK

        ! drop to user mode
        stc     sr, r1
        mov.l   p_mdmask, r2
        and     r2, r1
        ldc     r1, sr
        nop
        nop
        nop
        nop

        ! user mode: execute privileged MMU instruction STC PTEH,R1
        .word   0x0153                ! STC PTEH,R1 -- must NOT execute, must trap
        ! fall-through = instruction did NOT trap -> fail
        mov     #5, r9
        bra     _fail
        nop

ENTRY(exception_handler)
        ! General-Illegal handler: verify EXPEVT == 0x180
        .word   0x0052                ! STC EXPEVT, R0
        mov.l   p_expevt, r3
        cmp/eq  r3, r0
        mov     #2, r9                ! code 2 = EXPEVT wrong
        bf      _fail
        bra     _done
        nop

        .align 2
p_vbr_fixed:   .long exception_handler - 0x100
p_rbclear:     .long 0xDFFFFFFF
p_mdmask:      .long 0xBFFFFFFF
p_expevt:      .long 0x00000180

#else
        ! J2/non-MMU path (Test B): set up SH-2 indirect VBR so any exception
        ! lands in exception_handler; execute LDC R0,PTEH (.word 0x405E).
        ! On J2 this opcode is not in the decoder -> Illegal Instruction trap.
        mov.l   p_myvbr, r0
        ldc     r0, vbr

        .word   0x405E                ! LDC R0,PTEH -- must trap on J2
        ! fall-through = opcode executed normally on J2 -> fail
        mov     #5, r9
        bra     _fail
        nop

ENTRY(exception_handler)
        ! Landing here means J2 correctly trapped the unknown opcode -> pass.
        bra     _done
        nop

        .align 2
p_myvbr:   .long _myvbr
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

#if !CONFIG_MMU_ARCH
        ! SH-2 indirect vector table: every entry points to exception_handler.
        .align 2
ENTRY(_myvbr)
        .rept 64
        .long exception_handler
        .endr
#endif
