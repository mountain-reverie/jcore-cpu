! mmuirun.S -- M7: run instructions from a TRANSLATED page through the
! runnable §4.2 handler. Kernel (code/handler/walker/PGD/PTE/TSB/counters)
! lives in P1 (untranslated). One P0 CODE page (VA 0x00100000, identity-backed
! at PA 0x00100000, PTE flags 0x0F1 incl. EXEC; bits[11:8]=0 → pm=0) holds a small workload that is
! COPIED there (AT off) before AT is enabled. With AT on, jmp to VA 0x00100000
! -> cold IMISS (VBR+0x400) -> handler publishes the I-PTE as a TSB row and
! RTEs -> the re-fetch misses again and the HARDWARE walker installs it -> workload runs (writes ran_flag) -> jmp back to P1.
! PASS proves execution RESUMED inside the translated page (ran_flag written by
! an instruction fetched through translation) and walker_calls==1.
!
! The warm-TSB re-fetches (after each TLB flush below) are now resolved by the
! HARDWARE TSB walker (core/tlb_walk.vhd) stalling-and-walking with no
! exception at all -- the §4.1 software hot path these used to exercise is
! unreachable by design once the walker is mandatory (it only runs from the
! miss-exception vector). This guard checks the walker's own cnt_hits counter
! (P4 counter word 0xFF000054, bits 15:0) instead of the software tsb_hits
! counter for that reason.
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   (PTEH 0xFF000000  PTEL 0xFF000004  TSBPTR 0xFF00001C  ASIDR 0xFF000038
!    are read through their read-only P4 aliases, not STC)
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL =0x406E    LDC r3,PTEL =0x436E
!   LDC r0,VBR    =0x402E
!
! Result codes (r9 at _fail): 1/10/12 leg sentinels, 11 mixed-leg data,
! 9 cnt_hits delta (total), 8 walker_calls, 7 unexpected walker fault,
! 13 SPC moved across the warm leg (an exception was taken where the hardware
! walker should have resolved the fetch), 14/16 the software hot path ran,
! 15 cnt_hits did not advance by 1 across the warm leg.
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS. Since the per-sub-test fail-code globals
! start at 0 until a sub-test sets them, a fault reaching _fail BEFORE the first
! sub-test runs would otherwise silently report PASS. _fail now clamps r9==0 to
! 0x7F before the store so 0 can never leave through the fail path. Fail-code
! globals below use loud sentinels (_g_exp_* = 0xFFFFFFFF, _g_bad_* = small
! distinct values) so an early exit still names its cause.
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
        mov.l   k_pteData, r0 ; mov.l v_pteData, r1 ; mov.l r1, @r0

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
        mov.l   k_bkData, r0 ; mov.l v_seedData, r1 ; mov.l r1, @r0  ! = 0xDA7A0003

        ! ---- Zero the ran_flags and walker_calls / tsb_hits counters and the
        ! mixed-leg scratch/result words. ----
        mov.l   k_ranf, r0 ; mov #0, r1 ; mov.l r1, @r0         ! ran_flag=0
        mov.l   k_ranf2, r0 ; mov #0, r1 ; mov.l r1, @r0        ! ran_flag2=0
        mov.l   k_ranf3, r0 ; mov #0, r1 ; mov.l r1, @r0        ! ran_flag3=0
        mov.l   k_wcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! walker_calls=0
        mov.l   k_hcnt, r0 ; mov #0, r1 ; mov.l r1, @r0         ! tsb_hits=0
        mov.l   k_scratch, r0 ; mov #0, r1 ; mov.l r1, @r0      ! scratch=0
        mov.l   k_mixedval, r0 ; mov #0, r1 ; mov.l r1, @r0     ! mixed_val=0

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
        mov.l   va_code, r0            ! 0x00100000
        jmp     @r0                    ! cold IMISS -> handler -> install -> resume
        nop

        ! If execution never resumes in the page, the stub's jmp-back never
        ! happens and we never reach _after_ifetch; the sim times out (RED).

ENTRY(_after_ifetch)
        ! ---- Snapshot the walker's cnt_hits (0xFF000054[15:0]) baseline
        ! ---- before the warm + mixed phases below: those two code refetches
        ! ---- must be served by the hardware walker now, not software. ----
        mov.l   k_walkcnt, r0 ; mov.l @r0, r13
        mov.l   k_mask16,  r1 ; and    r1, r13

        ! ---- Seed an SPC sentinel for the WARM leg's "no exception" assert.
        ! WHY THIS IS HERE (do not drop it): the MMU emits PA tags and does NOT
        ! relocate the instruction bus, and every page this guard maps is
        ! IDENTITY (VA 0x00100000 -> PA 0x00100000). An UNTRANSLATED fetch of
        ! the workload therefore returns the SAME instruction word as a
        ! translated one, so "the workload ran and wrote its sentinel" does not
        ! prove the fast path was taken. Measured: mutating cpu.vhd's
        ! `dp_inst_i.ack <= inst_i.ack and not walk_supp_i` to
        ! `dp_inst_i.ack <= inst_i.ack` -- which makes the fetch complete
        ! untranslated and take a spurious IMISS exception instead of a
        ! hardware walk -- left this guard GREEN on every check it had.
        ! Only "no exception was taken" catches an inert/bypassed walker
        ! (same lesson as mmuwalkiside.S's Result=2). SPC is written by
        ! exception entry and by nothing else, so a surviving sentinel is that
        ! proof. Checked at _after_ifetch2 as code 13.
        mov.l   v_sent_spc, r0
        .word   0x404E                 ! LDC r0, SPC

        ! Cold leg resumed inside the translated page (proves the translated
        ! fetch ran). Keep AT ON. Re-arm the stub for a SECOND invocation by
        ! re-pointing its control block at ran_flag2 / sentinel2 /
        ! _after_ifetch2, then flush the TLB (TI|AT) leaving the TSB warm and
        ! re-jump into the page. The second IMISS is resolved by the HARDWARE
        ! walker stalling-and-walking against the warm TSB (cnt_hits++), with
        ! no exception and no software §4.1 hot path involvement.
        mov.l   k_ranf2, r0 ; mov #0, r1 ; mov.l r1, @r0        ! ran_flag2 = 0
        mov.l   k_ctl0, r0
        mov.l   k_ranf2, r1 ; mov.l r1, @r0                     ! ctl[0] = ran_flag2
        mov.l   v_sent2, r1 ; mov.l r1, @(4,r0)                ! ctl[1] = sentinel2
        mov.l   k_scratch, r1 ; mov.l r1, @(8,r0)             ! ctl[2] = data_src=scratch
        mov.l   k_scratch, r1 ; mov.l r1, @(12,r0)            ! ctl[3] = result=scratch
        mov.l   p_after2, r1 ; mov.l r1, @(16,r0)             ! ctl[4] = _after_ifetch2
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0        ! flush TLB, AT+TSB warm
        mov.l   va_code, r0
        jmp     @r0                                            ! warm IMISS -> hot path
        nop

ENTRY(_after_ifetch2)
        ! ---- 13: SPC still holds the sentinel seeded before the warm jmp, so
        ! the warm code-page fetch entered NO exception vector at all -- it was
        ! resolved by the hardware walker stalling and walking. This is the
        ! anti-vacuity assert for the whole I-side fast path; see the seeding
        ! site above for why the sentinel checks are load-bearing.
        .word   0x0042                 ! STC SPC, r0
        mov.l   v_sent_spc, r1
        cmp/eq  r0, r1 ; mov #13, r9 ; bf _fail

        ! ---- 14: the SOFTWARE §4.1 hot path in the vector did not run either
        ! (it is the only writer of tsb_hits). Independent of 13: 13 would also
        ! be satisfied by an exception that somehow left SPC alone.
        mov.l   k_hcnt, r0 ; mov.l @r0, r2
        tst     r2, r2 ; mov #14, r9 ; bf _fail

        ! ---- 15: and the walker's OWN cnt_hits advanced by exactly 2 for the
        ! warm fetch -- the positive half, so 13/14 cannot pass by the fetch
        ! never happening.
        ! WHY 2 AND NOT 1 (was 1 before the ITLB/DTLB split): the ITLB and the
        ! DTLB are separate arrays, so the code page needs an entry in EACH.
        ! The TI flush before the warm jmp empties both; the jmp takes an I-miss
        ! walked into the ITLB (hit #1), and the stub's very first instruction
        ! is `mov.l 9f, r3` -- a PC-RELATIVE LOAD, i.e. a D-side access to that
        ! same code page -- which takes a D-miss walked into the DTLB (hit #2).
        ! Under the old unified TLB the I-side install served the literal load
        ! too. Both are warm TSB hits, which is what this check asserts.
        mov.l   k_walkcnt, r0 ; mov.l @r0, r2 ; mov.l k_mask16, r3 ; and r3, r2
        sub     r13, r2 ; mov #2, r3 ; cmp/eq r3, r2 ; mov #15, r9 ; bf _fail

        ! Warm leg resumed inside the page. Now run the MIXED I+D leg: re-arm the
        ! stub control block so its load reads a TRANSLATED data page
        ! (VA 0x00102000) and stores the value to mixed_val. Keep AT ON and flush
        ! the TLB (TI|AT, TSB warm) so the code-page fetch is a warm hardware-
        ! walker hit (cnt_hits++) while the never-touched data page is a cold
        ! DMISS_R that goes to the walker (walker_calls++). The stub's load instruction is thus
        ! fetched through the I-TLB and has its operand fetched through the D-TLB.
        mov.l   k_ranf3, r0 ; mov #0, r1 ; mov.l r1, @r0        ! ran_flag3 = 0
        mov.l   k_mixedval, r0 ; mov #0, r1 ; mov.l r1, @r0     ! mixed_val = 0
        mov.l   k_ctl0, r0
        mov.l   k_ranf3, r1 ; mov.l r1, @r0                     ! ctl[0] = ran_flag3
        mov.l   v_sent3, r1 ; mov.l r1, @(4,r0)                ! ctl[1] = sentinel3
        mov.l   va_data, r1 ; mov.l r1, @(8,r0)               ! ctl[2] = data_src=VA 0x00102000
        mov.l   k_mixedval, r1 ; mov.l r1, @(12,r0)            ! ctl[3] = result=mixed_val
        mov.l   p_after3, r1 ; mov.l r1, @(16,r0)             ! ctl[4] = _after_ifetch3
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0        ! flush TLB, AT+TSB warm
        mov.l   va_code, r0
        jmp     @r0                                            ! mixed: IMISS (hot) + DMISS_R (walker)
        nop

ENTRY(_after_ifetch3)
        ! Mixed leg resumed inside the page. Disable AT, then verify all legs.
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! Cold sentinel still present (cold-leg assert, preserved).
        mov.l   k_ranf, r0 ; mov.l @r0, r2
        mov.l   v_sentinel, r3 ; cmp/eq r3, r2 ; mov #1, r9 ; bf _fail

        ! Warm sentinel still present (warm-leg assert, preserved).
        mov.l   k_ranf2, r0 ; mov.l @r0, r2
        mov.l   v_sent2, r3 ; cmp/eq r3, r2 ; mov #10, r9 ; bf _fail

        ! Mixed sentinel: the stub was I-fetched through translation a 3rd time.
        mov.l   k_ranf3, r0 ; mov.l @r0, r2
        mov.l   v_sent3, r3 ; cmp/eq r3, r2 ; mov #12, r9 ; bf _fail

        ! Mixed data: the translated LOAD read the seeded data page (0xDA7A0003).
        mov.l   k_mixedval, r0 ; mov.l @r0, r2
        mov.l   v_seedData, r3 ; cmp/eq r3, r2 ; mov #11, r9 ; bf _fail

        ! Walker cnt_hits advanced by exactly 5 over the warm + mixed legs,
        ! proving the hardware walker -- not software -- served them. Two per
        ! leg since the ITLB/DTLB split: each leg's TI flush empties both
        ! arrays, so the code page is walked once for the I-fetch and once for
        ! the stub's PC-relative literal load (see check 15). It was 2 under the
        ! unified TLB. The mixed leg's translated data page at 0x00102000 is a
        ! cold TSB MISS and so contributes to walker_calls (check 8) -- and,
        ! since retire-LDTLB, to ONE hit here as well: the handler no longer
        ! installs, it writes the TSB row and RTEs, so the re-executed load
        ! misses the TLB a second time and the hardware walker resolves it from
        ! the row just written. 4 warm-leg hits + that 1 resume hit = 5. This is
        ! MEASURED, not assumed: leaving the constant at 4 fails with result 9.
        mov.l   k_walkcnt, r0 ; mov.l @r0, r2 ; mov.l k_mask16, r3 ; and r3, r2
        sub     r13, r2 ; mov #5, r3 ; cmp/eq r3, r2 ; mov #9, r9 ; bf _fail

        ! walker_calls == 2 (cold code fetch + mixed cold data load).
        mov.l   k_wcnt, r0 ; mov.l @r0, r2 ; mov #2, r3 ; cmp/eq r3, r2 ; mov #8, r9 ; bf _fail

        ! ---- 16: the software §4.1 hot path ran for NO leg. The mixed leg's
        ! cold data DMISS_R does enter the vector, but it misses the TSB and
        ! falls through to _h_slow (walker_calls, checked above), so tsb_hits
        ! must still be 0 for the whole test. Any code fetch that took an
        ! exception instead of being walked would land on the hot path and
        ! bump it.
        mov.l   k_hcnt, r0 ; mov.l @r0, r2 ; tst r2, r2 ; mov #16, r9 ; bf _fail

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
k_pteData: .long 0x80002808           ! PTE table[idx(0x00102000)=0x102] = 0x80002400+0x408
v_pteData: .long 0x001020F1           ! identity PTE for data page (same flags; bits[11:8]=0 → pm=0)
k_bkData:  .long 0x00102000           ! identity backing == data VA (seed direct, AT off)
v_seedData:.long 0xDA7A0003           ! seed for the mixed-leg translated load
va_data:   .long 0x00102000           ! mixed-leg load VA (translated when AT on)
k_tsb:     .long 0x80002C00
k_img:     .long 0x80000000 + u_code_img
k_imgend:  .long 0x80000000 + u_code_end
k_bk:      .long 0x00100000           ! identity backing == workload VA (copy direct, AT off)
k_ranf:    .long 0x80002E08
k_ranf2:   .long 0x80002E0C
k_ranf3:   .long 0x80002E2C
v_sentinel:.long 0xC0DE0001
v_sent2:   .long 0xC0DE0002
v_sent3:   .long 0xC0DE0003
v_sent_spc:.long 0xDEADBE10           ! SPC "no exception was taken" sentinel
k_ctl0:    .long 0x80002E10           ! stub control block {flag,sent,src,res,ret} (E10..E20)
k_scratch: .long 0x80002E28           ! P1 scratch (cold/warm legs' load+store target)
k_mixedval:.long 0x80002E24           ! mixed-leg translated-load result
p_after:   .long 0x80000000 + _after_ifetch
p_after2:  .long 0x80000000 + _after_ifetch2
p_after3:  .long 0x80000000 + _after_ifetch3
k_wcnt:    .long 0x80010D00   ! must match WALKER_CALLS in tlbwalk.c
k_hcnt:    .long 0x80002E04
k_walkcnt: .long 0xFF000054   ! P4 walker counters: [31:16]=cnt_walks [15:0]=cnt_hits
k_mask16:  .long 0x0000FFFF
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
        .space 0x400, 0
_v_tlb:                                 ! _vbase + 0x400  (all TLB faults)
        bra     _h_common
        nop

        ! ---- §4.1 hot path (bank-1 scratch; AT stays ON). ----
_h_common:
        mov.l   H_tsbptr_a, r0
        mov.l   @r0, r0                 ! r0 = TSBPTR (P4 alias)
        mov.l   @r0+, r1                ! tag_hi (expected VPN)
        mov.l   H_pteh_a, r2
        mov.l   @r2, r2                 ! r2 = PTEH (P4 alias)
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @r0+, r1                ! tag_lo (expected ASID_TAG)
        mov.l   H_asidr_a, r2
        mov.l   @r2, r2                 ! r2 = ASIDR (P4 alias)
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @r0, r3                 ! TTE Data (PTEL image)
        ! tsb_hits++
        mov.l   H_hcnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4
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
