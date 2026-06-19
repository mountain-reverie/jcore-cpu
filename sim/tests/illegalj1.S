! J1 illegal-instruction trap test (standalone image; run on the J1 sim).
!
! On the J1 variant the j-core SMP / coprocessor instructions are dropped from
! the decoder and must trap as illegal. This test executes two dropped opcodes
! and verifies each one traps:
!   .word 0x2983 = CAS.L r8,r9,@r0     (j-core SMP atomic, dropped on J1)
!   .word 0x4088 = LDS Rm,CP0_COM      (coprocessor op, dropped on J1)
! Each trap bumps a counter; the test passes only if BOTH trapped (counter==2).
!
! IMPORTANT: this test only PASSES on the J1 decoder (decode/j1). On J2/J4 the
! two opcodes are valid instructions, so they execute instead of trapping and
! the test fails by design. Run it on the J1 sim, e.g.:
!   make -C sim cpu_ctb DECODE_DIR=decode/j1 CPU_TB_CONFIG=work.cpu_j1
!   ./sim/cpu_ctb -i sim/tests/illegalj1.img --stop-time=200us
!
! Structure mirrors trapatest.S: standalone vector table, SIM_INSTR result
! protocol, VBR -> _myvbr (every vector points at the handler). No GDB stub.

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
        ! VBR -> _myvbr: every vector slot points at illegal_handler, so a trap
        ! to general-illegal (vec 4) or slot-illegal (vec 6) reaches the handler.
        mov.l   p_myvbr, r0
        ldc     r0, vbr
        ! counter = 0
        mov.l   p_counter, r1
        mov     #0, r2
        mov.l   r2, @r1

        .word   0x2983              ! CAS.L  - dropped on J1 -> must trap
        .word   0x4088              ! LDS CP0_COM - dropped on J1 -> must trap

        ! both traps must have fired
        mov.l   p_counter, r1
        mov.l   @r1, r2
        mov     #2, r5
        cmp/eq  r5, r2
        bf      _fail_loop
        bra     _done
        nop

ENTRY(illegal_handler)
        ! SH-2 stack frame: @r15 = faulting PC. Bump the counter, advance the
        ! saved PC past the 2-byte illegal opcode, then RTE.
        mov.l   p_counter_h, r1
        mov.l   @r1, r2
        add     #1, r2
        mov.l   r2, @r1
        mov.l   @r15, r0
        add     #2, r0
        mov.l   r0, @r15
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
p_myvbr:       .long _myvbr
p_counter:     .long 0x00007800
p_counter_h:   .long 0x00007800
p_test_result: .long TEST_RESULT_ADDRESS

        .align 2
ENTRY(_myvbr)
        .rept 64
        .long illegal_handler
        .endr
