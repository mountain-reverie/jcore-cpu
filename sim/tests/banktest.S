! PM1 register-banking test (J4 only).
!
! In privileged mode (MD=1 at reset), R0-R7 select bank 0 when SR.RB=0 and
! bank 1 when SR.RB=1. STC Rm_BANK,Rn reads the *inactive* bank. This test
! writes distinct values to R1 under each bank, confirms the bank-0 value
! survives a bank-1 write (isolation), and confirms STC R1_BANK reads the
! inactive bank.
!
! Requires the DUT built with PRIV_ARCH=true (CONFIG_PRIV_ARCH=1) AND the J4
! decoder (make -C decode generate-j4). On a J2 build there is no banking, so
! the test skips straight to success. Runs entirely in supervisor mode, so no
! exception/VBR scaffolding is needed -- only the simulator magic block.
!
! SR.RB is bit 29. LDC SR has pipeline latency, so NOPs follow each RB change.

#include "sim_instr.h"

        .section .vect
        .long start            ! 0: power-on PC
        .long 0x00007000       ! 1: power-on SP (inside RAM)
        .long start            ! 2: manual reset PC
        .long 0x00007000       ! 3: manual reset SP
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
        .global start
start:
#if CONFIG_PRIV_ARCH
        ! RB=0: write 0x11 into R1 (bank 0)
        bsr     set_rb0
        nop
        mov     #0x11, r1

        ! RB=1: write 0x22 into R1 (bank 1)
        bsr     set_rb1
        nop
        mov     #0x22, r1

        ! still RB=1: R1 must read back 0x22 (bank 1 active)
        mov     #0x22, r3
        cmp/eq  r1, r3
        bf      _fail_loop

        ! RB=0: R1 must read back 0x11 (the bank-1 write was invisible) -> isolation
        bsr     set_rb0
        nop
        mov     #0x11, r3
        cmp/eq  r1, r3
        bf      _fail_loop

        ! RB=0: STC R1_BANK,R2 reads the INACTIVE bank (bank 1) = 0x22.
        ! (-m2 gas has no R*_BANK mnemonic; emit the raw encoding.)
        .word   0x0292          ! STC R1_BANK, R2 = 0000 0010 1001 0010
        mov     #0x22, r3
        cmp/eq  r2, r3
        bf      _fail_loop
        bra     _done
        nop

set_rb0:
        stc     sr, r0
        mov.l   rb_clear, r4    ! 0xDFFFFFFF
        and     r4, r0
        ldc     r0, sr
        nop
        nop
        nop
        rts
        nop
set_rb1:
        stc     sr, r0
        mov.l   rb_set, r4      ! 0x20000000
        or      r4, r0
        ldc     r0, sr
        nop
        nop
        nop
        rts
        nop
        .align 2
rb_set:   .long 0x20000000
rb_clear: .long 0xDFFFFFFF
#else
        ! J2/J1: no banking -> nothing to test, pass by skipping.
        bra     _done
        nop
#endif

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail_loop:
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0        ! non-zero = fail
        bra     _fail_loop
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
