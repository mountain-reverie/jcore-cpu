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
! Scratch / fixed addresses.  THE WHOLE BLOCK LIVES AT 0x00010000, ABOVE ANY
! IMAGE, AND MUST STAY THERE.  It used to sit at 0x00002000, which the images
! outgrew: m8_dsdslot_0 links to _edata=0x2bb4, so kmain's OWN page-table setup
! was writing PGD[0] over case 23's literal pool (0x2000) and the four PTEs over
! case 29's (0x2800-0x280F), and the 64-long TSB zero-fill at 0x2C00 was 76 bytes
! from erasing _m8_run_all itself -- which is exactly what happened the moment
! one more case (CAS.L) pushed _edata to 0x2d10: the dispatcher was zeroed, the
! jsr ran into zeros, and the CPU reset-looped every ~4.8us.  That looked
! convincingly like a locked-RMW bus hang and is not a CPU defect at all.
! sim/tests/Makefile now FAILS the build if an m8 image reaches 0x10000, so this
! cannot come back silently.  Keep the block 256-byte aligned: TSBPTR is
! (TSBBR and not 0xF) OR (index << 4), an OR rather than an add, so a
! non-256-aligned TSB base would alias its own entries.
!
! Scratch / fixed addresses:
!   SNAP_A           0x80011000   (P1, untranslated)
!   SNAP_B           0x80011100   (P1, untranslated)
!   ctlsv            0x80011200   (PrivMem D-side control-reg baseline save slot)
!   M8_FCNT          0x80011300   (fault counter; _h_common increments it once
!                                  per TLB fault, both fast and slow path)
!   PGD              0x80010000 -> PTE table base 0x80010400 (PGD[0]=0x80010401)
!   PTE for 0x00100  0x80010800   (= pte_tab[0x100])  value 0x001000F1
!   TSB (16 entries) 0x80010C00
!   stack            0x80010F00
!   MMUCR            0xFF000010  (flush: |TI keep AT -> write 0x5)
!   TSBBR/TSBCFG     0xFF000014 / 0xFF000018
!   PTEH/PTEL        0xFF000000 / 0xFF000004   (read-only P4 aliases)
!   TSBPTR/ASIDR     0xFF00001C / 0xFF000038   (read-only P4 aliases)
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E    LDC r3,PTEL =0x436E
!   LDC r0,VBR    =0x402E   LDTLB.RN     =0x0078

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define SNAP_A 0x80011000
#define SNAP_B 0x80011100
! M8_FCNT: total TLB faults taken, incremented once per entry to _h_common
! (which is the common target of the IMISS/DMISS_R/DMISS_W vectors, so it
! counts every fault on both the fast and the slow path).
!
! Why this exists: the axes compare a faulting run against a reference run and
! assert the architectural state matches. That says nothing about whether a
! fault ever happened, so a case whose fault stops firing still passes. Measured
! on m8_dsdslot_0 (2026-08-07): pointing a case's flush at _m8_flush+6, so
! MMUCR.TI is never set and no fault CAN occur, left the case green. The
! counter turns "a fault fired" into something a case can assert.
#define M8_FCNT 0x80011300

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
        ! Relocate SP into P1 and jump to the P1 alias of kmain so ALL code,
        ! stack, and structure accesses are untranslated from here on.
        mov.l   p_sp,   r15            ! r15 = 0x80010F00
        mov.l   p_kmain, r0            ! r0  = 0x80000000 + kmain
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x80010F00
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
        mov.l   k_pgd,  r0             ! 0x80010000
        mov.l   k_pgd0, r1             ! 0x80010401
        mov.l   r1, @r0

        ! ---- Build the PTEs (PTEL image: backing PA | 0x0F1). Four adjacent
        ! identity pages: 0x100 (workload) and 0x101 (MAC dual-base second
        ! operand, so the two @Rm+/@Rn+ accesses fault on DISTINCT cold pages);
        ! 0x102/0x103 (DSideDSlot Case A/B data page C / branch-target page D --
        ! the TLB is UNIFIED (one array for I and D, core/tlb.vhd) so a delay-
        ! slot D-access and a branch-target I-fetch each need their OWN page
        ! distinct from the branch (A) and delay-slot-fetch (B) pages, or they
        ! silently re-hit a TLB entry the other access type already installed. ----
        mov.l   k_pteA, r0 ; mov.l v_pteA, r1 ; mov.l r1, @r0
        mov.l   k_pteB, r0 ; mov.l v_pteB, r1 ; mov.l r1, @r0
        mov.l   k_pteC, r0 ; mov.l v_pteC, r1 ; mov.l r1, @r0
        mov.l   k_pteD, r0 ; mov.l v_pteD, r1 ; mov.l r1, @r0

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
k_pgd:     .long 0x80010000
k_pgd0:    .long 0x80010401
k_pteA:    .long 0x80010800
v_pteA:    .long 0x001000D1    ! identity PTE: PA(==VA) | flags 0x0D1 (U cleared: kernel code, SMEP)
k_pteB:    .long 0x80010804    ! pte_tab[0x101] (= 0x80010400 + 0x101*4)
v_pteB:    .long 0x001010D1    ! identity PTE for VA 0x00101000, U cleared: kernel code, SMEP
k_pteC:    .long 0x80010808    ! pte_tab[0x102] (= 0x80010400 + 0x102*4)
v_pteC:    .long 0x001020D1    ! identity PTE for VA 0x00102000 (DSideDSlot data page C)
k_pteD:    .long 0x8001080C    ! pte_tab[0x103] (= 0x80010400 + 0x103*4)
v_pteD:    .long 0x001030D1    ! identity PTE for VA 0x00103000 (DSideDSlot target page D)
k_tsb:     .long 0x80010C00
k_vbr:     .long 0x80000000 + _vbase
k_tsbbr_a: .long 0xFF000014
v_tsbbr:   .long 0x80010C04
k_tsbcfg_a:.long 0xFF000018
v_tsbcfg:  .long 0x00000061
k_mmucr:   .long 0xFF000010
k_runall:  .long 0x80000000 + _m8_run_all
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
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
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ===================== Shared helpers =====================
        ! _m8_flush: arm a COLD TLB -- MMUCR |= TI (=5) flushes, keeps AT on --
        !            AND zero the 16-entry TSB, so the hardware walker cannot
        !            resolve the next faulting access from a warm TSB slot left
        !            behind by an earlier case.  Without this, only case 1 of
        !            each sub-image ever reaches software: from case 2 on the
        !            walker installs from the still-warm TSB with M8_FCNT==0,
        !            and every _m8_fcntchk downstream reports "no fault fired".
        !            TI self-clears.  Clobbers r0, r1, r2.
        .balign 4
ENTRY(_m8_flush)
        mov.l   m8_mmucr, r0
        mov     #5, r1                 ! TI(4) | AT(1)
        mov.l   r1, @r0
        mov.l   m8_tsb, r0
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b
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

        ! _m8_fcntchk: assert at least one fault was taken by the run that just
        !              finished, THEN clear the counter for the next run.
        !              r5 = this case's numeric ID (same convention as _m8_cmp:
        !              on failure the ID is written to TEST_RESULT_ADDRESS and
        !              the test spins, so the co-sim reports Result=<id>).
        !              Clobbers r0, r1.
        !
        ! Check-and-clear, so no separate "reset" call is needed at the flush
        ! sites: every measured run starts from zero because the preceding
        ! check zeroed it. That matters for more than brevity -- the counter
        ! must NOT be cleared inside _m8_flush, because the mutation this whole
        ! mechanism exists to catch (pointing a case's flush literal at
        ! _m8_flush+6 so the flush is skipped) would then skip the clear too,
        ! leave a stale nonzero count behind, and pass anyway.
        !
        ! Deliberately ">= 1", not an exact count: it closes the demonstrated
        ! hole (a case whose fault never fires still passing) without baking in
        ! a per-case expected number that nothing currently derives. An exact
        ! count would also catch "faulted, but fewer times than intended" --
        ! e.g. the instruction under test replaced by a nop, which still faults
        ! on the delay-slot I-fetch and so survives this check.
        !
        ! KNOWN GAP, and the design to close it (a 2026-08-08 review raised this;
        ! it was attempted and backed out, deliberately, see below).
        ! One counter checked after BOTH legs cannot say WHICH leg faulted, so a
        ! case whose CONTROL (warm) leg also faults still passes and the oracle
        ! degenerates to comparing fault-vs-fault -- the same vacuity this counter
        ! exists to close. The same weakness was found and fixed by hand in
        ! sim/tests/m8_macseq.S, where a counter checked from case entry was
        ! satisfied by cold-TLB setup faults alone, so this is live, not theory.
        !
        ! The fix that works: add M8_FCNT_A and an _m8_fcntsplit helper called at
        ! the leg boundary, which parks the faulting leg's count in M8_FCNT_A and
        ! re-zeros M8_FCNT so the control leg is measured alone. _m8_fcntchk then
        ! asserts BOTH `M8_FCNT_A >= 1` (the faulting leg did fault) and
        ! `M8_FCNT == 0` (the control leg did not). _m8_fcntsplit must save and
        ! restore r0-r2 and take NO registers: the emitted cases carry live state
        ! across that boundary and the templates disagree about which registers,
        ! so any clobber contract is unsafe.
        !
        ! Why it is not done here: the call has to be emitted into EVERY case, and
        ! decode/gen-go/internal/faultgen/emit.go has NINE templates carrying a
        ! _fcntchk literal while only four share the `! ---- control leg (warm
        ! TLB) ----` marker -- the leg boundary is spelled differently in the
        ! rest and has to be located per template. A partially-applied version
        ! fails every m8 case at once (fcntchk would read an M8_FCNT_A that no
        ! template sets), so it is all-or-nothing and wants its own commit.
        .balign 4
ENTRY(_m8_fcntchk)
        mov.l   m8_fcnt_p, r0
        mov.l   @r0, r1
        tst     r1, r1
        bt      _m8_cmp_fail           ! count == 0 -> no fault fired
        mov     #0, r1
        rts
         mov.l  r1, @r0                ! clear for the next run

        .balign 4
m8_fcnt_p: .long M8_FCNT

        .align 2
m8_mmucr:  .long 0xFF000010
m8_tsb:    .long 0x80010C00
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
        ! M8_FCNT++ -- placed BEFORE the fast/slow split so it counts every
        ! fault regardless of which path services it. r4/r5 are bank-1 scratch
        ! here (hardware sets RB=1 on exception entry) and the fast path below
        ! only uses r0-r3, so clobbering them is safe; _h_slow reloads r4-r7
        ! itself before the walker call.
        mov.l   H_fcnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4
        mov.l   H_tsbptr_a, r0
        mov.l   @r0, r0                 ! TSBPTR (P4 alias)
        mov.l   @r0+, r1                ! tag_hi (expected VPN)
        mov.l   H_pteh_a, r2
        mov.l   @r2, r2                 ! PTEH (P4 alias)
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @r0+, r1                ! tag_lo (expected ASID_TAG)
        mov.l   H_asidr_a, r2
        mov.l   @r2, r2                 ! ASIDR (P4 alias)
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @r0, r3                 ! TTE Data (PTEL image)
        .word   0x436E                  ! LDC r3, PTEL
        .word   0x0078                  ! LDTLB.RN  (install + return atomically)

        ! ---- Slow path: call the C walker. ----
_h_slow:
        sts.l   pr, @-r15
        mov.l   H_pgd, r4               ! r4 = pgd (P1)
        mov.l   H_pteh_a, r5
        mov.l   @r5, r5                 ! r5 = PTEH   (faulting page VA)
        mov.l   H_tsbptr_a, r6
        mov.l   @r6, r6                 ! r6 = TSBPTR (TSB slot ptr)
        mov.l   H_walk, r7
        jsr     @r7
         nop
        tst     r0, r0
        bt      _h_realfault            ! r0==0 -> walker fault
        lds.l   @r15+, pr
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0078                  ! LDTLB.RN

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
H_fcnt:   .long M8_FCNT
H_pgd:    .long 0x80010000
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker runs untranslated
H_mmucr:  .long 0xFF000010
H_result: .long TEST_RESULT_ADDRESS
H_pteh_a:   .long 0xFF000000
H_tsbptr_a: .long 0xFF00001C
H_asidr_a:  .long 0xFF000038
#endif
