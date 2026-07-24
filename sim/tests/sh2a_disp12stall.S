! SH-2A two-word MOV.L @(disp12,Rm),Rn load whose slot1 is STALLED by a
! reg_conf RAW interlock on the base register (Rm).
!
! Task 1 fix-2 (feat/j2a-group1-disp12): g_ext_word in decode/decode_core.vhm
! sources ext_word_o COMBINATIONALLY from if_dr, on the premise that if_dr
! always holds the extension word (word2) throughout the disp12 op's slot1
! (the imm_from_ext cycle). This test attacks that premise: it makes the
! disp12 load's slot1 STALL for extra cycles via a load-use RAW hazard on
! the base register, so if if_dr were to advance mid-slot1 during the stall,
! the combinational ext_word would change and the computed disp/address
! would be corrupted. A non-zero disp (0x100 -> byte offset 0x400) makes any
! ext_word corruption produce a clearly wrong address (and a mismatch).
!
! Assembled with native SH-2A mnemonics (-Wa,--isa=sh2a): the two-word
! MOV.L @(disp12,Rm),Rn form is emitted directly (gas disp = disp12 field x4,
! so a disp12 field of 0x100 is written as @(0x400,Rn)).
!
! Three interlock shapes, each preceding the disp12 load so the base reg is
! produced by a slow (memory-load) instruction right before its use:
!   case 1: base produced by a pc-relative mov.l 0 instructions before the
!           disp12 load (tight load-use interlock).
!   case 2: base produced 1 instruction before (one filler between).
!   case 3: base produced by an @Rn+ post-increment load immediately before.
! In all cases the disp12 load must read the CORRECT address (disp intact).
!
! Marker convention mirrors sh2a_disp12s.S: 0 = pass, non-zero = fail code.

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
        .long 0
_sim_instr_end: .long 0

        .text
        .global start
start:
        ! Pre-store the three seed values at @(0x100, base) for each scratch
        ! region. disp12 = 0x100 -> byte offset 0x100*4 = 0x400.
        ! store word1 n=2(Rn=r2 base) m=1(Rm=r1 data) = 0x3211, word2=0x2100.

        ! --- seed region 1 ---
        mov.l   p_seed1, r1
        mov.l   p_scratch1, r2
        nop
        mov.l   r1,@(0x400,r2)
        nop
        nop

        ! --- seed region 2 ---
        mov.l   p_seed2, r1
        mov.l   p_scratch2, r2
        nop
        mov.l   r1,@(0x400,r2)
        nop
        nop

        ! --- seed region 3 ---
        mov.l   p_seed3, r1
        mov.l   p_scratch3, r2
        nop
        mov.l   r1,@(0x400,r2)
        nop
        nop

        ! ================= case 1: tight load-use interlock =================
        ! Produce base r4 with a pc-relative load, then IMMEDIATELY use r4 as
        ! the disp12 load base (no filler) -> the disp12 load's slot1 stalls
        ! waiting on r4 (reg_conf RAW).
        ! disp12 load word1 n=5(Rn=r5 dest) m=4(Rm=r4 base)
        !   = 0011 0101 0100 0001 = 0x3541, word2 = 0x6100.
        mov.l   p_scratch1, r4          ! r4 = base (slow: memory load)
        mov.l   @(0x400,r4),r5
        nop
        nop
        mov.l   p_seed1, r0
        cmp/eq  r0, r5
        bf      _fail1

        ! ================= case 2: one filler between ======================
        ! base r4 produced, one nop, then disp12 load. Still an interlock
        ! window (the load's slot1 lands while r4 is being written back).
        mov.l   p_scratch2, r4
        nop
        mov.l   @(0x400,r4),r5
        nop
        nop
        mov.l   p_seed2, r0
        cmp/eq  r0, r5
        bf      _fail2

        ! ================= case 3: post-increment load producer ============
        ! base r4 produced by a mov.l @r6+,r4 (post-inc load, multi-cycle)
        ! immediately before the disp12 load.
        mov.l   p_pscratch3, r6         ! r6 -> memory word holding scratch3
        nop
        nop
        mov.l   @r6+, r4                ! r4 = scratch3 (post-inc load)
        mov.l   @(0x400,r4),r5
        nop
        nop
        mov.l   p_seed3, r0
        cmp/eq  r0, r5
        bf      _fail3

        bra     _done
        nop

        .align 4
p_seed1:     .long 0xA5A5A5A5
p_seed2:     .long 0x5A5A5A5A
p_seed3:     .long 0xC3C3C3C3
p_scratch1:  .long scratch1
p_scratch2:  .long scratch2
p_scratch3:  .long scratch3
p_pscratch3: .long p_scratch3_ind
p_scratch3_ind: .long scratch3

        .global _done
_done:
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop
_fail1:
        mov.l   p_test_result, r0
        mov     #1, r9         ! 1 = case 1 (tight interlock) address/disp corrupted
        mov.l   r9, @r0
        bra     _fail1
        nop
_fail2:
        mov.l   p_test_result, r0
        mov     #2, r9         ! 2 = case 2 (one filler) address/disp corrupted
        mov.l   r9, @r0
        bra     _fail2
        nop
_fail3:
        mov.l   p_test_result, r0
        mov     #3, r9         ! 3 = case 3 (post-inc producer) address/disp corrupted
        mov.l   r9, @r0
        bra     _fail3
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS

        ! Each scratch region needs base+0x400 writable. Give headroom.
        .align 4
scratch1: .space 0x800
        .align 4
scratch2: .space 0x800
        .align 4
scratch3: .space 0x800
