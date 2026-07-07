! pagefault_dmac.S -- PAGE_FAULT_ARCH data-read fault on a MAC.L @Rm+,@Rn+ whose
! first operand read faults from the flash/D-window. The exotic reliability case:
! the multiply-ACCUMULATE (MACH:MACL) must NOT double-apply across the fault, and
! BOTH post-increment bases must advance exactly once. This exercises the shared
! acc_squash wiring (cpu.vhd: mac_i.acc_squash <= dp_tlb_squash) on the base J1.
!
! *** KNOWN LIMITATION (currently EXPECTED TO FAIL, Result=12) ***
! On the base J1 PAGE_FAULT path the squash follows tlb_exc_pend (the
! `elsif PAGE_FAULT_ARCH` branch in core/datapath.vhm's squash block). pend drops
! at exception dispatch -- BEFORE the MAC accumulate commits -- so the faulting
! pass's accumulate is NOT suppressed and the clean restart adds it AGAIN
! (2*3=6 twice -> MACL=12 instead of 6). The J4 MMU avoids this by holding the
! squash until SR.RB (later, covering the MAC commit); the base J1 has no RB.
! The base restore (r0/r8) IS correct (single increment) -- only the accumulate
! double-applies. FIX (deferred): a MAC-only squash-hold decoupled from the GPR
! writeback squash (which must stay pend-following so it does not eat the R15
! pushes). MITIGATION: do not MAC.L/W @Rm+,@Rn+ directly from an unmapped flash
! page -- make the operand page resident first, or stream DSP data from RAM.
! Kept as a regression MARKER; NOT in pagefault_sim.sh's default run list.
!
! Flow:
!   - pre-store A=0x00000002 @ 0x00050000, B=0x00000003 @ 0x00050020 (WRITES,
!     not faulted; both live in the 0x0005_xxxx D-window)
!   - clear MAC; r0=0x50000, r8=0x50020
!   - MAC.L @r0+,@r8+ -> the FIRST operand read (@r0) faults (PF_DREAD). Handler
!     disarms the whole D-window (one-shot), RTEs; the restart re-runs the MAC with
!     both reads clean -> acc = 2*3 = 6 EXACTLY ONCE, r0=0x50004, r8=0x50024.
!   - PASS iff MACL==6 AND MACH==0 AND r0==0x50004 AND r8==0x50024.
!     A lingering faulting-pass accumulate would give MACL==12 (2*6) or similar;
!     a double-increment would give r0==0x50008 / r8==0x50028.

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
#if CONFIG_PAGE_FAULT_ARCH
        mov     #0, r1
        mov.l   p_vbr, r0
        ldc     r0, vbr                 ! VBR -> _vbr_table
        ! ---- seed operands (WRITES -> not faulted) ----
        mov.l   c_wa, r0                ! 0x00050000
        mov     #2, r1 ; mov.l r1, @r0
        mov.l   c_wb, r0                ! 0x00050020
        mov     #3, r1 ; mov.l r1, @r0
        ! ---- clear MAC ----
        mov     #0, r9
        lds     r9, mach
        lds     r9, macl
        ! ---- faulting MAC ----
        mov.l   c_wa, r0                ! r0 = 0x00050000
        mov.l   c_wb, r8                ! r8 = 0x00050020
        mac.l   @r0+, @r8+              ! first read faults; restart accumulates once
        ! ---- checks ----
        mov.l   c_r0end, r2 ; cmp/eq r2, r0 ; bf _fail_r0   ! r0 single-inc
        mov.l   c_r8end, r2 ; cmp/eq r2, r8 ; bf _fail_r8   ! r8 single-inc
        sts     mach, r3   ; mov #0, r2  ; cmp/eq r2, r3 ; bf _fail_mh ! MACH==0
        sts     macl, r3   ; mov #6, r2  ; cmp/eq r2, r3 ; bt _done    ! MACL==6
        mov     #9, r9
        bra     _fail
        nop
_fail_r0: mov #4, r9 ; bra _fail ; nop
_fail_r8: mov #5, r9 ; bra _fail ; nop
_fail_mh: mov #6, r9 ; bra _fail ; nop

        .align 2
p_vbr:      .long _vbr_table
c_wa:       .long 0x00050000
c_wb:       .long 0x00050020
c_r0end:    .long 0x00050004
c_r8end:    .long 0x00050024
        .align 2
_vbr_table: .long _pf_handler

! Handler: preserve r0/r8 (the MAC bases) and r1, disarm the D-window, RTE.
        .align 2
_pf_handler:
        mov.l   r0, @-r15
        mov.l   r8, @-r15
        mov.l   r1, @-r15
        mov.l   hd_disarm, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! store 0x00060000 -> tb disarms D-window
        mov.l   @r15+, r1
        mov.l   @r15+, r8
        mov.l   @r15+, r0
        rte
        nop
        .align 2
hd_disarm:  .long 0x00060000
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
