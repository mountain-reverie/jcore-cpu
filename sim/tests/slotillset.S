! slotillset.S -- the ISA-mandated slot-illegal instruction SET (J4/PRIV).
!
! check_illegal_delay_slot() is derived in decode/gen-go/internal/model/build.go
! by walking each instruction's microcode for wrpc_z ("writes PC"). That rule
! catches the unconditional branches, RTE and TRAPA, but SILENTLY MISSES
! two groups the SH ISA also requires to raise a slot illegal instruction
! exception (Renesas SH Instruction Set Summary, "Possible Exceptions" --
! a field docs/insns.json does not carry):
!
!   - the CONDITIONAL branches BT/BF/BT_S/BF_S, which redirect via
!     zbus="T(PC)" + if_addy="ZBUS" instead of wrpc_z; and
!   - the PC-relative operand fetches MOVA and MOV.{W,L} @(disp,PC),Rn, which
!     never write PC at all but read a PC that is indeterminate in a delay slot.
!
! ---- The two groups have DIFFERENT variant scope ----
! The conditional branches are slot-illegal on SH-1/SH-2 as well, so they carry
! `slot_illegal = true` in the BASE spec (decode/gen-go/spec/branch.toml) and
! trap on every variant.
!
! The PC-relative fetches are slot-illegal on SH-3/SH-4 ONLY -- the Renesas note
! is scoped "SH4*: If this instruction is executed in a delay slot, a slot
! illegal instruction exception will be generated". On SH-1/SH-2 they are LEGAL
! with defined semantics, and J-core's own test ROM depends on it:
! testrom/tests/testmov2.s:27 runs `bra` with `mova` in the delay slot, so
! trapping it on J2 hangs the ROM (measured: regression.sh Step 3 stops after 5
! of 20 LED writes). They therefore carry the flag as a J4-only ATTRIBUTE PATCH
! in decode/gen-go/spec/sh4/mov.toml.
!
! Because THIS guard runs only on the J4/PRIV build, it asserts that all seven
! trap. The opposite J2 assertion is held by testmov2.s via regression.sh
! Step 3.
!
! Base-J2 cpu_ctb does not fire illegal-instruction exceptions at all (a
! pre-existing testbench limitation, see j4_illegal_trap.S), so this MUST run
! under the J4/PRIV decoder built by sim/mmu_sim.sh.
!
! ---- Method ----
! Each victim opcode is placed in the delay slot of a `bra`. The victims are
! emitted as `.word` because gas correctly REFUSES to assemble a branch into a
! delay slot -- which is also why every encoding below is re-derived from its
! table rather than trusted:
!
!   bra   label            1010 dddd dddd dddd -> 0xA000 (disp=0)
!   bt    label            1000 1001 dddd dddd -> 0x8900
!   bf    label            1000 1011 dddd dddd -> 0x8B00
!   bt/s  label            1000 1101 dddd dddd -> 0x8D00
!   bf/s  label            1000 1111 dddd dddd -> 0x8F00
!   mova  @(disp,PC),R0    1100 0111 dddd dddd -> 0xC700
!   mov.w @(disp,PC),Rn    1001 nnnn dddd dddd -> 0x9000 (n=0)
!   mov.l @(disp,PC),Rn    1101 nnnn dddd dddd -> 0xD000 (n=0)
!
! J4 overlay opcodes used here (verified against
! decode/gen-go/spec/sh4/exceptions.toml):
!   STC EXPEVT,r0 = 0x0052   (0000 nnnn 0101 0010)
!   LDC r0,SPC    = 0x404E   (0100 mmmm 0100 1110)
!   LDC r0,VBR    = 0x402E
!
! Non-trapping execution of every victim is deliberately made HARMLESS, so a
! regression shows up as a clean "did not trap" result code and not as a
! runaway: T is preset so BT/BT_S and BF/BF_S fall through rather than branch,
! and the PC-relative loads use disp=0 (reading our own code) into r0.
!
! The handler checks EXPEVT == 0x1A0 (Slot Illegal), NOT merely "an exception
! happened" -- a General Illegal (0x180) reaching the same VBR+0x100 vector
! would otherwise pass vacuously.
!
! ---- Controls (guard against a vacuous pass) ----
!   Case 0: `bra` in a delay slot -- ALREADY trapped before this change. If it
!           reports "did not trap", the harness itself is broken, not the fix.
!   Case 8: `nop` in a delay slot -- legal, and must NOT trap. Catches an
!           over-broad check_illegal_delay_slot that traps everything.
!
! ---- Result codes ----
!    0  all pass
!    1  case 0: bra    in delay slot did not trap   (CONTROL: harness broken)
!    2  case 1: bt     in delay slot did not trap
!    3  case 2: bf     in delay slot did not trap
!    4  case 3: bt/s   in delay slot did not trap
!    5  case 4: bf/s   in delay slot did not trap
!    6  case 5: mova   in delay slot did not trap  (J4 only; J2 must NOT trap)
!    7  case 6: mov.w @(disp,PC) in delay slot did not trap   (J4 only)
!    8  case 7: mov.l @(disp,PC) in delay slot did not trap   (J4 only)
!    9  case 8: nop    in delay slot WRONGLY trapped (over-broad check)
!   10..17  case 0..7 trapped with EXPEVT != 0x1A0 (wrong exception kind)
!
! ---- _fail integrity net ----
! Same as mmufault.S: _fail clamps r9==0 to 0x7F, because sim/cpu_ctb.c's
! test_result() reads any 4-byte write of 0 as PASS -- so a fault reaching
! _fail before any sub-test ran must not silently report success.
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
        .long _fail
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_slot - 0x100, so VBR+0x100 = _v_slot. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Pin handler globals in callee regs the handler never clobbers.
        ! The handler touches only r0/r1 (and r9 on the fail paths), so r8/r11
        ! stay live across every exception. ----
        mov.l   p_g_resume, r8          ! r8  = &_g_resume
        mov.l   p_g_bad_expevt, r11     ! r11 = &_g_bad_expevt

        ! ---- Expected EXPEVT is 0x1A0 (Slot Illegal) for every trapping case.
        mov.l   p_g_exp_expevt, r0
        mov.l   p_expevt_slotill, r1
        mov.l   r1, @r0

        ! ================================================================
        ! Case 0 (CONTROL): bra in a delay slot. Trapped before this change
        ! too -- proves the harness, vector and handler are live.
        ! ================================================================
        mov.l   pr_0, r0
        mov.l   r0, @r8                 ! _g_resume = _r0
        mov     #10, r0
        mov.l   r0, @r11                ! EXPEVT-mismatch code for this case
        bra     _n0
        .word   0xA000                  ! <-- delay slot: bra (disp=0)
_n0:    mov     #1, r9                  ! fell through => no exception raised
        bra     _fail
        nop
        .balign 4
pr_0:   .long   _r0
_r0:

        ! ================================================================
        ! Case 1: bt in a delay slot. T=0 so a non-trapping bt falls through.
        ! ================================================================
        mov.l   pr_1, r0
        mov.l   r0, @r8
        mov     #11, r0
        mov.l   r0, @r11
        clrt                            ! T=0 => bt not taken if it wrongly runs
        bra     _n1
        .word   0x8900                  ! <-- delay slot: bt (disp=0)
_n1:    mov     #2, r9
        bra     _fail
        nop
        .balign 4
pr_1:   .long   _r1
_r1:

        ! ================================================================
        ! Case 2: bf in a delay slot. T=1 so a non-trapping bf falls through.
        ! ================================================================
        mov.l   pr_2, r0
        mov.l   r0, @r8
        mov     #12, r0
        mov.l   r0, @r11
        sett                            ! T=1 => bf not taken if it wrongly runs
        bra     _n2
        .word   0x8B00                  ! <-- delay slot: bf (disp=0)
_n2:    mov     #3, r9
        bra     _fail
        nop
        .balign 4
pr_2:   .long   _r2
_r2:

        ! ================================================================
        ! Case 3: bt/s in a delay slot. T=0 so it falls through if it runs.
        ! ================================================================
        mov.l   pr_3, r0
        mov.l   r0, @r8
        mov     #13, r0
        mov.l   r0, @r11
        clrt
        bra     _n3
        .word   0x8D00                  ! <-- delay slot: bt/s (disp=0)
_n3:    mov     #4, r9
        bra     _fail
        nop
        .balign 4
pr_3:   .long   _r3
_r3:

        ! ================================================================
        ! Case 4: bf/s in a delay slot. T=1 so it falls through if it runs.
        ! ================================================================
        mov.l   pr_4, r0
        mov.l   r0, @r8
        mov     #14, r0
        mov.l   r0, @r11
        sett
        bra     _n4
        .word   0x8F00                  ! <-- delay slot: bf/s (disp=0)
_n4:    mov     #5, r9
        bra     _fail
        nop
        .balign 4
pr_4:   .long   _r4
_r4:

        ! ================================================================
        ! Case 5: mova @(0,PC),r0 in a delay slot (J4-only rule).
        ! ================================================================
        mov.l   pr_5, r0
        mov.l   r0, @r8
        mov     #15, r0
        mov.l   r0, @r11
        bra     _n5
        .word   0xC700                  ! <-- delay slot: mova @(0,PC),r0
_n5:    mov     #6, r9
        bra     _fail
        nop
        .balign 4
pr_5:   .long   _r5
_r5:

        ! ================================================================
        ! Case 6: mov.w @(0,PC),r0 in a delay slot (J4-only rule).
        ! ================================================================
        mov.l   pr_6, r0
        mov.l   r0, @r8
        mov     #16, r0
        mov.l   r0, @r11
        bra     _n6
        .word   0x9000                  ! <-- delay slot: mov.w @(0,PC),r0
_n6:    mov     #7, r9
        bra     _fail
        nop
        .balign 4
pr_6:   .long   _r6
_r6:

        ! ================================================================
        ! Case 7: mov.l @(0,PC),r0 in a delay slot (J4-only rule).
        ! ================================================================
        mov.l   pr_7, r0
        mov.l   r0, @r8
        mov     #17, r0
        mov.l   r0, @r11
        bra     _n7
        .word   0xD000                  ! <-- delay slot: mov.l @(0,PC),r0
_n7:    mov     #8, r9
        bra     _fail
        nop
        .balign 4
pr_7:   .long   _r7
_r7:

        ! ================================================================
        ! Case 8 (NEGATIVE CONTROL): nop in a delay slot is LEGAL and must
        ! NOT trap. _g_resume points at the fail path, so entering the
        ! handler at all reports 9 rather than falling through to _done.
        ! ================================================================
        mov.l   pr_8, r0
        mov.l   r0, @r8                 ! _g_resume = _r8_bad
        mov     #9, r0
        mov.l   r0, @r11
        bra     _n8
        nop                             ! <-- delay slot: legal, must not trap
_r8_bad:
        mov     #9, r9                  ! only reachable via the handler
        bra     _fail
        nop
        .balign 4
pr_8:   .long   _r8_bad
_n8:

        bra     _done
        nop

        .balign 4
p_rbclear:          .long 0xDFFFFFFF
p_vbr_val:          .long _v_slot - 0x100
p_g_resume:         .long _g_resume
p_g_bad_expevt:     .long _g_bad_expevt
p_g_exp_expevt:     .long _g_exp_expevt
p_expevt_slotill:   .long 0x1A0

#endif  ! CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ================================================================
        ! Slot Illegal / General Illegal vector, placed at VBR + 0x100.
        !
        ! Confirms the exception KIND via EXPEVT before resuming: 0x1A0 is
        ! Slot Illegal, 0x180 is General Illegal. Both land here, so without
        ! this check a General Illegal would let the guard pass vacuously.
        ! ================================================================
        .balign 4
_v_slot:
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   He_exp, r1
        mov.l   @r1, r1                 ! r1 = expected EXPEVT (0x1A0)
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   He_resume, r0
        mov.l   @r0, r0                 ! r0 = per-case resume label
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

        .balign 4
He_exp:         .long _g_exp_expevt
He_resume:      .long _g_resume

_h_bad_expevt:
        mov.l   He_bad, r0              ! pool must sit AFTER the load: mov.l
        mov.l   @r0, r9                 ! @(disp,PC) has no negative displacement
        bra     _fail
        nop
        .balign 4
He_bad:         .long _g_bad_expevt

        ! ================================================================
        ! Handler globals. Loud sentinels so a fault arriving before any
        ! sub-test has run still names its cause rather than reporting 0.
        ! ================================================================
        .balign 4
_g_exp_expevt:  .long 0xFFFFFFFF        ! set to 0x1A0 by start
_g_resume:      .long 0
_g_bad_expevt:  .long 0x5A

#endif  ! CONFIG_PRIV_ARCH
