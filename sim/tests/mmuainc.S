! mmuainc.S -- RED guard: @Rn+ auto-increment leaks across a D-side TLB fault.
!
! A single straight-line `mov.l @Rn+, Rm` whose operand lives in a translated
! page takes a cold DMISS_R. The §4.2 handler installs the mapping and returns
! (LDTLB.RN) so the load RE-EXECUTES. Architecturally the post-increment must
! occur EXACTLY ONCE: Rn == VA+4, Rm == seed.
!
! Defect: the precise-exception squash (tlb_squash, 441a25a) gates only we_wb,
! NOT we_ex. The post-increment base update rides we_ex, so the faulting attempt
! already bumped Rn once before the exception; the restart bumps it AGAIN ->
! Rn == VA+8 (double). A displacement load `mov.l @(0,Rn),Rm` writes Rm via
! we_wb (squashed) and is immune -- used as the control (define AINC_DISP_CONTROL).
!
! Kernel (code/stack/PGD/PTE/TSB) lives in P1 (untranslated): the handler never
! faults. Reuses the mmurun §4.1/§4.2 handler + C walker (tlbwalk.o).
!
! TEST_RESULT codes: 0 PASS ; 1 Rn wrong (double-increment) ; 2 Rm wrong.
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC TSBPTR,r0 =0x0043   STC PTEH,r2 =0x0253   STC ASIDR,r2 =0x0273
!   STC PTEH,r5   =0x0553   STC TSBPTR,r6=0x0643
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E    LDC r3,PTEL =0x436E
!   LDC r0,VBR    =0x402E   LDTLB.RN     =0x0078

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

        ! ---- ASIDR = 0. ----
        mov     #0, r0
        .word   0x407E                 ! LDC r0, ASIDR

        ! ---- Build PGD[0] -> PTE table (P1 ptr, present). ----
        mov.l   k_pgd,  r0             ! 0x80002000
        mov.l   k_pgd0, r1            ! 0x80002401
        mov.l   r1, @r0

        ! ---- Build the one PTE (PTEL image: backing PA | 0x0F1). ----
        mov.l   k_pteA, r0 ; mov.l v_pteA, r1 ; mov.l r1, @r0

        ! ---- Zero the 16-entry TSB (64 words). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed the backing page (AT off, identity) with the known value. ----
        mov.l   k_bkA, r0 ; mov.l v_seedA, r1 ; mov.l r1, @r0

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                 ! LDC r0, VBR

        ! ---- TSB config registers via MMIO. ----
        mov.l   k_tsbbr_a, r0 ; mov.l v_tsbbr, r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= THE FAULTING LOAD (straight-line) =================
        ! r0 = VA (bank-0; preserved across the bank-1 handler). r8 = dest.
        mov.l   va_A, r0
        mov     #0, r8                 ! poison dest so a missed load is visible
#if AINC_DISP_CONTROL
        ! Control: idempotent displacement load. Rm rides we_wb (squashed) and
        ! the base register is NOT modified by displacement addressing, so r0
        ! must remain VA and r8 the seed even on the buggy core. (No trailing
        ! `add` here: a trailing EX-stage write would itself be replayed by the
        ! imprecise restart -- a separate manifestation of the same leak.)
        mov.l   @(0,r0), r8
#else
        ! Defect path: post-increment base update rides we_ex (NOT squashed).
        mov.l   @r0+, r8               ! <-- faults DMISS_R; restarts; r0 should be VA+4 once
#endif

        ! ---- Disable AT before touching the sim result register. ----
        mov.l   k_mmucr, r1 ; mov #0, r2 ; mov.l r2, @r1

        ! ================= VERIFY =================
#if AINC_DISP_CONTROL
        ! Control: base untouched by displacement addressing -> r0 == VA.
        mov.l   va_A, r1 ; cmp/eq r1, r0 ; mov #1, r9 ; bf _fail
#else
        ! Rn incremented exactly once: r0 == VA + 4.
        mov.l   va_A_p4, r1 ; cmp/eq r1, r0 ; mov #1, r9 ; bf _fail
#endif
        ! Rm holds the loaded value.
        mov.l   v_seedA, r1 ; cmp/eq r1, r8 ; mov #2, r9 ; bf _fail
        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear: .long 0xDFFFFFFF
k_pgd:     .long 0x80002000
k_pgd0:    .long 0x80002401
k_pteA:    .long 0x80002800
v_pteA:    .long 0x001000F1    ! identity PTE: PA(==VA) | flags 0x0F1 (W|X|U|D|V; bits[11:8]=0 → pm=0)
k_tsb:     .long 0x80002C00
k_bkA:     .long 0x00100000    ! identity backing == workload VA (seed direct, AT off)
v_seedA:   .long 0xA11C0001
k_vbr:     .long 0x80000000 + _vbase
k_tsbbr_a: .long 0xFF000014
v_tsbbr:   .long 0x80002C04
k_tsbcfg_a:.long 0xFF000018
v_tsbcfg:  .long 0x00000061
k_mmucr:   .long 0xFF000010
va_A:      .long 0x00100000
va_A_p4:   .long 0x00100004
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
        ! ===================== Exception vector base =====================
        ! VBR points at the P1 alias of _vbase; hardware adds 0x420 (load miss).
        .balign 4
_vbase:
        .space 0x400, 0
_v_tlb:                                 ! _vbase + 0x400  (all TLB faults)
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
        .word   0x0078                  ! LDTLB.RN  (install + return atomically)

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
H_pgd:    .long 0x80002000
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker runs untranslated
H_mmucr:  .long 0xFF000010
H_result: .long TEST_RESULT_ADDRESS
#endif
