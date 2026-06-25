! mmuirun.S -- M7: run instructions from a TRANSLATED page through the
! runnable §4.2 handler. Kernel (code/handler/walker/PGD/PTE/TSB/counters)
! lives in P1 (untranslated). One P0 CODE page (VA 0x00100000, identity-backed
! at PA 0x00100000, PTE flags 0x3F1 incl. EXEC) holds a small workload that is
! COPIED there (AT off) before AT is enabled. With AT on, jmp to VA 0x00100000
! -> cold IMISS (VBR+0x400) -> walker installs I-PTE -> LDTLB.R re-fetches the
! faulting instruction -> workload runs (writes ran_flag) -> jmp back to P1.
! PASS proves execution RESUMED inside the translated page (ran_flag written by
! an instruction fetched through translation) and walker_calls==1.
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC TSBPTR,r0 =0x0043   STC PTEH,r2 =0x0253   STC ASIDR,r2 =0x0273
!   STC PTEH,r5   =0x0553   STC TSBPTR,r6=0x0643
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E    LDC r3,PTEL =0x436E
!   LDC r0,VBR    =0x402E   LDTLB.R     =0x0068

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

        ! ---- Initialise PR (slow-path handler does sts.l pr,@-r15). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- ASIDR = 0 (single context; tag_lo expected 0). ----
        mov     #0, r0
        .word   0x407E                 ! LDC r0, ASIDR

        ! ---- Build PGD[0] -> PTE table (P1 ptr, present). ----
        mov.l   k_pgd,  r0             ! 0x80002000
        mov.l   k_pgd0, r1             ! 0x80002401
        mov.l   r1, @r0

        ! ---- Build the one code PTE (PTEL image: PA | 0x3F1 incl. EXEC). ----
        mov.l   k_pte, r0 ; mov.l v_pte, r1 ; mov.l r1, @r0

        ! ---- Zero the 16-entry TSB (64 words). ----
        mov.l   k_tsb,  r0             ! 0x80002C00
        mov     #64, r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Copy the user-code stub into the backing page (AT off). The stub
        ! is assembled in P1 (u_code_img..u_code_end) with a PC-relative literal
        ! pool; PC-relative refs are position-independent so verbatim word copy
        ! into PA 0x00100000 keeps them resolving inside the same 4KB page. ----
        mov.l   k_img,    r2          ! src = P1 alias of u_code_img
        mov.l   k_imgend, r3          ! end
        mov.l   k_bk,     r4          ! dst = 0x00100000 (RAM backing, AT off)
2:      mov.l   @r2+, r1
        mov.l   r1, @r4
        add     #4, r4
        cmp/hs  r3, r2                ! T if r2 >= end
        bf      2b

        ! ---- Zero the ran_flag and walker_calls / tsb_hits counters. ----
        mov.l   k_ranf, r0 ; mov #0, r1 ; mov.l r1, @r0         ! ran_flag=0
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

        ! ================= COLD IMISS: run instructions from the page =========
        mov.l   va_code, r0            ! 0x00100000
        jmp     @r0                    ! cold IMISS -> handler -> install -> resume
        nop

        ! If execution never resumes in the page, the stub's jmp-back never
        ! happens and we never reach _after_ifetch; the sim times out (RED).

ENTRY(_after_ifetch)
        ! Reached by the stub's jmp back into P1 -- proves the translated fetch
        ! ran. Disable AT, then verify.
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ran_flag must equal the sentinel the resumed instruction wrote.
        mov.l   k_ranf, r0 ; mov.l @r0, r2
        mov.l   v_sentinel, r3 ; cmp/eq r3, r2 ; mov #1, r9 ; bf _fail

        ! walker_calls must be exactly 1 (single cold touch).
        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #1, r3 ; cmp/eq r3, r2 ; mov #8, r9 ; bf _fail

        mov     #0, r9
        bra     _done
        nop

        ! ---- User-code stub image (assembled in P1, COPIED to PA 0x00100000). ----
        ! mov.l ranf,r0 ; mov.l sent,r1 ; mov.l r1,@r0 ; mov.l back,r0 ; jmp @r0
        .balign 4
u_code_img:
        mov.l   3f, r0                 ! r0 = 0x80002D08 (P1 ran_flag)
        mov.l   4f, r1                 ! r1 = 0xC0DE0001 (sentinel)
        mov.l   r1, @r0                ! write sentinel  (this instr proves I-fetch ran)
        mov.l   5f, r0                 ! r0 = 0x80000000 + _after_ifetch
        jmp     @r0                    ! return to P1 kernel
        nop
        .align 2
3:      .long   0x80002D08
4:      .long   0xC0DE0001
5:      .long   0x80000000 + _after_ifetch
u_code_end:

        .align 2
p_rbclear: .long 0xDFFFFFFF
k_pgd:     .long 0x80002000
k_pgd0:    .long 0x80002401
k_pte:     .long 0x80002800           ! PTE table[idx(0x00100000)=0x100] = 0x80002400+0x400
v_pte:     .long 0x001003F1           ! identity PTE: PA(==VA) | flags 0x3F1 (incl EXEC)
k_tsb:     .long 0x80002C00
k_img:     .long 0x80000000 + u_code_img
k_imgend:  .long 0x80000000 + u_code_end
k_bk:      .long 0x00100000           ! identity backing == workload VA (copy direct, AT off)
k_ranf:    .long 0x80002D08
v_sentinel:.long 0xC0DE0001
k_wcnt:    .long 0x80002D00
k_hcnt:    .long 0x80002D04
k_vbr:     .long 0x80000000 + _vbase
k_tsbbr_a: .long 0xFF000014
v_tsbbr:   .long 0x80002C04
k_tsbcfg_a:.long 0xFF000018
v_tsbcfg:  .long 0x00000061
k_mmucr:   .long 0xFF000010
va_code:   .long 0x00100000
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
        ! VBR points at the P1 alias of _vbase; hardware adds 0x400 (inst miss),
        ! 0x420 (load miss) or 0x440 (store miss). All stubs branch to the
        ! shared hot path.
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
        ! tsb_hits++
        mov.l   H_hcnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4
        .word   0x436E                  ! LDC r3, PTEL
        .word   0x0068                  ! LDTLB.R  (install + return atomically)
        nop                             ! delay slot

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
        .word   0x0068                  ! LDTLB.R
        nop

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
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker runs untranslated
H_mmucr:  .long 0xFF000010
H_result: .long TEST_RESULT_ADDRESS
#endif
