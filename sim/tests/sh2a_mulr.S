! SH-2A MULR R0,Rn: 32x32->32 signed multiply, MACH:MACL preserved.
!
! Task 2 (Group 8 PR-B) guard. Exercises the 5-slot mulr row in
! decode/gen-go/spec/sh2a/multiply.toml, which borrows the MAC datapath
! for the multiply itself but must leave the architectural MACH:MACL
! pair completely untouched -- via the MAC_SAVE/MAC_RESTORE_L/
! MAC_RESTORE_H shadow-register mechanism (core/datapath.vhm,
! core/components_pkg.vhd, Task 1).
!
! Uses the native SH-2A mulr mnemonic (requires -Wa,--isa=sh2a). Encoding:
! nnnn = op.code(11:8) (Rn), R0 is the fixed second operand:
!   MULR R0,Rn = 0100 nnnn 1000 0000
!
! Marker convention mirrors sim/tests/sh2a_bitreg.S: 0 = pass at
! TEST_RESULT_ADDRESS, non-zero = fail (distinct codes below).

#include "sim_instr.h"

.section .vect
        .long   start           ! 0: power-on PC
        .long   0x00007000      ! 1: power-on SP (inside RAM)
        .long   start           ! 2: manual reset PC
        .long   0x00007000      ! 3: manual reset SP
        .rept   60
        .long   0
        .endr
        .long   SIM_INSTR_MAGIC
        .long   _sim_instr_end
        .long   _done
        .long   _fail1
        .long   CMD_ENABLE_TEST_RESULT
_sim_instr_end:
        .long   0

.text
.global start
start:

! =====================================================================
! case 1: basic correctness -- R0=3, R2=5 -> mulr R0,R2 -> R2==15
! =====================================================================
        mov     #3, r0
        mov     #5, r2
        mulr    r0, r2
        mov     #15, r5
        cmp/eq  r2, r5
        bf      _fail1

! =====================================================================
! case 2: low-32 overflow -- R0=0x10000, R1=0x10000 -> R1==0x00000000
! =====================================================================
        mov.l   p_0x10000, r0
        mov.l   p_0x10000, r1
        mulr    r0, r1
        mov     #0, r5
        cmp/eq  r1, r5
        bf      _fail2

! =====================================================================
! case 3: Rn == R0 -- mulr R0,R0 -> R0 == R0^2 (low 32)
! =====================================================================
        mov     #3, r0
        mulr    r0, r0
        mov     #9, r5
        cmp/eq  r0, r5
        bf      _fail3

! =====================================================================
! case 4: Rn == R15 -- proves the shadow approach handles the stack
! register (a stack-based save/restore route could not touch R15).
! Save the real stack pointer first, restore it afterward.
! =====================================================================
        mov     r15, r8         ! save real SP
        mov     #6, r0
        mov     #7, r15
        mulr    r0, r15
        mov     #42, r5
        cmp/eq  r15, r5
        bf      _fail4
        mov     r8, r15         ! restore real SP

! =====================================================================
! case 5: MAC preservation -- seed MACH/MACL to known values, run
! mulr, verify both registers are unchanged AND the mulr result is
! correct.
! =====================================================================
        mov.l   p_0xAAAAAAAA, r0
        lds     r0, mach
        mov.l   p_0x55555555, r0
        lds     r0, macl
        mov     #4, r0
        mov     #6, r3
        mulr    r0, r3
        mov     #24, r5
        cmp/eq  r3, r5
        bf      _fail5
        sts     mach, r6
        sts     macl, r7
        mov.l   p_0xAAAAAAAA, r5
        cmp/eq  r6, r5
        bf      _fail6
        mov.l   p_0x55555555, r5
        cmp/eq  r7, r5
        bf      _fail7

! =====================================================================
! case 6: in-flight MAC survival -- a mac.l accumulation interleaved
! with mulr must produce the same final MACH:MACL as a reference run
! with no mulr in the middle.
! =====================================================================
! --- reference run: zero-MAC (lds); 3x mac.l @r2+,@r1+ with no mulr ---
        mov     #0, r0
        ldc     r0, sr          ! S=0 (no saturation)
        lds     r0, mach        ! clrmac replacement (cosim: clrmac self-XORs uninit TEMP1 -> U)
        lds     r0, macl        ! r0 == 0 here (mov #0,r0 above)
        mov.l   p_macdata1, r1
        mov.l   p_macdata2, r2
        mac.l   @r2+, @r1+
        mac.l   @r2+, @r1+
        mac.l   @r2+, @r1+
        sts     mach, r6        ! reference MACH
        sts     macl, r7        ! reference MACL

! --- interleaved run: same 3 mac.l ops, with mulr between iterations 1/2
!     and 2/3 (using registers unrelated to the accumulation) ---
        mov     #0, r0
        ldc     r0, sr          ! S=0
        lds     r0, mach        ! clrmac replacement (cosim: clrmac self-XORs uninit TEMP1 -> U)
        lds     r0, macl        ! r0 == 0 here (mov #0,r0 above)
        mov.l   p_macdata1, r1
        mov.l   p_macdata2, r2
        mac.l   @r2+, @r1+
        mov     #3, r0
        mov     #5, r4
        mulr    r0, r4          ! (in-flight, between iter 1/2)
        mac.l   @r2+, @r1+
        mov     #9, r0
        mov     #9, r4
        mulr    r0, r4          ! (in-flight, between iter 2/3)
        mac.l   @r2+, @r1+
        sts     mach, r8        ! interleaved-run MACH
        sts     macl, r9        ! interleaved-run MACL

        cmp/eq  r6, r8
        bf      _fail8
        cmp/eq  r7, r9
        bf      _fail9

        bra     _done
        nop

        .align 2
p_0x10000:      .long 0x00010000
p_0xAAAAAAAA:   .long 0xAAAAAAAA
p_0x55555555:   .long 0x55555555
p_macdata1:      .long _macval1
p_macdata2:      .long _macval2

        .align 2
! Small signed operand arrays for the mac.l accumulation (2 elements is
! enough to prove interleaving survives across at least one full MAC
! pipeline latency; 3rd op picked to also touch the third mulr slot).
_macval1:
        .long   2
        .long   3
        .long   5
_macval2:
        .long   7
        .long   11
        .long   13

.global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0         ! 0 = pass
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
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
