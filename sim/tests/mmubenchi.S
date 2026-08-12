! mmubenchi.S -- I-SIDE TLB-miss hot-path BENCHMARK guard.
!
! The instruction-fetch twin of mmubench.S. Same vector-inlined fast path (no
! tsb_hits++ counter, no `bra` stub), but the faulting access is an I-FETCH
! rather than a data load/store, so sim/bench_tlb_hotpath.sh reports the IMISS
! fault->resume latency instead of the DMISS one.
!
! Derived from mmuirun.S, keeping only its cold and warm legs:
!   cold: jmp to VA 0x00100000 -> IMISS, empty TSB -> C walker installs
!   warm: MMUCR.TI flush (TSB stays warm) -> jmp again -> IMISS, TSB HIT
! mmuirun's third "mixed" leg is deliberately dropped: it adds a translated
! DMISS_R on top of the IMISS, which would put D-side visits in the same trace
! and make the I-side number unreadable.
!
! Fast-path proof without a counter: walker_calls must be 1, not 2. Two would
! mean the warm IMISS missed the TSB and re-entered the walker.
!
! Result codes (r9 at _fail): 1/10 leg sentinels, 8 walker_calls (also the
! unexpected-prot code written directly by the vector), 7 unexpected walker
! fault, 13 SPC moved across the warm leg (an exception was taken where the
! hardware walker should have resolved the fetch), 15 the walker's cnt_hits did
! not advance by exactly 2 across the warm leg (one walk per array since the
! ITLB/DTLB split -- see the check itself for why 2 and not 1).
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   (PTEH 0xFF000000  PTEL 0xFF000004  TSBPTR 0xFF00001C  ASIDR 0xFF000038
!    are read through their read-only P4 aliases, not STC)
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E
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
#if CONFIG_PRIV_ARCH
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

        ! ---- Build the one code PTE (PTEL image: PA | 0x0F1 incl. EXEC). ----
        mov.l   k_pte, r0 ; mov.l v_pte, r1 ; mov.l r1, @r0

        ! ---- Build the data PTE for the mixed-leg load page (VA 0x00102000). ----

        ! ---- Zero the 16-entry TSB (64 words). ----
        mov.l   k_tsb,  r0             ! 0x80002C00
        mov     #64, r2
        shll    r2                      ! 2-way sets: 32 B/set => 128 words
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

        ! ---- Seed the mixed-leg data backing page PA 0x00102000 (AT off). ----

        ! ---- Zero the ran_flags and walker_calls / tsb_hits counters and the
        ! mixed-leg scratch/result words. ----
        mov.l   k_ranf, r0 ; mov #0, r1 ; mov.l r1, @r0         ! ran_flag=0
        mov.l   k_ranf2, r0 ; mov #0, r1 ; mov.l r1, @r0        ! ran_flag2=0
        mov.l   k_wcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! walker_calls=0
        mov.l   k_hcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! tsb_hits=0
        mov.l   k_scratch, r0 ; mov #0, r1 ; mov.l r1, @r0      ! scratch=0

        ! ---- Init stub control block for the COLD leg:
        ! {ran_flag, sentinel1, data_src=scratch, result=scratch, _after_ifetch}.
        ! The stub always performs a load+store; the cold/warm legs point it at a
        ! safe P1 scratch word (untranslated, no D-miss). The mixed leg re-points
        ! data_src at the translated VA 0x00102000. ----
        mov.l   k_ctl0, r0
        mov.l   k_ranf, r1     ; mov.l r1, @r0                  ! ctl[0] = ran_flag
        mov.l   v_sentinel, r1 ; mov.l r1, @(4,r0)             ! ctl[1] = sentinel1
        mov.l   k_scratch, r1  ; mov.l r1, @(8,r0)             ! ctl[2] = data_src=scratch
        mov.l   k_scratch, r1  ; mov.l r1, @(12,r0)            ! ctl[3] = result=scratch
        mov.l   p_after, r1    ; mov.l r1, @(16,r0)            ! ctl[4] = _after_ifetch

        ! ---- VBR = P1 alias of the vector base. ----
        mov.l   k_vbr, r0
        .word   0x402E                 ! LDC r0, VBR

        ! ---- TSB config registers via MMIO. ----
        mov.l   k_tsbbr_a, r0 ; mov.l v_tsbbr, r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0

        ! ---- Enable AT. ----
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0

        ! ================= COLD IMISS: run instructions from the page =========
! Phase brackets for sim/bench_tlb_hotpath.sh (labels only; no code emitted).
ENTRY(_bench_cold_start)
        mov.l   va_code, r0            ! 0x00100000
        jmp     @r0                    ! cold IMISS -> handler -> install -> resume
        nop

        ! If execution never resumes in the page, the stub's jmp-back never
        ! happens and we never reach _after_ifetch; the sim times out (RED).

ENTRY(_after_ifetch)
        ! Cold leg resumed inside the translated page (proves the translated
        ! fetch ran). Keep AT ON. Re-arm the stub for a SECOND invocation by
        ! re-pointing its control block at ran_flag2 / sentinel2 /
        ! _after_ifetch2, then flush the TLB (TI|AT) leaving the TSB warm and
        ! re-jump into the page. The second IMISS must hit the §4.1 asm hot path
        ! (PTEH/ASIDR match against the warm TSB) -> tsb_hits++ and LDTLB.RN, with
        ! NO second walker call.
        mov.l   k_ranf2, r0 ; mov #0, r1 ; mov.l r1, @r0        ! ran_flag2 = 0
        mov.l   k_ctl0, r0
        mov.l   k_ranf2, r1 ; mov.l r1, @r0                     ! ctl[0] = ran_flag2
        mov.l   v_sent2, r1 ; mov.l r1, @(4,r0)                ! ctl[1] = sentinel2
        mov.l   k_scratch, r1 ; mov.l r1, @(8,r0)             ! ctl[2] = data_src=scratch
        mov.l   k_scratch, r1 ; mov.l r1, @(12,r0)            ! ctl[3] = result=scratch
        mov.l   p_after2, r1 ; mov.l r1, @(16,r0)             ! ctl[4] = _after_ifetch2
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0        ! flush TLB, AT+TSB warm

        ! ---- Anti-vacuity seeding for the warm leg (OUTSIDE the measured
        ! [_bench_warm_start, _after_ifetch2) window on purpose -- it must not
        ! perturb the number sim/bench_tlb_hotpath.sh reports).
        !
        ! WHY: the MMU emits PA tags and does NOT relocate the instruction bus,
        ! and this guard's workload page is IDENTITY-mapped (VA 0x00100000 ->
        ! PA 0x00100000). An UNTRANSLATED fetch returns the same instruction
        ! word as a translated one, so the sentinel/walker_calls checks below
        ! all hold even when the fetch bypasses translation entirely. Measured:
        ! mutating cpu.vhd's `dp_inst_i.ack <= inst_i.ack and not walk_supp_i'
        ! to `dp_inst_i.ack <= inst_i.ack' -- the fetch completes untranslated
        ! and takes a spurious IMISS instead of a hardware walk -- left this
        ! guard GREEN. Only "no exception was taken" catches that, the same
        ! lesson mmuwalkiside.S's Result=2 encodes.
        !
        ! SPC is written by exception entry and nothing else, so a surviving
        ! sentinel proves the warm IMISS was answered by the hardware walker.
        ! r13 snapshots the walker's own cnt_hits as the positive half.
        mov.l   k_walkcnt, r0 ; mov.l @r0, r13
        mov.l   k_mask16,  r1 ; and    r1, r13
        mov.l   v_sent_spc, r0
        .word   0x404E                 ! LDC r0, SPC
ENTRY(_bench_warm_start)
        mov.l   va_code, r0
        jmp     @r0                                            ! warm IMISS -> hot path
        nop

ENTRY(_after_ifetch2)
        ! Warm leg resumed inside the page: that second IMISS was a TSB HIT and
        ! ran the vector-inlined fast path. Disable AT and verify.
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ---- 13: SPC still holds the sentinel -> the warm code-page fetch
        ! entered NO exception vector; the hardware walker resolved it. See the
        ! seeding site above for why this is the only non-vacuous I-side check.
        .word   0x0042                 ! STC SPC, r0
        mov.l   v_sent_spc, r1
        cmp/eq  r0, r1 ; mov #13, r9 ; bf _fail

        ! ---- 15: the walker's own cnt_hits advanced by exactly 2 for that
        ! fetch -- the positive half, so 13 cannot pass by the fetch never
        ! happening at all.
        ! WHY 2 AND NOT 1 (was 1 before the ITLB/DTLB split): the ITLB and the
        ! DTLB are separate arrays, so the code page needs an entry in EACH.
        ! The warm leg's TI flush empties both; the jmp takes an I-miss walked
        ! into the ITLB (hit #1), and the stub's very first instruction is
        ! `mov.l 9f, r3` -- a PC-RELATIVE LOAD, i.e. a D-side access to the same
        ! code page -- which takes a D-miss walked into the DTLB (hit #2).
        ! Under the old unified TLB the I-side install served that literal load
        ! too, so one hit covered both. Both walks are warm TSB hits, which is
        ! precisely what this check is asserting.
        mov.l   k_walkcnt, r0 ; mov.l @r0, r2 ; mov.l k_mask16, r3 ; and r3, r2
        sub     r13, r2 ; mov #2, r3 ; cmp/eq r3, r2 ; mov #15, r9 ; bf _fail

        ! Cold sentinel still present.
        mov.l   k_ranf, r0 ; mov.l @r0, r2
        mov.l   v_sentinel, r3 ; cmp/eq r3, r2 ; mov #1, r9 ; bf _fail

        ! Warm sentinel: the stub was I-fetched through translation a 2nd time.
        mov.l   k_ranf2, r0 ; mov.l @r0, r2
        mov.l   v_sent2, r3 ; cmp/eq r3, r2 ; mov #10, r9 ; bf _fail

        ! walker_calls == 1 is the fast-path proof: 2 would mean the warm IMISS
        ! missed the TSB and re-entered the C walker instead of hitting.
        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #1, r3 ; cmp/eq r3, r2 ; mov #8, r9 ; bf _fail

        mov     #0, r9
        bra     _done
        nop

        ! ---- User-code stub image (assembled in P1, COPIED to PA 0x00100000). ----
        ! Re-runnable: instead of baked-in literals the stub indirects through a
        ! P1 control block {flag_addr, sentinel, return_addr}. The kernel patches
        ! that block between the cold and warm legs, so the SAME copied stub runs
        ! twice (cold: ran_flag/0xC0DE0001/_after_ifetch; warm: ran_flag2/
        ! 0xC0DE0002/_after_ifetch2) without re-copying. The literal it loads is
        ! an absolute P1 address, so the verbatim word-copy stays valid.
        ! Control block (5 words): {flag, sentinel, data_src, result, ret}. The
        ! stub writes the sentinel (proves the fetch translated), then LOADS from
        ! data_src and STORES the value to result (the load is the mixed-leg's
        ! translated D-access), then returns. Cold/warm legs point data_src at a
        ! P1 scratch word (untranslated); the mixed leg points it at the
        ! translated VA 0x00102000.
        !
        ! IMPORTANT: every ctl access uses DISPLACEMENT addressing @(disp,r3)
        ! (r3 constant), NOT post-increment @r3+. A DMISS_R on the translated
        ! load re-enters the workload at the instruction PRECEDING the faulting
        ! load (faulting_PC-2) and re-executes it; with a constant base every
        ! instruction is idempotent, so the re-run reloads the same data_src and
        ! the load then resolves correctly (this mirrors mmurun's robust
        ! `mov.l <lit>,r0 ; mov.l @r0,rX` pattern). A post-increment here would be
        ! re-run and corrupt the pointer.
        .balign 4
u_code_img:
        mov.l   9f, r3                 ! r3 = &ctl (P1 control block, constant)
        mov.l   @(0,r3), r0            ! r0 = target flag addr
        mov.l   @(4,r3), r1           ! r1 = sentinel value
        mov.l   r1, @r0                ! write sentinel  (this instr proves I-fetch ran)
        mov.l   @(8,r3), r5           ! r5 = data_src addr (idempotent setup)
        mov.l   @r5, r6               ! LOAD (mixed leg: operand fetched through D-TLB)
        mov.l   @(12,r3), r5          ! r5 = result addr
        mov.l   r6, @r5               ! store loaded value
        mov.l   @(16,r3), r0          ! r0 = return addr (P1)
        jmp     @r0                    ! return to P1 kernel
        nop
        .align 2
9:      .long   0x80002E10            ! P1 addr of ctl block {flag,sent,src,res,ret}
u_code_end:

        .align 2
p_rbclear: .long 0xDFFFFFFF
k_pgd:     .long 0x80002000
k_pgd0:    .long 0x80002401
k_pte:     .long 0x80002800           ! PTE table[idx(0x00100000)=0x100] = 0x80002400+0x400
v_pte:     .long 0x001000D1           ! identity PTE: PA(==VA) | flags 0x0D1 (U cleared: kernel code, SMEP)
k_tsb:     .long 0x80002C00
k_img:     .long 0x80000000 + u_code_img
k_imgend:  .long 0x80000000 + u_code_end
k_bk:      .long 0x00100000           ! identity backing == workload VA (copy direct, AT off)
k_ranf:    .long 0x80002E08
k_ranf2:   .long 0x80002E0C
v_sentinel:.long 0xC0DE0001
v_sent2:   .long 0xC0DE0002
v_sent_spc:.long 0xDEADBE10           ! SPC "no exception was taken" sentinel
k_walkcnt: .long 0xFF000054   ! P4 walker counters: [31:16]=cnt_walks [15:0]=cnt_hits
k_mask16:  .long 0x0000FFFF
k_ctl0:    .long 0x80002E10           ! stub control block {flag,sent,src,res,ret} (E10..E20)
k_scratch: .long 0x80002E28           ! P1 scratch (cold/warm legs' load+store target)
p_after:   .long 0x80000000 + _after_ifetch
p_after2:  .long 0x80000000 + _after_ifetch2
k_wcnt:    .long 0x80010D00   ! must match WALKER_CALLS in tlbwalk.c
k_hcnt:    .long 0x80002E04
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
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ===================== Exception vector base =====================
        ! VBR points at the P1 alias of _vbase; hardware adds 0x400 (inst miss),
        ! 0x420 (load miss) or 0x440 (store miss). All stubs branch to the
        ! shared hot path.
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
        ! _vbase + 0x400 -- ALL TLB faults. The fast path is INLINED HERE at
        ! the vector, and is byte-identical to sim/tests/mmubench.S's copy so
        ! the I-side and D-side numbers are comparable. `_h_common` aliases
        ! the vector so sim/bench_tlb_hotpath.sh can bracket [_h_common,_h_slow).
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
        mov.l   @r0, r3                 !          r3 = TTE data (PTEL)
        mov.l   H_asidr_a, r2
        mov.l   @r2, r2                 ! r2 = ASIDR (P4 alias)
        cmp/eq  r1, r2          ! tag_lo vs ASIDR
        bf      _h_slow
        .word   0x436E                  ! LDC r3, PTEL
        .word   0x0078                  ! LDTLB.RN (install + return)

        ! ---- Slow path: call the C walker. ----
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
        ! Protection fault on a TSB hit -- unreachable in this workload; placed
        ! after _h_slow so it stays outside the measured window.
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
H_hcnt:   .long 0x80002E04
H_pgd:    .long 0x80002000
H_walk:   .long 0x80000000 + ___jcore_tlb_walk  ! P1 alias: walker runs untranslated
H_mmucr:  .long 0xFF000010
H_pteh_a:   .long 0xFF000000
H_tsbptr_a: .long 0xFF00001C
H_asidr_a:  .long 0xFF000038
H_result: .long TEST_RESULT_ADDRESS
#endif
