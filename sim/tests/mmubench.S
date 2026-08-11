! mmubench.S -- TLB-miss hot-path BENCHMARK guard.
!
! WHY THIS EXISTS SEPARATELY FROM mmurun.S.
! mmurun is a correctness guard: its PASS criteria include tsb_hits==4, so its
! hot path carries a `tsb_hits++` counter (2 loads + add + store) and reaches
! the handler through a `bra _h_common` stub. Neither exists in the real Linux
! handler, so every cycle number taken from mmurun had to be corrected by a
! hand-estimated "net out ~7 cycles of counter and ~3 of branch" -- an estimate
! standing between the measurement and the number anyone actually cares about.
!
! This guard removes the estimate. Its handler is a BYTE-FAITHFUL copy of
! linux@jcore's JCORE_TLB_FASTPATH (arch/sh/kernel/cpu/jcore/ex.S): 9
! instructions, inlined AT the vector with no taken branch on a hit, no
! counter, same register discipline (r0/r1/r3 only; r2 untouched). What
! sim/bench_tlb_hotpath.sh measures here is the production cost directly.
!
! The workload is mmurun's, unchanged: four P0 pages, first touch faults to the
! C walker (cold TSB), then MMUCR.TI evicts the TLB while the TSB stays warm so
! the second touch exercises the asm fast path.
!
! HOW THE FAST PATH IS PROVEN TO HAVE RUN (no counter to assert on):
! walker_calls must equal 4, not 8. Eight would mean the second round of
! touches fell through to the C walker again -- i.e. the fast path never took
! its hit. Combined with the four data readbacks (two of them written by
! resumed stores), that pins the same behaviour the counter used to, without
! perturbing the thing being measured.
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC TSBPTR,r0 =0x004B   STC PTEH,r5 =0x058B   STC TSBPTR,r6=0x064B
!   CMP/EQ PTEH,r1=0x01CB   CMP/EQ ASIDR,r1=0x01DB
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E
!   LDC r0,VBR    =0x402E   LDTLB.RN     =0x0078   LDTLB.RN r3 =0x03FB
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
        mov.l   p_sp,   r15
        mov.l   p_kmain, r0
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

        ! ---- Initialise PR (the slow path pushes it on entry). ----
        mov     #0, r0
        lds     r0, pr

        ! ---- ASIDR = 0 (single context; tag_lo expected 0). ----
        mov     #0, r0
        .word   0x407E                 ! LDC r0, ASIDR

        ! ---- Build PGD[0] -> PTE table (P1 ptr, present). ----
        mov.l   k_pgd,  r0
        mov.l   k_pgd0, r1
        mov.l   r1, @r0

        ! ---- Build the four PTEs (PTEL images: backing PA | 0x0F1). ----
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

        ! ---- Seed backing pages / clear store targets, zero the counter. ----
        mov.l   k_bkA, r0 ; mov.l v_seedA, r1 ; mov.l r1, @r0
        mov.l   k_bkC, r0 ; mov.l v_seedC, r1 ; mov.l r1, @r0
        mov.l   k_bkB, r0 ; mov #0, r1        ; mov.l r1, @r0
        mov.l   k_bkD, r0 ; mov #0, r1        ; mov.l r1, @r0
        mov.l   k_wcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! walker_calls=0

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                 ! LDC r0, VBR

        ! ---- TSB config registers via MMIO. ----
        mov.l   k_tsbbr_a, r0 ; mov.l v_tsbbr, r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= FIRST TOUCHES (4 walker installs) =================
! Phase brackets for sim/bench_tlb_hotpath.sh (labels only; no code emitted).
ENTRY(_bench_cold_start)
        mov.l   va_A, r0 ; mov.l @r0, r8
        mov.l   va_C, r0 ; mov.l @r0, r10
        mov.l   va_B, r0 ; mov.l sv_B, r1 ; mov.l r1, @r0
        mov.l   va_D, r0 ; mov.l sv_D, r1 ; mov.l r1, @r0

ENTRY(_bench_cold_end)
        ! ---- Flush the TLB, keep AT on (TI|AT). TSB stays warm. ----
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0

ENTRY(_bench_warm_start)
        ! ================= SECOND TOUCHES (4 TSB hot-path hits) ==============
        ! B is a STORE on purpose, so the hit set covers DMISS_W (EXPEVT
        ! 0x080) and not just DMISS_R (0x060). It also proves stores reach the
        ! MISS vector: since the miss/protection vector split, a store landing
        ! at VBR+0x100 instead of VBR+0x400 would mean the fault classifier put
        ! a write miss on the protection side (result 8). Do not make it a load.
        mov.l   va_A, r0 ; mov.l @r0, r8
        mov.l   va_B, r0 ; mov.l sv_B2, r1 ; mov.l r1, @r0   ! store -> DMISS_W 0x080
        mov.l   va_C, r0 ; mov.l @r0, r10
        mov.l   va_D, r0 ; mov.l @r0, r11
        mov.l   va_B, r0 ; mov.l @r0, r12                    ! read back (TLB now warm)

ENTRY(_bench_warm_end)
        ! ---- Disable AT before touching the sim result register. ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ================= VERIFY =================
        mov.l   v_seedA, r1 ; cmp/eq r1, r8  ; mov #1, r9 ; bf _fail
        mov.l   sv_B2,   r1 ; cmp/eq r1, r12 ; mov #2, r9 ; bf _fail
        mov.l   v_seedC, r1 ; cmp/eq r1, r10 ; mov #3, r9 ; bf _fail
        mov.l   sv_D,    r1 ; cmp/eq r1, r11 ; mov #4, r9 ; bf _fail
        ! walker_calls==4 is the fast-path proof: 8 would mean the second round
        ! of touches missed the TSB and re-entered the C walker.
        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #4, r3 ; cmp/eq r3, r2 ; mov #5, r9 ; bf _fail
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
v_pteA:    .long 0x001000F1
v_pteB:    .long 0x001010F1
v_pteC:    .long 0x001020F1
v_pteD:    .long 0x001030F1
k_tsb:     .long 0x80002C00
k_bkA:     .long 0x00100000
k_bkB:     .long 0x00101000
k_bkC:     .long 0x00102000
k_bkD:     .long 0x00103000
v_seedA:   .long 0xA5A50001
v_seedC:   .long 0xA5A50003
sv_B:      .long 0x5B5B0002
sv_B2:     .long 0x5B5B0022   ! second-round store value (proves the DMISS_W fast-path hit landed)
sv_D:      .long 0x5B5B0004
k_wcnt:    .long 0x80010D00   ! must match WALKER_CALLS in tlbwalk.c
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
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ===================== Exception vector base =====================
        .balign 4
_vbase:
        ! VBR+0x100 -- general exceptions, which since the miss/protection
        ! vector split includes IPROT/DPROT_R/DPROT_W. This workload never
        ! takes one (all four PTEs are W|X|U|D|V), so arriving here is a
        ! defect. Distinct result code so it cannot be read as a walker fault.
        .org    _vbase + 0x100
_v_general:
        mov.l   HP_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT
        mov.l   HP_result, r0
        mov     #8, r1
        mov.l   r1, @r0                 ! TEST_RESULT = 8 (unexpected prot/general)
1:      bra     1b
        nop
        .align  2
HP_mmucr:  .long 0xFF000010
HP_result: .long TEST_RESULT_ADDRESS

        .org    _vbase + 0x400

        ! _vbase + 0x400 -- ALL TLB faults. The fast path is INLINED HERE,
        ! exactly as linux@jcore inlines JCORE_TLB_FASTPATH at its vector:
        ! hardware lands on the first instruction and a TSB hit runs straight
        ! to LDTLB.RN with NO taken branch. `_h_common` is an alias for the
        ! vector itself so sim/bench_tlb_hotpath.sh can bracket the path with
        ! the same [_h_common, _h_slow) symbol pair it uses for mmurun.
_v_tlb:
_h_common:
        .word   0x004B                  ! stc      tsbptr, r0
        mov.l   @r0+, r1                !          r1 = tag_hi (expected VPN)
        .word   0x01CB                  ! cmp/eq   pteh, r1
        bf      _h_slow
        mov.l   @r0+, r1                !          r1 = tag_lo (expected ASID_TAG)
        mov.l   @r0, r3                 !          r3 = TTE data (PTEL); load-use
                                        !          latency hides behind the ASID
                                        !          compare + bf below
        .word   0x01DB                  ! cmp/eq   asidr, r1
        bf      _h_slow
        .word   0x03FB                  ! ldtlb.rn r3  (PTEL<-r3; install + return)

        ! ---- Slow path: call the C walker. Must come IMMEDIATELY after the
        ! fast path, with NO alignment padding: sim/bench_tlb_hotpath.sh
        ! measures dwell as "PC within [_h_common, _h_slow)", so a pad word here
        ! lands inside the measured window. It is not merely dead space either --
        ! LDTLB.RN has no delay slot, so the PC parks on whatever follows it for
        ! the 4 cycles the install+redirect takes, and a pad word absorbs those
        ! into the reported dwell. A `.balign 4` here previously made this guard
        ! report 21 cyc against mmubenchi's 17 for the SAME 11 instructions, and
        ! that phantom 4-cycle gap got written up as an unexplained I-vs-D
        ! microarchitectural difference. It was padding. Do not re-add it. ----
_h_slow:
        sts.l   pr, @-r15
        mov.l   H_pgd, r4               ! r4 = pgd (P1)
        .word   0x058B                  ! STC PTEH, r5   (faulting page VA)
        .word   0x064B                  ! STC TSBPTR, r6 (TSB slot ptr)
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

        ! ---- (unreachable) protection-fault landing. Not reachable in this workload
        ! (all four PTEs are W|X|U|D|V), so reaching it is a defect, not a path
        ! to benchmark. Placed AFTER _h_slow so it stays outside the measured
        ! [_h_common, _h_slow) window. Distinct result code so it cannot be
        ! confused with a walker fault. ----
_h_prot:
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT
        mov.l   H_result, r0
        mov     #8, r1
        mov.l   r1, @r0                 ! TEST_RESULT = 8 (unexpected prot fault)
1:      bra     1b
        nop

        .align 2
H_pgd:    .long 0x80002000
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker must run untranslated
H_mmucr:  .long 0xFF000010
H_result: .long TEST_RESULT_ADDRESS
#endif
