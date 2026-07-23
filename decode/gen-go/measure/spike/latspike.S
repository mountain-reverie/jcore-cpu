! Latency-measurement SPIKE (Task 1). Proves LED-marker cycle extraction.
! Marker = byte write of a distinct id to PIO 0xABCD0000 -> cosim prints
!   "LED: WRITE 0xNN at <ns> ns"  (timestamped).
! Brackets: cal-A 100 nop / cal-B 200 nop (difference -> ns/cycle, marker
! overhead cancels); indep add (issue); dep add (latency); indep mul.l (issue).
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
        mov.l   led, r14           ! r14 = 0xABCD0000 (PIO marker addr)
        bra     begin
        nop
        .align 2
led:    .long   0xABCD0000
begin:
        ! --- calibration A: 100 nops ---
        mov     #0x11, r0
        mov.b   r0, @r14
        .rept 100
        nop
        .endr
        mov     #0x12, r0
        mov.b   r0, @r14
        ! --- calibration B: 200 nops ---
        mov     #0x13, r0
        mov.b   r0, @r14
        .rept 200
        nop
        .endr
        mov     #0x14, r0
        mov.b   r0, @r14
        ! --- independent add (issue): 96 = 12 * 8-way ---
        mov     #0x21, r0
        mov.b   r0, @r14
        .rept 12
        add     #1, r1
        add     #1, r2
        add     #1, r3
        add     #1, r4
        add     #1, r5
        add     #1, r6
        add     #1, r7
        add     #1, r8
        .endr
        mov     #0x22, r0
        mov.b   r0, @r14
        ! --- dependent add (latency): 100 all r1 ---
        mov     #0x31, r0
        mov.b   r0, @r14
        .rept 100
        add     #1, r1
        .endr
        mov     #0x32, r0
        mov.b   r0, @r14
        ! --- independent mul.l (issue): 100 ---
        mov     #0x41, r0
        mov.b   r0, @r14
        .rept 100
        mul.l   r1, r2
        .endr
        mov     #0x42, r0
        mov.b   r0, @r14
        bra     _done
        nop
        .align 2
_done:
        mov.l   p_res, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail:
        mov.l   p_res, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_res:  .long   TEST_RESULT_ADDRESS
