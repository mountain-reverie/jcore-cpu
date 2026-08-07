! shldshadguard: empirical base-J2 check of SHLD/SHAD (dynamic shift)
! semantics. These two instructions are declared in the BASE spec
! (decode/gen-go/spec/system.toml, no variant overlay gating) and
! decode/decode_body.vhd generates them unconditionally -- but the pinned
! CI assembler (binutils-gdb @ cf1e4755, opcodes/sh-opc.h) explicitly
! restricts shld/shad to J4 ("J2 lacks shld/shad"), which breaks
! testrom/tests/testshift.s under -m2. This guard measures, on the plain
! base-J2 cpu_ctb (CPU_VARIANT=j2, the sim/Makefile default -- NOT the J4/MMU
! overlay build), whether the base decoder's SHLD/SHAD hardware actually
! computes the documented (docs/insns.json) results.
!
! Encodings verified against the task's worked example: SHAD r3,r2 = 0100
! 0010 0011 1100 = 0x423C i.e. word = 0x4000 | (n<<8) | (m<<4) | {C,D}
! where "SHLD/SHAD Rm,Rn" -> nnnn=Rn (dest, shifted operand), mmmm=Rm (count).
! Throughout this guard n=1 (r1=Rn, the value being shifted) and m=2
! (r2=Rm, the signed shift count), so:
!   SHLD r2,r1 = .word 0x412D
!   SHAD r2,r1 = .word 0x412C
!
! Semantics under test (docs/insns.json pseudocode):
!   SHLD: if Rm>=0: Rn <<= (Rm&0x1F)
!         elif (Rm&0x1F)==0: Rn = 0
!         else: Rn = (unsigned)Rn >> ((~Rm&0x1F)+1)
!   SHAD: same, but the right shift is ARITHMETIC (sign-extends), and the
!         (Rm&0x1F)==0 / Rm<0 edge case yields 0 or 0xFFFFFFFF depending on
!         Rn's sign -- this is the case a naive barrel shifter is most
!         likely to get wrong (shift-by-32 is undefined in a plain shifter).
!
! Non-vacuity: this guard was confirmed to go RED by mutating an expected
! constant (see task-6-report.md) and reverted before commit.
!
! This is deliberately a BASE-variant (CPU_VARIANT=j2) guard and is run via
! decode/gen-go/regression.sh's sim-tests step, NOT via sim/mmu_sim.sh --
! mmu_sim.sh builds the J4/MMU overlay, under which this guard does not
! apply and is intentionally absent from its guard list.

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
        ! ---- Case 1: SHLD positive shift.  Rn=1, Rm=4 -> Rn = 1<<4 = 0x10
        mov.l   c1_rn, r1
        mov.l   c1_rm, r2
        .word 0x412D                   ! shld r2,r1
        mov.l   c1_exp, r3
        cmp/eq  r3, r1
        bf      case1_fail
        bra     case2
        nop
case1_fail:
        mov     #1, r9
        bra     _fail_loop
        nop

case2:
        ! ---- Case 2: SHLD negative shift.  Rn=0x80000000, Rm=-4
        ! -> unsigned Rn >> ((~(-4)&0x1F)+1) = Rn >> 4 = 0x08000000
        mov.l   c2_rn, r1
        mov.l   c2_rm, r2
        .word 0x412D                   ! shld r2,r1
        mov.l   c2_exp, r3
        cmp/eq  r3, r1
        bf      case2_fail
        bra     case3
        nop
case2_fail:
        mov     #2, r9
        bra     _fail_loop
        nop

case3:
        ! ---- Case 3: SHLD zero-shift edge, Rm=-32 (Rm&0x1F==0, Rm<0).
        ! Rn=0xFFFFFFFF (negative) -> SHLD result must be 0 regardless of
        ! Rn's sign (unlike SHAD).
        mov.l   c3_rn, r1
        mov.l   c3_rm, r2
        .word 0x412D                   ! shld r2,r1
        mov.l   c3_exp, r3
        cmp/eq  r3, r1
        bf      case3_fail
        bra     case4
        nop
case3_fail:
        mov     #3, r9
        bra     _fail_loop
        nop

case4:
        ! ---- Case 4: SHAD positive shift.  Rn=1, Rm=4 -> Rn = 1<<4 = 0x10
        mov.l   c4_rn, r1
        mov.l   c4_rm, r2
        .word 0x412C                   ! shad r2,r1
        mov.l   c4_exp, r3
        cmp/eq  r3, r1
        bf      case4_fail
        bra     case5
        nop
case4_fail:
        mov     #4, r9
        bra     _fail_loop
        nop

case5:
        ! ---- Case 5: SHAD negative shift, arithmetic (sign-extending).
        ! Rn=0x80000000, Rm=-4 -> Rn >>a 4, sign-extended = 0xF8000000
        mov.l   c5_rn, r1
        mov.l   c5_rm, r2
        .word 0x412C                   ! shad r2,r1
        mov.l   c5_exp, r3
        cmp/eq  r3, r1
        bf      case5_fail
        bra     case6
        nop
case5_fail:
        mov     #5, r9
        bra     _fail_loop
        nop

case6:
        ! ---- Case 6: SHAD zero-shift edge, Rn negative (0x80000000),
        ! Rm=-32 (Rm&0x1F==0, Rm<0) -> result must be 0xFFFFFFFF (all 1s,
        ! sign-extension of the "infinite" arithmetic shift), NOT 0.
        mov.l   c6_rn, r1
        mov.l   c6_rm, r2
        .word 0x412C                   ! shad r2,r1
        mov.l   c6_exp, r3
        cmp/eq  r3, r1
        bf      case6_fail
        bra     case7
        nop
case6_fail:
        mov     #6, r9
        bra     _fail_loop
        nop

case7:
        ! ---- Case 7: SHAD zero-shift edge, Rn positive (0x7FFFFFFF),
        ! Rm=-32 -> result must be 0x00000000.
        mov.l   c7_rn, r1
        mov.l   c7_rm, r2
        .word 0x412C                   ! shad r2,r1
        mov.l   c7_exp, r3
        cmp/eq  r3, r1
        bf      case7_fail
        bra     _done
        nop
case7_fail:
        mov     #7, r9
        bra     _fail_loop
        nop

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail_loop)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail_loop
        nop

        .align 2
p_test_result:       .long TEST_RESULT_ADDRESS
p_test_result_pass:  .long TEST_PASS_MAGIC

c1_rn: .long 0x00000001
c1_rm: .long 4
c1_exp: .long 0x00000010

c2_rn: .long 0x80000000
c2_rm: .long -4
c2_exp: .long 0x08000000

c3_rn: .long 0xFFFFFFFF
c3_rm: .long -32
c3_exp: .long 0x00000000

c4_rn: .long 0x00000001
c4_rm: .long 4
c4_exp: .long 0x00000010

c5_rn: .long 0x80000000
c5_rm: .long -4
c5_exp: .long 0xF8000000

c6_rn: .long 0x80000000
c6_rm: .long -32
c6_exp: .long 0xFFFFFFFF

c7_rn: .long 0x7FFFFFFF
c7_rm: .long -32
c7_exp: .long 0x00000000
