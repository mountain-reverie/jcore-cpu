! m8_runtime.inc -- static runtime for the M8 exhaustive MMU-fault precise-
! exception harness. Every generated per-instruction self-check block plugs into
! this scaffold via the `_m8_run_all` dispatch label.
!
! ============================== ORACLE =====================================
! Fault-transparency: run an instruction TWICE with byte-identical inputs --
!   * faulting leg : the access/fetch hits a COLD TLB -> precise exception ->
!                    the C walker (tlbwalk.c) installs the mapping -> the
!                    instruction restarts.  Snapshot touched arch state to
!                    SNAP_A.
!   * control leg  : the mapping is already WARM -> no fault.  Snapshot to
!                    SNAP_B.
! A precise exception is invisible, so SNAP_A must equal SNAP_B.  Any
! difference is a defect; `_m8_cmp` reports that case's numeric ID.
!
! ============================== CONTRACT ===================================
! A case block (in the generated/`_m8_run_all` file) is straight-line code that:
!   1. seeds its backing memory to a known state,
!   2. arms a COLD TLB                 -> `bsr _m8_flush ; nop`,
!   3. sets the instruction's input registers,
!   4. runs the instruction under test (faults, is serviced, restarts),
!   5. stores the touched arch state (GPRs / memory words) to SNAP_A,
!   6. re-seeds backing memory to the SAME known state (this access re-WARMS
!      the TLB for the control leg -- do NOT flush again),
!   7. sets the SAME input registers,
!   8. runs the instruction under test (warm -> no fault),
!   9. stores the touched arch state to SNAP_B,
!  10. `mov #len,r4 ; mov #id,r5 ; bsr _m8_cmp ; nop`.
! The ONLY difference between leg 5-state and leg 9-state must be whether the
! access faulted (cold vs warm TLB): identical seed, identical input regs,
! identical operands.  `_m8_cmp` returns on match; on mismatch it writes the
! case ID to TEST_RESULT_ADDRESS (-> "Test failed. Result=<id>") and spins.
! After the LAST case returns, `kmain` writes 0 -> "Test Passed".
!
! Fixed workload page: VA 0x00100000 (page index 0x100), identity PTE
! 0x001000F1 (V/R/W/X + flags; bits[11:8]=0 → pm=0), so VA==PA and stores/loads are simple.
!
! Scratch / fixed addresses:
!   SNAP_A           0x80003000   (P1, untranslated)
!   SNAP_B           0x80003100   (P1, untranslated)
!   ctlsv            0x80003200   (PrivMem D-side control-reg baseline save slot)
!   PGD              0x80002000 -> PTE table base 0x80002400 (PGD[0]=0x80002401)
!   PTE for 0x00100  0x80002800   (= pte_tab[0x100])  value 0x001000F1
!   TSB (16 entries) 0x80002C00
!   stack            0x80002F00
!   MMUCR            0xFF000010  (flush: |TI keep AT -> write 0x5)
!   TSBBR/TSBCFG     0xFF000014 / 0xFF000018
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC TSBPTR,r0 =0x0043   STC PTEH,r2 =0x0253   STC ASIDR,r2 =0x0273
!   STC PTEH,r5   =0x0553   STC TSBPTR,r6=0x0643
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E    LDC r3,PTEL =0x436E
!   LDC r0,VBR    =0x402E   LDTLB.RN     =0x0068

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define SNAP_A 0x80003000
#define SNAP_B 0x80003100

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! Relocate SP into P1 and jump to the P1 alias of kmain so ALL code,
        ! stack, and structure accesses are untranslated from here on.
        mov.l   p_sp,   r15            ! r15 = 0x80002F00
        mov.l   p_kmain, r0            ! r0  = 0x80000000 + kmain
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x80002F00
p_kmain: .long 0x80000000 + kmain

kmain:
        ! ---- Ensure RB=0 (keep MD=1). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        ! ---- Initialise PR (slow-path handler pushes it). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- Initialise GBR to a concrete value. The I-fetch axis plants
        ! `STC GBR, Rn` as a case; an uninitialised GBR reads 'U' in the co-sim,
        ! and the snapshot store of that 'U' wedges the SRAM bus (invalid write /
        ! ACK timeout). Seeding GBR makes the case precise rather than vacuous. ----
        mov     #0, r0
        ldc     r0, gbr

        ! ---- ASIDR = 0. ----
        mov     #0, r0
        .word   0x407E                 ! LDC r0, ASIDR

        ! ---- Build PGD[0] -> PTE table (P1 ptr, present). ----
        mov.l   k_pgd,  r0             ! 0x80002000
        mov.l   k_pgd0, r1             ! 0x80002401
        mov.l   r1, @r0

        ! ---- Build the PTEs (PTEL image: backing PA | 0x0F1). Two adjacent
        ! identity pages: 0x100 (workload) and 0x101 (MAC dual-base second
        ! operand, so the two @Rm+/@Rn+ accesses fault on DISTINCT cold pages). ----
        mov.l   k_pteA, r0 ; mov.l v_pteA, r1 ; mov.l r1, @r0
        mov.l   k_pteB, r0 ; mov.l v_pteB, r1 ; mov.l r1, @r0

        ! ---- Zero the 16-entry TSB (64 words). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                 ! LDC r0, VBR

        ! ---- TSB config registers via MMIO. ----
        mov.l   k_tsbbr_a, r0 ; mov.l v_tsbbr, r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. Cases run translated from here. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ---- Dispatch to the generated/hand-written cases (P1 alias). ----
        mov.l   k_runall, r0
        jsr     @r0
        nop

        ! All cases passed (none spun) -> PASS.
        bra     _done
        nop

        .align 2
p_rbclear: .long 0xDFFFFFFF
k_pgd:     .long 0x80002000
k_pgd0:    .long 0x80002401
k_pteA:    .long 0x80002800
v_pteA:    .long 0x001000F1    ! identity PTE: PA(==VA) | flags 0x0F1 (W,X,U,D,V; bits[11:8]=0 → pm=0)
k_pteB:    .long 0x80002804    ! pte_tab[0x101] (= 0x80002400 + 0x101*4)
v_pteB:    .long 0x001010F1    ! identity PTE for VA 0x00101000 (PA in PTEL[31:10])
k_tsb:     .long 0x80002C00
k_vbr:     .long 0x80000000 + _vbase
k_tsbbr_a: .long 0xFF000014
v_tsbbr:   .long 0x80002C04
k_tsbcfg_a:.long 0xFF000018
v_tsbcfg:  .long 0x00000061
k_mmucr:   .long 0xFF000010
k_runall:  .long 0x80000000 + _m8_run_all
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

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
        ! ===================== Shared helpers =====================
        ! _m8_flush: arm a COLD TLB -- MMUCR |= TI (=5) flushes, keeps AT on.
        !            TI self-clears.  Clobbers r0, r1.
        .balign 4
ENTRY(_m8_flush)
        mov.l   m8_mmucr, r0
        mov     #5, r1                 ! TI(4) | AT(1)
        mov.l   r1, @r0
        rts
        nop

        ! _m8_cmp: compare SNAP_A[0..r4) vs SNAP_B[0..r4) (r4 = byte length,
        !          multiple of 4).  r5 = this case's numeric ID.  On match: rts.
        !          On mismatch: write ID to TEST_RESULT_ADDRESS (nonzero ->
        !          "Test failed. Result=<id>", does not exit) and spin.
        !          Clobbers r0-r3.
        .balign 4
ENTRY(_m8_cmp)
        mov.l   m8_snapa, r0
        mov.l   m8_snapb, r1
1:      mov.l   @r0+, r2
        mov.l   @r1+, r3
        cmp/eq  r2, r3
        bf      _m8_cmp_fail
        add     #-4, r4
        cmp/pl  r4
        bt      1b
        rts
        nop
_m8_cmp_fail:
        mov.l   m8_result, r0
        mov.l   r5, @r0                ! report ID; nonzero -> no exit
2:      bra     2b
        nop

        .align 2
m8_mmucr:  .long 0xFF000010
m8_snapa:  .long SNAP_A
m8_snapb:  .long SNAP_B
m8_result: .long TEST_RESULT_ADDRESS

        ! ===================== Exception vector base =====================
        ! VBR points at the P1 alias of _vbase; hardware adds the per-access-type
        ! offset: +0x400 IMISS, +0x420 DMISS_R (load), +0x440 DMISS_W (store).
        .balign 4
_vbase:
        .space 0x400, 0
_v_ifetch:                              ! _vbase + 0x400  (IMISS)
        bra     _h_common
        nop
        .space (0x420 - 0x400 - 4), 0
_v_load:                                ! _vbase + 0x420  (DMISS_R)
        bra     _h_common
        nop
        .space (0x440 - 0x420 - 4), 0
_v_store:                               ! _vbase + 0x440  (DMISS_W)
        bra     _h_common
        nop

        ! ---- §4.1 hot path (bank-1 scratch; AT stays ON). ----
_h_common:
        .word   0x0043                  ! STC TSBPTR, r0
        mov.l   @r0+, r1                ! tag_hi (expected VPN)
        .word   0x0253                  ! STC PTEH, r2
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @r0+, r1                ! tag_lo (expected ASID_TAG)
        .word   0x0273                  ! STC ASIDR, r2
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @r0, r3                 ! TTE Data (PTEL image)
        .word   0x436E                  ! LDC r3, PTEL
        .word   0x0068                  ! LDTLB.RN  (install + return atomically)

        ! ---- Slow path: call the C walker. ----
_h_slow:
        sts.l   pr, @-r15
        mov.l   H_pgd, r4               ! r4 = pgd (P1)
        .word   0x0553                  ! STC PTEH, r5   (faulting page VA)
        .word   0x0643                  ! STC TSBPTR, r6 (TSB slot ptr)
        mov.l   H_walk, r7
        jsr     @r7
         nop
        tst     r0, r0
        bt      _h_realfault            ! r0==0 -> walker fault
        lds.l   @r15+, pr
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0068                  ! LDTLB.RN

_h_realfault:
        lds.l   @r15+, pr
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT
        mov.l   H_result, r0
        mov     #7, r1
        mov.l   r1, @r0                 ! TEST_RESULT = 7 (unexpected walker fault)
1:      bra     1b
        nop

        .align 2
H_pgd:    .long 0x80002000
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker runs untranslated
H_mmucr:  .long 0xFF000010
H_result: .long TEST_RESULT_ADDRESS
#endif
