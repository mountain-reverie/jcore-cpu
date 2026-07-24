! SH-2A TBR round-trip: ldc r1,TBR (0x414A) then stc TBR,r2 (0x024A); r2==r1.
!
! TBR is a named register at extended-register-file index 23 ("10111"),
! SH2A_ARCH-gated (rf_depth=24). ldc/stc TBR mirror ldc/stc GBR exactly.
!
! Uses the native SH-2A TBR / jsr/n mnemonics (requires -Wa,--isa=sh2a).
!   LDC Rm, TBR = 0100 mmmm 0100 1010  ->  ldc r1, TBR = 0x414A
!   STC TBR, Rn = 0000 nnnn 0100 1010  ->  stc TBR, r2 = 0x024A

#include "sim_instr.h"
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
        .global start
start:
        mov.l   p_val, r1        ! r1 = 0xABCD1234
        ldc     r1, tbr           ! (0100 0001 0100 1010)
        stc     tbr, r2           ! (0000 0010 0100 1010)
        mov.l   p_val, r3
        cmp/eq  r2, r3
        bf      _fail

        ! jsr/n @@(disp8,TBR): memory-indirect table-jump, no delay slot.
        ! Build an in-memory jump table at tbl_addr, load TBR with its
        ! address, then jsr/n @@(0,TBR) should call sub1 via mem[TBR+0];
        ! PR must hold call+2 so the following rts returns here.
        mov.l   tbl_addr, r4     ! r4 = &jumptbl (in RAM)
        mov.l   sub1_addr, r5    ! r5 = &sub1
        mov.l   r5, @r4          ! jumptbl[0] = &sub1
        ldc     r4, tbr           ! (0100 0100 0100 1010)
        mov     #0x55, r6        ! r6 = 0x55 (cleared by sub1 if reached)
        jsr/n   @@(0,tbr)         ! -> PC = mem[TBR+0] = sub1
        ! (no delay slot) execution returns here via sub1's rts
        mov     r6, r0
        cmp/eq  #0, r0           ! sub1 set r6 = 0 ?
        bf      _fail

        bra     _done
        nop
        .align 2
p_val:  .long   0xABCD1234
tbl_addr: .long 0x00008000       ! jumptbl location in RAM
sub1_addr: .long sub1
sub1:
        mov     #0, r6           ! marker: reached
        rts
        nop
        .align 2
_done:  mov.l   p_res, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail:  mov.l   p_res, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_res:  .long   TEST_RESULT_ADDRESS
