! mmurun.S -- M6: runnable full §4.2 TLB-miss handler in ghdl.
!
! Kernel (code/stack/PGD/PTE/TSB/counters) lives in P1 (untranslated): the
! handler never faults and a TLB flush never evicts code. Four P0 pages are
! translated. First touch -> TLB miss + cold-TSB miss -> C walker installs into
! TSB+TLB (walker_calls++). MMUCR.TI flush evicts the TLB, TSB stays warm, so
! the second touch hits the §4.1 asm hot path (tsb_hits++). PASS requires
! walker_calls==4, tsb_hits==4, and all four data readbacks correct (two of
! them written by resumed stores -> proves the 0x440 store path end-to-end).
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC TSBPTR,r0 =0x0043   STC PTEH,r2 =0x0253   STC ASIDR,r2 =0x0273
!   STC PTEH,r5   =0x0553   STC TSBPTR,r6=0x0643
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E    LDC r3,PTEL =0x436E
!   LDC r0,VBR    =0x402E   LDTLB.RN     =0x0068

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

        ! ---- Initialise PR to a defined value. The slow-path handler does
        ! `sts.l pr,@-r15` on entry; on the very first fault PR is otherwise
        ! uninitialised, which the ghdl bus model rejects as an undefined-data
        ! store. The push/pop is balanced so the saved value is immaterial. ----
        mov     #0, r0
        lds     r0, pr

        ! ---- ASIDR = 0 (single context; tag_lo expected 0). ----
        mov     #0, r0
        .word   0x407E                 ! LDC r0, ASIDR

        ! ---- Build PGD[0] -> PTE table (P1 ptr, present). ----
        mov.l   k_pgd,  r0             ! 0x80002000
        mov.l   k_pgd0, r1             ! 0x80002401
        mov.l   r1, @r0

        ! ---- Build the four PTEs (PTEL images: backing PA | 0x3F1). ----
        mov.l   k_pteA, r0 ; mov.l v_pteA, r1 ; mov.l r1, @r0
        mov.l   k_pteB, r0 ; mov.l v_pteB, r1 ; mov.l r1, @r0
        mov.l   k_pteC, r0 ; mov.l v_pteC, r1 ; mov.l r1, @r0
        mov.l   k_pteD, r0 ; mov.l v_pteD, r1 ; mov.l r1, @r0

        ! ---- Zero the 16-entry TSB (64 words). ----
        mov.l   k_tsb,  r0             ! 0x80002C00
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed backing pages (loads) / clear store targets, zero counters. ----
        mov.l   k_bkA, r0 ; mov.l v_seedA, r1 ; mov.l r1, @r0   ! A = 0xA5A50001
        mov.l   k_bkC, r0 ; mov.l v_seedC, r1 ; mov.l r1, @r0   ! C = 0xA5A50003
        mov.l   k_bkB, r0 ; mov #0, r1        ; mov.l r1, @r0   ! B = 0
        mov.l   k_bkD, r0 ; mov #0, r1        ; mov.l r1, @r0   ! D = 0
        mov.l   k_wcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! walker_calls=0
        mov.l   k_hcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! tsb_hits=0

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                 ! LDC r0, VBR

        ! ---- TSB config registers via MMIO. ----
        mov.l   k_tsbbr_a, r0 ; mov.l v_tsbbr, r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= FIRST TOUCHES (4 walker installs) =================
        mov.l   va_A, r0 ; mov.l @r0, r8           ! A: load  -> 0x420
        mov.l   va_C, r0 ; mov.l @r0, r10          ! C: load  -> 0x420
        mov.l   va_B, r0 ; mov.l sv_B, r1 ; mov.l r1, @r0   ! B: store -> 0x440
        mov.l   va_D, r0 ; mov.l sv_D, r1 ; mov.l r1, @r0   ! D: store -> 0x440

        ! ---- Flush the TLB, keep AT on (TI|AT). TSB stays warm. ----
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0

        ! ================= SECOND TOUCHES (4 TSB hot-path hits) ==============
        mov.l   va_A, r0 ; mov.l @r0, r8           ! A: load (recheck seed)
        mov.l   va_B, r0 ; mov.l @r0, r12          ! B: load -- r12, NOT r9: the verify reuses r9 as its fail-code register (mov #1,r9 on the A line below), which would clobber the B readback before line 127 compares it
        mov.l   va_C, r0 ; mov.l @r0, r10          ! C: load
        mov.l   va_D, r0 ; mov.l @r0, r11          ! D: load (read back store)

        ! ---- Disable AT before touching the sim result register. ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ================= VERIFY =================
        mov.l   v_seedA, r1 ; cmp/eq r1, r8  ; mov #1, r9 ; bf _fail
        mov.l   sv_B,    r1 ; cmp/eq r1, r12 ; mov #2, r9 ; bf _fail  ! r12 holds B readback
        mov.l   v_seedC, r1 ; cmp/eq r1, r10 ; mov #3, r9 ; bf _fail
        mov.l   sv_D,    r1 ; cmp/eq r1, r11 ; mov #4, r9 ; bf _fail
        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #4, r3 ; cmp/eq r3, r2 ; mov #5, r9 ; bf _fail
        mov.l   k_hcnt, r0 ; mov.l @r0, r2 ; mov #4, r3 ; cmp/eq r3, r2 ; mov #6, r9 ; bf _fail
        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear: .long 0xDFFFFFFF
k_pgd:     .long 0x80002000
k_pgd0:    .long 0x80002401
k_pteA:    .long 0x80002800
k_pteB:    .long 0x80002804
k_pteC:    .long 0x80002808
k_pteD:    .long 0x8000280C
v_pteA:    .long 0x001003F1    ! identity PTE: PA(==VA) | flags 0x3F1
v_pteB:    .long 0x001013F1
v_pteC:    .long 0x001023F1
v_pteD:    .long 0x001033F1
k_tsb:     .long 0x80002C00
k_bkA:     .long 0x00100000    ! identity backing == workload VA (seed direct, AT off)
k_bkB:     .long 0x00101000
k_bkC:     .long 0x00102000
k_bkD:     .long 0x00103000
v_seedA:   .long 0xA5A50001
v_seedC:   .long 0xA5A50003
sv_B:      .long 0x5B5B0002
sv_D:      .long 0x5B5B0004
k_wcnt:    .long 0x80002D00
k_hcnt:    .long 0x80002D04
k_vbr:     .long 0x80000000 + _vbase
k_tsbbr_a: .long 0xFF000014
v_tsbbr:   .long 0x80002C04
k_tsbcfg_a:.long 0xFF000018
v_tsbcfg:  .long 0x00000061
k_mmucr:   .long 0xFF000010
va_A:      .long 0x00100000
va_B:      .long 0x00101000
va_C:      .long 0x00102000
va_D:      .long 0x00103000
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
        ! VBR points at the P1 alias of _vbase; hardware adds 0x420 (load miss)
        ! or 0x440 (store miss). Both stubs branch to the shared hot path.
        .balign 4
_vbase:
        .space 0x420, 0
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
        ! tsb_hits++
        mov.l   H_hcnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4
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
H_hcnt:   .long 0x80002D04
H_pgd:    .long 0x80002000
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker must run untranslated (AT on during handler)
H_mmucr:  .long 0xFF000010
H_result: .long TEST_RESULT_ADDRESS
#endif
