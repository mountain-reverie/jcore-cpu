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
! This guard removes the estimate: its handler is inlined AT the vector with no
! taken branch on a hit, no counter, and a tight register discipline (r0/r1/r3
! only; r2 untouched), so sim/bench_tlb_hotpath.sh measures the miss cost and
! nothing else.
!
! NOTE: this handler was once a byte-faithful copy of linux@jcore's
! JCORE_TLB_FASTPATH, and the bench refused to report numbers unless it still
! matched. That software fast path no longer exists -- the hardware TSB walker
! replaced it -- so the mirrors-Linux claim and its fidelity gate are retired.
! What remains measurable, and what this guard is for, is the walker's own
! cycle cost (sim/bench_tlb_hotpath.sh, walker-ON vs walker-OFF).
!
! The workload is mmurun's, unchanged: four P0 pages, first touch faults to the
! C walker (cold TSB), then MMUCR.TI evicts the TLB while the TSB stays warm so
! the second touch exercises the asm fast path.
!
! HOW THE WARM PATH IS PROVEN TO HAVE BEEN SERVED WITHOUT SOFTWARE (no counter
! to assert on): walker_calls must equal 4, not 8. Eight would mean the second
! round of touches re-entered the C walker -- i.e. the warm TSB was not used.
! Combined with the four data readbacks (two of them written by resumed
! stores), that pins the same behaviour the counter used to, without
! perturbing the thing being measured.
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   (PTEH 0xFF000000  PTEL 0xFF000004  TSBPTR 0xFF00001C  ASIDR 0xFF000038
!    are read through their read-only P4 aliases, not STC)
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E
!   LDC r0,VBR    =0x402E
!
! ---- walker-install version (retire-LDTLB) --------------------------------
! This guard's handler no longer installs a TLB entry. There is no software
! install instruction left; the HARDWARE walker (core/tlb_walk.vhd) is the sole
! installer. What changed inside the §4.2 handler, and nothing else:
!
!   * SLOW PATH: the C walker (tests/tlbwalk.c) already wrote the TSB row for
!     the faulting VPN -- that was always its job. It now ends in a plain `rte`
!     instead of `LDC PTEL / LDTLB.RN`. The faulting access re-executes, misses
!     the TLB again, and this time the hardware walker finds the row the C
!     walker just wrote and installs it. Same fault -> service -> resume path,
!     reached the only way it can now be reached.
!   * FAST PATH (§4.1): retired, and PROVABLY DEAD rather than merely unused. A
!     TLB-miss exception is delivered only AFTER the hardware walker probed the
!     TSB and missed, so a matching TSB row cannot be sitting here. The tag
!     compares are kept and turned into that assertion: a match now writes
!     TEST_RESULT = 29 instead of installing. STRONGER -- the old code would
!     have silently installed and hidden a walker that skipped a live row.
!
! Everything the guard actually asserts is unchanged.
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
        shll    r2                      ! 2-way sets: 32 B/set => 128 words
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

        ! _vbase + 0x400 -- ALL TLB faults. The fast path is INLINED HERE:
        ! hardware lands on the first instruction and, before retire-LDTLB, a TSB
        ! hit ran straight to LDTLB.RN with NO taken branch. The path is kept
        ! inline (and its tag compares turned into an assertion -- see below) so
        ! the benchmark still measures the same window. `_h_common` is an alias for the
        ! vector itself so sim/bench_tlb_hotpath.sh can bracket the path with
        ! the same [_h_common, _h_slow) symbol pair it uses for mmurun.
_v_tlb:
_h_common:
        mov.l   H_tsbptr_a, r0
        mov.l   @r0, r0                 ! r0 = TSBPTR (P4 alias)
        mov.l   @r0+, r1                !          r1 = tag_hi (expected VPN)
        mov.l   H_pteh_a, r2
        mov.l   @r2, r2                 ! r2 = PTEH (P4 alias)
        cmp/eq  r1, r2          ! tag_hi vs PTEH
        bf      _h_slow
        mov.l   @r0+, r1                !          r1 = tag_lo (expected ASID_TAG)
        mov.l   @r0, r3                 !          r3 = TTE data (PTEL); load-use
                                        !          latency hides behind the ASID
                                        !          compare + bf below
        mov.l   H_asidr_a, r2
        mov.l   @r2, r2                 ! r2 = ASIDR (P4 alias)
        cmp/eq  r1, r2          ! tag_lo vs ASIDR
        bf      _h_slow
        ! ---- The software §4.1 fast path is RETIRED (retire-LDTLB): there is
        ! ---- no TLB-install instruction left, so it cannot install anything.
        ! ---- It is also PROVABLY DEAD: a TLB-miss exception is only delivered
        ! ---- after the HARDWARE walker (core/tlb_walk.vhd) probed the TSB and
        ! ---- MISSED, so a matching row cannot be here. The compares above are
        ! ---- kept and turned into that assertion -- if they DO match, the
        ! ---- walker skipped a row it should have used and this guard's whole
        ! ---- premise is broken. Result 29.
        bra     _h_tsbhit
        nop

        ! ---- Slow path: call the C walker. Must come IMMEDIATELY after the
        ! fast path, with NO alignment padding: sim/bench_tlb_hotpath.sh
        ! measures dwell as "PC within [_h_common, _h_slow)", so a pad word here
        ! lands inside the measured window. It was not merely dead space under
        ! the old software install either -- LDTLB.RN had no delay slot, so the PC
        ! parked on whatever followed it for the 4 cycles the install+redirect
        ! took, and a pad word absorbed those into the reported dwell. A `.balign 4` here previously made this guard
        ! report 21 cyc against mmubenchi's 17 for the SAME 11 instructions, and
        ! that phantom 4-cycle gap got written up as an unexplained I-vs-D
        ! microarchitectural difference. It was padding. Do not re-add it. ----
_h_slow:
        sts.l   pr, @-r15
        mov.l   H_pgd, r4               ! r4 = pgd (P1)
        mov.l   H_pteh_a, r5
        mov.l   @r5, r5                 ! r5 = PTEH (faulting page VA)
        mov.l   H_tsbptr_a, r6
        mov.l   @r6, r6                 ! r6 = TSBPTR (TSB slot ptr)
        mov.l   H_walk, r7
        jsr     @r7
         nop
        tst     r0, r0
        bt      _h_realfault            ! r0==0 -> walker fault
        lds.l   @r15+, pr
        ! ---- The C walker has written the TSB row. Plain RTE: the faulting
        ! ---- access re-executes, misses the TLB again, and this time the
        ! ---- HARDWARE walker finds the row and installs it. Same resume path,
        ! ---- reached the only way it can now be reached.
        rte
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

_h_tsbhit:
        ! Unreachable by construction -- see _h_common. Loud if it ever is.
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT
        mov.l   H_result, r0
        mov     #29, r1
        mov.l   r1, @r0                 ! TEST_RESULT = 29 (TSB row matched at
1:      bra     1b                      ! the miss vector: impossible)
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
H_pteh_a:   .long 0xFF000000
H_tsbptr_a: .long 0xFF00001C
H_asidr_a:  .long 0xFF000038
H_result: .long TEST_RESULT_ADDRESS
#endif
