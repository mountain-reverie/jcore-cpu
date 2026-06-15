! PM1 register-banking test.
!
! Common sequence (runs on both J2 and J4): under MD=1, write 0x11 into R1 with
! SR.RB=0, then 0x22 into R1 with SR.RB=1, then read R1 back with SR.RB=0.
!
!   - J4 (PRIV_ARCH=1): R0-R7 are banked, so the RB=1 write went to bank 1 and
!     the RB=0 read sees the bank-0 value 0x11 (isolation). STC R1_BANK then
!     reads the inactive bank (bank 1) = 0x22.
!   - J2/J1 (PRIV_ARCH=0): no banking, so the RB=1 write aliased the same R1 and
!     the RB=0 read sees 0x22. The test asserts this -- it FAILS if banking ever
!     leaks into a non-PRIV_ARCH build (i.e. if the read returned 0x11).
!
! So the test fails loudly in either direction: banking must work on J4 and must
! be absent on J2/J1. Requires the J4 decoder (make -C decode generate-j4) for
! the STC R*_BANK encoding; that instruction is only executed on the J4 path.
! Runs entirely in supervisor mode (no traps), so only the magic block is needed.
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
        ! RB=0: write 0x11 into R1
        bsr     set_rb0
        nop
        mov     #0x11, r1

        ! RB=1: write 0x22 into R1
        bsr     set_rb1
        nop
        mov     #0x22, r1

        ! RB=0: read R1 back
        bsr     set_rb0
        nop

#if CONFIG_PRIV_ARCH
        ! J4: banked -> R1 (bank 0) == 0x11 (the bank-1 write was invisible)
        mov     #0x11, r3
        cmp/eq  r1, r3
        bf      _fail_loop
        ! STC R1_BANK,R2 reads the INACTIVE bank (bank 1) == 0x22
        ! (-m2 gas has no R*_BANK mnemonic; emit the raw encoding.)
        .word   0x0292          ! STC R1_BANK, R2 = 0000 0010 1001 0010
        mov     #0x22, r3
        cmp/eq  r2, r3
        bf      _fail_loop
        bra     _done
        nop
#else
        ! J2/J1: no banking -> the RB=1 write aliased the same R1, so R1 == 0x22.
        ! If it reads 0x11, banking leaked into a non-PRIV_ARCH build -> fail.
        mov     #0x22, r3
        cmp/eq  r1, r3
        bf      _fail_loop
        bra     _done
        nop
#endif

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
