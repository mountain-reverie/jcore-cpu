! SH-2A TBR round-trip: ldc r1,TBR (0x414A) then stc TBR,r2 (0x024A); r2==r1.
!
! TBR is a named register at extended-register-file index 23 ("10111"),
! SH2A_ARCH-gated (rf_depth=24). ldc/stc TBR mirror ldc/stc GBR exactly.
!
! sh2-elf-as (plain -m2) does not know the SH-2A TBR mnemonic, so both
! instructions are hand-encoded via .word.
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
        .word   0x414A           ! ldc r1, TBR   (0100 0001 0100 1010)
        .word   0x024A           ! stc TBR, r2   (0000 0010 0100 1010)
        mov.l   p_val, r3
        cmp/eq  r2, r3
        bf      _fail
        bra     _done
        nop
        .align 2
p_val:  .long   0xABCD1234
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
