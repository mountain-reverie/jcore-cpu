! sh2a_movml_push_restart.S -- restart-safety proof for SH-2A MOVML.L Rm,@-R15
! (multi-register PUSH) under a MID-LOOP data TLB *store* fault, AND the
! companion leak-detection guard for push_active / movml_pushinit_r
! (CONFIG_SH2A_ARCH && CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH).
!
! Design property under test: MOVML.L R4,@-R15 (push R0..R4, opcode
! 0100 0100 1111 0001 = 0x44F1) is implemented in decode_core.vhm /
! datapath.vhm as: ONE init slot that computes a datapath-internal scratch
! push_ptr = R15 - 4*(m+1) (NOT written to R15), then m+1 indexed STORE slots
! R(idx) @ push_ptr + idx*4 (idx 0..m), then ONE terminal slot that commits
! R15 := R15 - 4*(m+1). R15 is pristine until the terminal slot, so a store
! that faults mid-loop restarts the WHOLE instruction from idx 0 with R15 and
! push_ptr recomputed identically -- already-committed stores are re-written
! with identical values (idempotent).
!
! Straddle: R15 = 0x1010 so push_ptr = 0x1010 - 20 = 0x0FFC.
!     idx0 -> VA 0x0FFC -> R0   (page 0, mapped: commits every attempt)
!     idx1 -> VA 0x1000 -> R1   (page 1, UNMAPPED first attempt -> DMISS_W)
!     idx2 -> VA 0x1004 -> R2   (page 1)
!     idx3 -> VA 0x1008 -> R3   (page 1)
!     idx4 -> VA 0x100C -> R4   (page 1, just below original R15=0x1010)
! So the fault hits an EARLY store (idx1) AFTER idx0 already committed -- the
! genuine mid-push window that exercises the restart AND the state leak.
!
! LEAK GUARD (the whole point of this test vs a plain restart test): a
! pre-fix core never clears push_active (datapath) / movml_pushinit_r
! (decode_core) when the terminal slot is skipped by the fault redirect, so
! BOTH latches stay '1' into the handler. The handler then executes an
! ORDINARY MOV.L Rm,@(0,R15) SP-relative store of a marker to VA 0x1010
! (= the pristine R15, one word ABOVE the push region). With push_active
! leaked, that store's address signature matches push_ptr_store and it is
! MISROUTED to push_ptr+0 = 0x0FFC instead of 0x1010, so VA 0x1010 never
! receives the marker (check 8 below fails). With the fix, push_active is
! cleared on the first committing redirect slot, so the marker lands at
! 0x1010. (The restart-side movml_pushinit_r leak independently corrupts the
! restarted store sequence -> checks 1..5/6 fail on a pre-fix core too.)
!
! The handler runs with SR.RB=1 (bank 1), so its use of r0..r2 touches the
! BANKED bank-1 registers -- it does NOT clobber the bank-0 R0..R4 that the
! push restart re-reads. R15 (R8..R15 are common, unbanked) is shared, which
! is exactly why the SP-relative marker store exercises the leak.
!
! Result codes (TEST_RESULT_ADDRESS):
!   0 pass
!   1..5  mem[push_ptr+idx*4] mismatch for R0..R4 after restart
!   6     R15 not updated to start-20 (0x0FFC) after restart
!   7     fault handler did not run exactly once
!   8     handler SP-relative marker store LEAKED (VA 0x1010 != marker) --
!         push_active/movml_pushinit_r not cleared on the mid-push fault
!   9     DMISS_W EXPEVT code wrong (handler-side guard)
!  10     DMISS_W TEA wrong (handler-side guard)
!  15     unexpected trap / fell through to _fail
!
! Hand-encoded (sh2-elf-as -m2 lacks these): MOVML.L r4,@-r15=0x44F1;
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E  LDTLB=0x0038
!   LDC r0,VBR=0x402E   STC EXPEVT,r0=0x0052

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_dstore - 0x440 (VBR+0x440 = D-store vector = _v_dstore). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Clear fault counter. ----
        mov.l   p_g_fault_count, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Pre-seed the scratch word VA 0x1010 with a non-marker sentinel
        !      (AT still off: flat physical addressing). If the handler's marker
        !      store leaks to push_ptr instead, 0x1010 keeps this value. ----
        mov.l   p_scratch, r0
        mov.l   p_scratch_pre, r1
        mov.l   r1, @r0

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. Page 1 deliberately left UNMAPPED so store idx1 (the
        !      R1 store to VA 0x1000) DMISSes. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0
        nop
        nop
        nop
        nop
        nop
        nop

        ! ---- Load the push source registers R0..R4 with sentinels (bank 0). ----
        mov.l   p_s0, r0
        mov.l   p_s1, r1
        mov.l   p_s2, r2
        mov.l   p_s3, r3
        mov.l   p_s4, r4
        mov.l   p_sp0, r15              ! R15 = 0x1010 -> push_ptr = 0x0FFC
        nop

        ! --- instruction under test: MOVML.L r4,@-r15 (push R0..R4). ---
        ! First attempt: idx0 (R0->0x0FFC) commits, idx1 (R1->0x1000) DMISSes.
        ! Handler maps page 1, runs a leak-detecting SP store, RTEs with SPC
        ! still at THIS instruction, so it restarts from idx0.
        .word   0x44F1

        ! ---- Verify each register landed at push_ptr + idx*4. ----
        mov.l   p_ppc, r6              ! r6 = push_ptr = 0x0FFC
        mov.l   p_s0, r7
        mov.l   @(0,r6), r5
        cmp/eq  r5, r7
        bf      _fail1
        mov.l   p_s1, r7
        mov.l   @(4,r6), r5
        cmp/eq  r5, r7
        bf      _fail2
        mov.l   p_s2, r7
        mov.l   @(8,r6), r5
        cmp/eq  r5, r7
        bf      _fail3
        mov.l   p_s3, r7
        mov.l   @(12,r6), r5
        cmp/eq  r5, r7
        bf      _fail4
        mov.l   p_s4, r7
        mov.l   @(16,r6), r5
        cmp/eq  r5, r7
        bf      _fail5

        ! ---- Verify R15 == start - 4*5 = 0x1010 - 20 = 0x0FFC. ----
        mov.l   p_sp_final, r7
        cmp/eq  r15, r7
        bf      _fail6

        ! ---- Verify the fault handler ran EXACTLY ONCE. ----
        mov.l   p_g_fault_count, r0
        mov.l   @r0, r7
        mov     #1, r6
        cmp/eq  r6, r7
        bf      _fail7

        ! ---- LEAK GUARD: the handler's SP-relative marker store must have
        !      landed at VA 0x1010, not been misrouted to push_ptr. ----
        mov.l   p_scratch, r0
        mov.l   @r0, r7
        mov.l   p_marker, r6
        cmp/eq  r6, r7
        bf      _fail8

        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_dstore - 0x440 ! VBR so VBR+0x440 = _v_dstore (D-store vector)
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000E8        ! W|X|U|C
p_sp0:          .long 0x00001010        ! R15 start: push_ptr = 0x0FFC straddles page 0/1
p_sp_final:     .long 0x00000FFC        ! R15 after push: start - 4*5
p_ppc:          .long 0x00000FFC        ! push_ptr base
p_scratch:      .long 0x00001010        ! handler SP-relative store target (= R15 start)
p_scratch_pre:  .long 0x11111111        ! pre-seed sentinel (must be overwritten by marker)
p_marker:       .long 0x5A5A5A5A        ! handler marker value
p_g_fault_count: .long _g_fault_count
p_s0:  .long 0xA0A0A000
p_s1:  .long 0xB1B1B111
p_s2:  .long 0xC2C2C222
p_s3:  .long 0xD3D3D333
p_s4:  .long 0xE4E4E444

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH

        .global _done
ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop

_fail1: mov.l p_test_result, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail1
        nop
_fail2: mov.l p_test_result, r0
        mov #2, r9
        mov.l r9, @r0
        bra _fail2
        nop
_fail3: mov.l p_test_result, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail3
        nop
_fail4: mov.l p_test_result, r0
        mov #4, r9
        mov.l r9, @r0
        bra _fail4
        nop
_fail5: mov.l p_test_result, r0
        mov #5, r9
        mov.l r9, @r0
        bra _fail5
        nop
_fail6: mov.l p_test_result, r0
        mov #6, r9
        mov.l r9, @r0
        bra _fail6
        nop
_fail7: mov.l p_test_result, r0
        mov #7, r9
        mov.l r9, @r0
        bra _fail7
        nop
_fail8: mov.l p_test_result, r0
        mov #8, r9
        mov.l r9, @r0
        bra _fail8
        nop

        .global _fail
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov     #15, r9
        mov.l   r9, @r0
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH

        ! ================================================================
        ! DMISS_W handler at VBR+0x440 (D-store vector) = _v_dstore.
        ! Runs with RB=1 (bank 1): r0..r2 here are the banked bank-1 copies,
        ! so they do NOT clobber the bank-0 R0..R4 the push restart re-reads.
        ! Maps page 1, does a leak-detecting ORDINARY SP-relative marker store
        ! (must land at VA 0x1010 = R15, NOT be misrouted to push_ptr), bumps
        ! the fault counter, RTEs WITHOUT touching SPC.
        ! ================================================================
        .balign 4
        .space 0x380, 0
        .balign 4
_v_dstore:                              ! = VBR + 0x440
        ! Sanity-guard: EXPEVT must be DMISS_W (0x080).
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hc_dmiss_w, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt

        ! Sanity-guard: TEA must be VA 0x1000 (the R1 store address).
        mov.l   Hp_tea_addr, r0
        mov.l   @r0, r2
        mov.l   Hc_page1_va, r1
        cmp/eq  r1, r2
        bf      _h_bad_tea

        ! Map page 1 (VA 0x1000-0x1FFF): identity, W+X+U+C = 0xE8.
        mov.l   Hc_page1_va, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=1, ASID=0)
        mov.l   Hp_ptel_page1, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! LEAK GUARD store: ordinary MOV.L Rm,@(0,R15). R15 is common (pristine
        ! 0x1010, now a mapped page). On a leaking core push_active=1 misroutes
        ! this to push_ptr+0 = 0x0FFC; on a fixed core it lands at 0x1010.
        mov.l   Hp_marker, r1
        mov.l   r1, @(0,r15)

        ! Bump fault counter.
        mov.l   Hp_g_fault_count, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0

        ! Return WITHOUT touching SPC: hardware-captured SPC = the MOVML.L's own
        ! PC, so the whole push retries from idx0.
        rte
        nop

_h_bad_expevt:
        mov.l   Hp_test_result, r0
        mov     #9, r9
        mov.l   r9, @r0
_h_bad_expevt_spin:
        bra     _h_bad_expevt_spin
        nop

_h_bad_tea:
        mov.l   Hp_test_result, r0
        mov     #10, r9
        mov.l   r9, @r0
_h_bad_tea_spin:
        bra     _h_bad_tea_spin
        nop

        .balign 4
Hc_dmiss_w:         .long 0x00000080
Hc_page1_va:        .long 0x00001000
Hp_tea_addr:        .long 0xFF00000C
Hp_ptel_page1:      .long 0x000010E8        ! PPN=0x1000>>10 (identity) | W|X|U|C
Hp_marker:          .long 0x5A5A5A5A
Hp_g_fault_count:   .long _g_fault_count
Hp_test_result:     .long TEST_RESULT_ADDRESS

        ! ================================================================
        ! Shared handler globals + page-1 physical backing.
        ! ================================================================
        .balign 4
_g_fault_count: .long 0

_fault_pages:
        .space 0x1000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH
