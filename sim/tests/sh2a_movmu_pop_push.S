! SH-2A MOVMU.L pop(n>0) -> push regression: exercises the stale-movml_idx_r
! hazard on the mupush PR-entry slot.
!
! A pop-family MOVMU.L @R15+,Rn (n>0) leaves the g_movml sequencer's
! movml_idx_r register = n. If a later MOVMU.L Rm,@-R15 (mupush) PR-entry
! slot falls through to that stale index instead of seeding 0, movml_hold
! stays '1' and op.addr is held forever on the PR store -> registers never
! stored, R15 wrong.
!
! This test drives a FULL round-trip (push+pop) FIRST -- whose pop leaves
! movml_idx_r=4 stale -- then a SECOND round-trip with fresh sentinels, and
! verifies the SECOND round-trip's registers/PR/R15. Without the fix the
! second push hangs / corrupts and the checks fail.
!
! Opcodes hand-encoded (sh2-elf-as -m2 does not know SH-2A MOVMU.L):
!   MOVMU.L Rm,@-R15 : 0100 mmmm 1111 0000   (push PR, then Rm..R0)
!   MOVMU.L @R15+,Rn : 0100 nnnn 1111 0100   (pop R0..Rn, then PR)
! Marker convention: 0 = pass, non-zero = fail.

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
        ! ---- round 1: push+pop with n=4 (leaves movml_idx_r=4 stale) ----
        mov.l   q_s0, r0
        mov.l   q_s1, r1
        mov.l   q_s2, r2
        mov.l   q_s3, r3
        mov.l   q_s4, r4
        mov.l   q_spr, r6
        lds     r6, pr
        nop
        .word   0x44F0        ! movmu.l r4,@-r15  (push PR,R4..R0)
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        nop
        .word   0x44F4        ! movmu.l @r15+,r4  (pop R0..R4,PR) -> idx_r=4
        nop

        ! ---- round 2: fresh sentinels, push+pop, then verify ----
        mov.l   p_s0, r0
        mov.l   p_s1, r1
        mov.l   p_s2, r2
        mov.l   p_s3, r3
        mov.l   p_s4, r4
        mov.l   p_spr, r6
        lds     r6, pr
        nop
        .word   0x44F0        ! movmu.l r4,@-r15  (push PR,R4..R0) -- mupush after stale pop
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        mov     #0, r6
        lds     r6, pr
        nop
        .word   0x44F4        ! movmu.l @r15+,r4  (pop R0..R4,PR)
        nop

        mov.l   p_s0, r7
        cmp/eq  r0, r7
        bf      _fail0
        mov.l   p_s1, r7
        cmp/eq  r1, r7
        bf      _fail1
        mov.l   p_s2, r7
        cmp/eq  r2, r7
        bf      _fail2
        mov.l   p_s3, r7
        cmp/eq  r3, r7
        bf      _fail3
        mov.l   p_s4, r7
        cmp/eq  r4, r7
        bf      _fail4

        sts     pr, r7
        mov.l   p_spr, r6
        cmp/eq  r6, r7
        bf      _fail5

        mov.l   p_sp0, r7
        cmp/eq  r15, r7
        bf      _fail6

        bra     _done
        nop

        .align 2
q_s0:  .long 0x11110000
q_s1:  .long 0x22221111
q_s2:  .long 0x33332222
q_s3:  .long 0x44443333
q_s4:  .long 0x55554444
q_spr: .long 0x66665555
p_s0:  .long 0xA0A0A000
p_s1:  .long 0xB1B1B111
p_s2:  .long 0xC2C2C222
p_s3:  .long 0xD3D3D333
p_s4:  .long 0xE4E4E444
p_spr: .long 0xF5F5F555
p_sp0: .long 0x00007000

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop

_fail0: mov.l p_test_result, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail0
        nop
_fail1: mov.l p_test_result, r0
        mov #2, r9
        mov.l r9, @r0
        bra _fail1
        nop
_fail2: mov.l p_test_result, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail2
        nop
_fail3: mov.l p_test_result, r0
        mov #4, r9
        mov.l r9, @r0
        bra _fail3
        nop
_fail4: mov.l p_test_result, r0
        mov #5, r9
        mov.l r9, @r0
        bra _fail4
        nop
_fail5: mov.l p_test_result, r0
        mov #6, r9
        mov.l r9, @r0
        bra _fail5
        nop
_fail6: mov.l p_test_result, r0
        mov #7, r9
        mov.l r9, @r0
        bra _fail6
        nop
_fail:  mov.l p_test_result, r0
        mov #8, r9
        mov.l r9, @r0
        bra _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
