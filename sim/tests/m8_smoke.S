! m8_smoke.S -- hand-written end-to-end smoke test for the M8 fault harness.
!
! Defines `_m8_run_all` with TWO cases that exercise the runtime contract in
! m8_runtime.inc:
!   Case 1 (known PASS): translated `mov.l @r0+, r8` -- post-M7 the @Rn+
!     post-increment is PRECISE across a DMISS_R, so the faulting and control
!     legs produce identical {r0, r8}.  No Result=1.
!   Case 2 (known FAIL): translated `mov.l r8,@-r0` (pre-decrement store) --
!     a DEFERRED defect: the base decrement leaks across the DMISS_W (rides
!     we_ex, not squashed), so the faulting leg decrements twice and stores to
!     the wrong word.  Snapshots {r0, mem[VA+4]} differ -> Result=2.
!
! EXPECTED co-sim output with BOTH cases: "Test failed. Result=2" and NO
! "Test Passed" (case 2 spins).  Disabling case 2's `bsr _m8_cmp` yields
! "Test Passed", independently confirming case 1 is precise.
!
! The two legs of each case differ ONLY in cold (fault) vs warm (no fault) TLB:
! same memory seed, same input registers, same operands.

#include "m8_runtime.inc"

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        .text
ENTRY(_m8_run_all)
        sts.l   pr, @-r15              ! preserve return to kmain

        ! ================= Case 1: mov.l @r0+, r8  (PASS) =================
        ! Inputs: r0 = VA (0x00100000), r8 = 0.  Snapshot {r0, r8}, len 8.
        ! ---- faulting leg ----
        mov.l   c1_va, r0
        mov.l   c1_seed, r1
        mov.l   r1, @r0                ! seed mem[VA] = 0xA11C0001
        bsr     _m8_flush              ! cold TLB
        nop
        mov.l   c1_va, r0              ! r0 = VA
        mov     #0, r8                 ! poison dest
        mov.l   @r0+, r8               ! <-- faults DMISS_R, restarts
        mov.l   c1_snapa, r2
        mov.l   r0, @r2                ! SNAP_A[0] = r0
        mov.l   r8, @(4,r2)            ! SNAP_A[1] = r8
        ! ---- control leg ----
        mov.l   c1_va, r0
        mov.l   c1_seed, r1
        mov.l   r1, @r0                ! re-seed (warm store; re-warms TLB)
        mov.l   c1_va, r0
        mov     #0, r8
        mov.l   @r0+, r8               ! warm: no fault
        mov.l   c1_snapb, r2
        mov.l   r0, @r2                ! SNAP_B[0] = r0
        mov.l   r8, @(4,r2)            ! SNAP_B[1] = r8
        ! ---- compare ----
        mov     #8, r4
        mov     #1, r5
        bsr     _m8_cmp
        nop

        ! ================= Case 2: mov.l r8,@-r0  (FAIL) =================
        ! Inputs: r0 = VA+8 (0x00100008), r8 = store value.  @-r0 pre-decrements
        ! r0 by 4 then stores -> architecturally r0=VA+4, mem[VA+4]=stval.
        ! Snapshot {r0, mem[VA+4]}, len 8.  The leaking decrement makes the
        ! faulting leg store to VA and leave r0=VA -> both words differ.
        ! ---- faulting leg ----
        mov.l   c2_va4, r0
        mov.l   c1_seed, r1
        mov.l   r1, @r0                ! seed mem[VA+4] = 0xA11C0001
        bsr     _m8_flush              ! cold TLB
        nop
        mov.l   c2_va8, r0             ! r0 = VA+8
        mov.l   c2_stval, r8           ! store value
        mov.l   r8, @-r0               ! <-- faults DMISS_W, restarts
        mov.l   c1_snapa, r2
        mov.l   r0, @r2                ! SNAP_A[0] = r0 (final base)
        mov.l   c2_va4, r3
        mov.l   @r3, r1
        mov.l   r1, @(4,r2)            ! SNAP_A[1] = mem[VA+4]
        ! ---- control leg ----
        mov.l   c2_va4, r0
        mov.l   c1_seed, r1
        mov.l   r1, @r0                ! re-seed mem[VA+4] (warm; re-warms TLB)
        mov.l   c2_va8, r0
        mov.l   c2_stval, r8
        mov.l   r8, @-r0               ! warm: no fault
        mov.l   c1_snapb, r2
        mov.l   r0, @r2                ! SNAP_B[0] = r0
        mov.l   c2_va4, r3
        mov.l   @r3, r1
        mov.l   r1, @(4,r2)            ! SNAP_B[1] = mem[VA+4]
        ! ---- compare ----
        mov     #8, r4
        mov     #2, r5
        bsr     _m8_cmp                ! <-- reports Result=2 and spins
        nop

        lds.l   @r15+, pr
        rts
        nop

        .align 2
c1_va:    .long 0x00100000
c1_seed:  .long 0xA11C0001
c1_snapa: .long SNAP_A
c1_snapb: .long SNAP_B
c2_va4:   .long 0x00100004
c2_va8:   .long 0x00100008
c2_stval: .long 0x57013333
#endif
