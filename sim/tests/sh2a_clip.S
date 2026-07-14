! SH-2A saturation instructions: CLIPS.B/CLIPS.W/CLIPU.B/CLIPU.W Rn.
!
! Task 2 (Group 8 PR-A) guard. Exercises the new CLIP_SB/CLIP_SW/CLIP_UB/
! CLIP_UW alumanip_t cases (Task 1, core/components_pkg.vhd) wired through
! the "n"-format spec rows in decode/gen-go/spec/sh2a/arith.toml and the
! sticky CS bit (SR bit 2) set in core/datapath.vhm.
!
! sh2-elf-as (plain -m2) does not know the SH-2A CLIPS/CLIPU or LDC/STC-SR
! opcodes needed here in this exact bit pattern, so everything is
! hand-encoded via .word. Encoding: nnnn = op.code(11:8) (Rn):
!   CLIPU.B Rn    = 0100 nnnn 1000 0001
!   CLIPU.W Rn    = 0100 nnnn 1000 0101
!   CLIPS.B Rn    = 0100 nnnn 1001 0001
!   CLIPS.W Rn    = 0100 nnnn 1001 0101
!   STC  SR,Rn    = 0000 nnnn 0000 0010
!   LDC  Rn,SR    = 0100 nnnn 0000 1110
!
! r1 holds the value under test (clip operand + result); r0 is the STC
! SR destination; r2 is the LDC SR source (used only to force CS to a
! known 0 or 1 before each clip, proving CS is OR'd in, not overwritten).
!
! Marker convention mirrors sim/tests/sh2a_bitreg.S: 0 = pass at
! TEST_RESULT_ADDRESS, non-zero = fail (distinct codes below).

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
        .long _fail1
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
        .global start
start:
        !=====================================================================
        ! CLIPU.B Rn  (0 <= Rn <= 0xFF)
        !=====================================================================

        ! case 1: in-range (0x50) -> unchanged, CS stays 0
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR  (clear SR incl. CS)
        mov     #0x50, r1
        .word   0x4181          ! CLIPU.B r1
        nop
        mov     #0x50, r5
        cmp/eq  r1, r5
        bf      _fail1
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        mov     #0, r5
        cmp/eq  r0, r5
        bf      _fail2

        ! case 2: CS pre-set to 1, in-range clip -> CS stays 1 (sticky)
        mov     #4, r2
        .word   0x420E          ! LDC r2,SR  (CS=1)
        mov     #0x50, r1
        .word   0x4181          ! CLIPU.B r1
        nop
        mov     #0x50, r5
        cmp/eq  r1, r5
        bf      _fail3
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail4

        ! case 3: over-high -> Rn == 0xFF, CS == 1
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR (clear CS)
        mov.l   p_0x1FF, r1
        .word   0x4181          ! CLIPU.B r1
        nop
        mov.l   p_0xFF, r5
        cmp/eq  r1, r5
        bf      _fail5
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail6

        !=====================================================================
        ! CLIPU.W Rn  (0 <= Rn <= 0xFFFF)
        !=====================================================================

        ! case 4: in-range (0x1234) -> unchanged, CS stays 0
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR
        mov.l   p_0x1234, r1
        .word   0x4185          ! CLIPU.W r1
        nop
        mov.l   p_0x1234, r5
        cmp/eq  r1, r5
        bf      _fail7
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        mov     #0, r5
        cmp/eq  r0, r5
        bf      _fail8

        ! case 5: CS pre-set to 1, in-range clip -> CS stays 1
        mov     #4, r2
        .word   0x420E          ! LDC r2,SR (CS=1)
        mov.l   p_0x1234, r1
        .word   0x4185          ! CLIPU.W r1
        nop
        mov.l   p_0x1234, r5
        cmp/eq  r1, r5
        bf      _fail9
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail10

        ! case 6: over-high -> Rn == 0xFFFF, CS == 1
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR (clear CS)
        mov.l   p_0x10000, r1
        .word   0x4185          ! CLIPU.W r1
        nop
        mov.l   p_0xFFFF, r5
        cmp/eq  r1, r5
        bf      _fail11
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail12

        !=====================================================================
        ! CLIPS.B Rn  (-0x80 <= Rn <= 0x7F)
        !=====================================================================

        ! case 7: in-range (0x50) -> unchanged, CS stays 0
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR
        mov     #0x50, r1
        .word   0x4191          ! CLIPS.B r1
        nop
        mov     #0x50, r5
        cmp/eq  r1, r5
        bf      _fail13
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        mov     #0, r5
        cmp/eq  r0, r5
        bf      _fail14

        ! case 8: CS pre-set to 1, in-range clip -> CS stays 1
        mov     #4, r2
        .word   0x420E          ! LDC r2,SR (CS=1)
        mov     #0x50, r1
        .word   0x4191          ! CLIPS.B r1
        nop
        mov     #0x50, r5
        cmp/eq  r1, r5
        bf      _fail15
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail16

        ! case 9: over-high (200) -> Rn == 0x7F, CS == 1
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR (clear CS)
        mov.l   p_200, r1
        .word   0x4191          ! CLIPS.B r1
        nop
        mov     #0x7F, r5
        cmp/eq  r1, r5
        bf      _fail17
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail18

        ! case 10: under-low (-200) -> Rn == 0xFFFFFF80, CS == 1
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR (clear CS)
        mov.l   p_neg200, r1
        .word   0x4191          ! CLIPS.B r1
        nop
        mov.l   p_neg128, r5
        cmp/eq  r1, r5
        bf      _fail19
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail20

        !=====================================================================
        ! CLIPS.W Rn  (-0x8000 <= Rn <= 0x7FFF)
        !=====================================================================

        ! case 11: in-range (0x1234) -> unchanged, CS stays 0
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR
        mov.l   p_0x1234, r1
        .word   0x4195          ! CLIPS.W r1
        nop
        mov.l   p_0x1234, r5
        cmp/eq  r1, r5
        bf      _fail21
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        mov     #0, r5
        cmp/eq  r0, r5
        bf      _fail22

        ! case 12: CS pre-set to 1, in-range clip -> CS stays 1
        mov     #4, r2
        .word   0x420E          ! LDC r2,SR (CS=1)
        mov.l   p_0x1234, r1
        .word   0x4195          ! CLIPS.W r1
        nop
        mov.l   p_0x1234, r5
        cmp/eq  r1, r5
        bf      _fail23
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail24

        ! case 13: over-high (40000) -> Rn == 0x00007FFF, CS == 1
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR (clear CS)
        mov.l   p_40000, r1
        .word   0x4195          ! CLIPS.W r1
        nop
        mov.l   p_0x7FFF, r5
        cmp/eq  r1, r5
        bf      _fail25
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail26

        ! case 14: under-low (-40000) -> Rn == 0xFFFF8000, CS == 1
        mov     #0, r2
        .word   0x420E          ! LDC r2,SR (clear CS)
        mov.l   p_neg40000, r1
        .word   0x4195          ! CLIPS.W r1
        nop
        mov.l   p_neg32768, r5
        cmp/eq  r1, r5
        bf      _fail27
        .word   0x0002          ! STC SR,r0
        mov     #4, r5
        and     r5, r0
        cmp/eq  r0, r5
        bf      _fail28

        bra     _done
        nop

        .align 2
p_0x1FF:     .long 0x000001FF
p_0xFF:      .long 0x000000FF
p_0x1234:    .long 0x00001234
p_0x10000:   .long 0x00010000
p_0xFFFF:    .long 0x0000FFFF
p_200:       .long 200
p_neg200:    .long -200
p_neg128:    .long 0xFFFFFF80
p_40000:     .long 40000
p_0x7FFF:    .long 0x00007FFF
p_neg40000:  .long -40000
p_neg32768:  .long 0xFFFF8000

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail1:
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #2, r9
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #3, r9
        mov.l   r9, @r0
        bra     _fail3
        nop
_fail4:
        mov.l   p_test_result, r0
        mov     #4, r9
        mov.l   r9, @r0
        bra     _fail4
        nop
_fail5:
        mov.l   p_test_result, r0
        mov     #5, r9
        mov.l   r9, @r0
        bra     _fail5
        nop
_fail6:
        mov.l   p_test_result, r0
        mov     #6, r9
        mov.l   r9, @r0
        bra     _fail6
        nop
_fail7:
        mov.l   p_test_result, r0
        mov     #7, r9
        mov.l   r9, @r0
        bra     _fail7
        nop
_fail8:
        mov.l   p_test_result, r0
        mov     #8, r9
        mov.l   r9, @r0
        bra     _fail8
        nop
_fail9:
        mov.l   p_test_result, r0
        mov     #9, r9
        mov.l   r9, @r0
        bra     _fail9
        nop
_fail10:
        mov.l   p_test_result, r0
        mov     #10, r9
        mov.l   r9, @r0
        bra     _fail10
        nop
_fail11:
        mov.l   p_test_result, r0
        mov     #11, r9
        mov.l   r9, @r0
        bra     _fail11
        nop
_fail12:
        mov.l   p_test_result, r0
        mov     #12, r9
        mov.l   r9, @r0
        bra     _fail12
        nop
_fail13:
        mov.l   p_test_result, r0
        mov     #13, r9
        mov.l   r9, @r0
        bra     _fail13
        nop
_fail14:
        mov.l   p_test_result, r0
        mov     #14, r9
        mov.l   r9, @r0
        bra     _fail14
        nop
_fail15:
        mov.l   p_test_result, r0
        mov     #15, r9
        mov.l   r9, @r0
        bra     _fail15
        nop
_fail16:
        mov.l   p_test_result, r0
        mov     #16, r9
        mov.l   r9, @r0
        bra     _fail16
        nop
_fail17:
        mov.l   p_test_result, r0
        mov     #17, r9
        mov.l   r9, @r0
        bra     _fail17
        nop
_fail18:
        mov.l   p_test_result, r0
        mov     #18, r9
        mov.l   r9, @r0
        bra     _fail18
        nop
_fail19:
        mov.l   p_test_result, r0
        mov     #19, r9
        mov.l   r9, @r0
        bra     _fail19
        nop
_fail20:
        mov.l   p_test_result, r0
        mov     #20, r9
        mov.l   r9, @r0
        bra     _fail20
        nop
_fail21:
        mov.l   p_test_result, r0
        mov     #21, r9
        mov.l   r9, @r0
        bra     _fail21
        nop
_fail22:
        mov.l   p_test_result, r0
        mov     #22, r9
        mov.l   r9, @r0
        bra     _fail22
        nop
_fail23:
        mov.l   p_test_result, r0
        mov     #23, r9
        mov.l   r9, @r0
        bra     _fail23
        nop
_fail24:
        mov.l   p_test_result, r0
        mov     #24, r9
        mov.l   r9, @r0
        bra     _fail24
        nop
_fail25:
        mov.l   p_test_result, r0
        mov     #25, r9
        mov.l   r9, @r0
        bra     _fail25
        nop
_fail26:
        mov.l   p_test_result, r0
        mov     #26, r9
        mov.l   r9, @r0
        bra     _fail26
        nop
_fail27:
        mov.l   p_test_result, r0
        mov     #27, r9
        mov.l   r9, @r0
        bra     _fail27
        nop
_fail28:
        mov.l   p_test_result, r0
        mov     #28, r9
        mov.l   r9, @r0
        bra     _fail28
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
