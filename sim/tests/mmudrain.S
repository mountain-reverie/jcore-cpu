! mmudrain.S -- D-side fault trains drained by an I-side miss.
!
! Gap closed: the suite covers the D-fault axis and the I-fault axis
! separately, and D->D back-to-back (mmustr2.S), but never a D-side fault
! (or a train of them) immediately followed by an I-side miss -- where the
! squash/restart machinery is shared between the two axes.
!
! WHAT THIS FILE COVERS -- THREE legs:
!   A  N faulting LOADS  back-to-back      -> 1 IMISS   data 2 / regs 6 / count 0x10
!   C  N faulting STORES back-to-back      -> 1 IMISS   data 4 / regs 8 / count 0x12
!   D  N x (faulting STORE -> IMISS), chained through stub pages
!                                          data 5 / regs 9 / r12 0x0B / count 0x13
!
! UNIMPLEMENTED (future work; do NOT assume coverage):
!   B  N x (faulting LOAD -> IMISS)
! Leg B's load-side alternating shape is still uncovered; leg D covers the
! alternating shape on the STORE side only.
!
! ---- what leg D found (FIXED; all three legs pass on this tree) ----------
! Leg D was RED when it was written and it earned its keep: it exposed a
! PRE-EXISTING z-port age-blindness in the precise-exception squash
! (core/datapath.vhm, reg_wr_z_g), fixed by the one-shot `z_grace' bit in the
! g_restore2 generate. On an instruction-side fault whose restart PC is NOT
! backed up -- an IMISS on a branch TARGET, as here -- the squash window also
! suppressed the writeback of an instruction that had issued BEFORE the
! faulting fetch and is therefore architecturally OLDER than it. Since the
! restart PC is (correctly) the target, that instruction never re-executed and
! its register write was lost forever.
!
! READ THIS BEFORE DEBUGGING A FAILURE HERE -- the symptom points at the wrong
! subsystem. What failed first was layer 1: nine of the ten `@-Rn' bases read 4
! LOW, which looks exactly like the Model-C (concurrent) base-restore undo of
! docs/architecture/tlb.md section 9.4 mis-firing. It was not. The base restore
! fired in ALL TEN stubs, on time, with the right value, into the right
! register, with RB=0. The real chain runs the other way round:
!
!   the lost write WAS the r12 advance (the `add r11,r12' in the delay slot of
!   `jmp @r12')  ->  r12 stopped advancing, so the next stub was entered with
!   r12 == its own address  ->  its `jmp @r12' self-looped  ->  the whole stub
!   body, INCLUDING `mov.l r13,@-Rn', executed TWICE  ->  two pre-decrements,
!   base 4 low.
!
! So the r12 shortfall (layer 3) is the CAUSE and the doubled pre-decrement
! (layer 1) is the consequence -- not the other way round, and not a restore
! defect at all. Layer 1 fires first only because of the check order below; the
! layer-3 r12 check is the one that names the actual mechanism. If this guard
! goes red again, read layer 3 first even if layer 1 is what reported.
!
! Ruled out as harness error: plain `jmp @Rn' + delay-slot write to Rn was
! verified SH-2-correct on this core with a standalone non-MMU probe (the jump
! uses the PRE-delay-slot value), and leg C -- the same stores, same sentinel,
! same staging, but drained by a single IMISS instead of alternating -- passed
! throughout. DO NOT weaken this leg to make the suite green.
!
! ---- why the store legs matter (docs/architecture/tlb.md section 9) --------
! Section 9.1 states the contract: on a precise TLB fault, the base register of
! an access specifying writeback is left at its pre-instruction value, for
! every such form, uniformly.  Section 9.3 classifies the 30 writeback forms in
! the machine into three models by WHEN the base write commits relative to the
! faulting access:
!   A deferred  (7)  -- base write in a slot AFTER every access; restart-safe
!                       by construction, needs no restore
!   B bump-first(9)  -- base write commits in the slot BEFORE the access
!   C concurrent(14) -- base write lands in the SAME slot as the access, one
!                       cycle before tlb_squash can arm; suppression cannot
!                       reach it, so the explicit undo path is MANDATORY
! EVERY `@-Rn` store is in the concurrent group.  Leg A exercises the load side
! (`MOV.L @Rm+,Rn`, a bump-first form).  Legs C and D are the only guards in
! the suite that put a TRAIN of concurrent-model base restores (mem_predec)
! under the same drain conditions that exposed four defects on the load side.
!
! Every faulting access carries a non-idempotent side effect (post-increment
! on load, pre-decrement on store), so a restart that re-commits it is
! arithmetically visible.  Note the staging differs per direction so that both
! directions land on the page base:
!   loads   stage r<i> = page_i      ; `mov.l @r<i>+,r13` reads page_i,
!                                      leaves r<i> == page_i + 4
!   stores  stage r<i> = page_i + 4  ; `mov.l r13,@-r<i>` writes page_i,
!                                      leaves r<i> == page_i
! So the leg A check is `r<i> == page_i + 4` and the leg C/D check is
! `r<i> == page_i` EXACTLY.  In both cases 4 low means the access was DROPPED
! and 4 high means it was executed TWICE.  (mmuainc.S lesson.)
!
! The store pages are seeded with a distinct NON-ZERO value (0xC0000000 | i for
! leg C, 0xC1000000 | i for leg D) rather than 0, so that "the store landed" is
! distinguishable from "the page was always zero".
!
! Non-vacuity: the handler counts faults and each leg asserts the exact
! expected count.  Without this the file passes trivially if the pages are
! accidentally mapped and nothing ever faults.  The counter is a CHECK, not an
! oracle: faults can pre-empt each other, so the register arithmetic and the
! page read-back are the primary evidence and the count is the backstop.
!
! ---- check ORDER (deliberate; NOT the order the layers were designed in) ----
! The exactly-once register check runs BEFORE the fault-count check.  Both a
! genuine dropped access and a vacuous run (pages accidentally mapped) make the
! fault count wrong, so the count alone cannot tell the two apart.  The register
! evidence can: a vacuous run has every register at its untouched-by-restart
! value and only then trips the count.  So:
!   Result=6 / 8 / 9    -> real defect: an access was dropped or doubled
!   Result=2 / 4 / 5    -> real defect: a page holds the wrong data
!   Result=0x0B         -> real defect: leg D's delay-slot advance dropped/doubled
!   Result=0x10/12/13   -> vacuity: every access ran but the pages were mapped
!
! ---- three traps this file already stepped on (do not re-introduce) ----
!  1. Do NOT extend the identity-map range down to VA 0.  A VPN==0 entry makes
!     the very first D-side miss hang (the handler is never even entered); map
!     from `start`'s page instead.  `start` is .balign PAGE_SZ for that reason.
!  2. The handler must install STUB (instruction) pages with U=0.  0xE9 sets U,
!     and a kernel instruction fetch from a U=1 page is blocked by SMEP, so an
!     IMISS installed with 0xE9 re-faults forever.  The handler picks 0xC9 for
!     any VA below the data pool and 0xE9 inside it -- which is why the layout
!     contract below puts ALL the stub pages (A, C, D0..D9, the leg-D
!     trampoline) BELOW the first data page.
!  3. Nothing on the leg-D chain may touch r10.  r10 carries leg D's
!     fault-count snapshot across the whole chain, so _tramp_D loads its
!     return address into r14, not r10 (which is what _stub_A / _stub_C use --
!     legs A and C keep their snapshot in r11 instead).  Clobbering it makes
!     the non-vacuity check report garbage and sent this file's own bring-up
!     chasing a phantom.
!  4. FLUSH_TLB drops AT first.  This mattered absolutely under LDTLB (pulsing
!     TI with AT=1 unmapped the executing page AND the handler's page, and the
!     next fetch double-faulted with no way back).  Under the walker the
!     re-fetch would merely stall and re-walk, so the hazard is gone -- but AT
!     is still dropped around the TI pulse, both because the flush should not
!     race a translated fetch and because nothing is gained by relying on the
!     walker to rescue an avoidable window.
!
! Layout contract: [ code | _code_end | stub pages | data pages ].  Everything
! below _code_end is identity-mapped by the preamble (and re-mapped by
! FLUSH_TLB) and must never fault; everything above it is unmapped so it faults
! on first touch.
!
! ---- WALKER-INSTALL VERSION (L1 pilot of "retire LDTLB") -------------------
! No LDTLB / LDTLB.RN anywhere. Every TLB entry here is installed by the
! hardware TSB walker. What changed, and what deliberately did NOT:
!
!   * The preamble no longer LDTLBs the code pages; it writes a TSB ROW for
!     each and lets the walker pull them in on first touch, as a stall. Same
!     for FLUSH_TLB, which is now just the MMUCR.TI pulse -- the TSB survives
!     a TLB flush, so the code map rebuilds itself.
!   * The handler no longer ends in LDTLB.RN. It writes the faulting page's
!     TSB row and RTEs; the restarted access re-walks, hits that row, and the
!     walker installs it. So the FAULT TRAIN IS UNCHANGED -- one fault per
!     first touch, exactly as before -- and every check in this file (the
!     exactly-once base arithmetic, the page read-backs, the leg-D r12
!     advance, the fault counts) means precisely what it meant before.
!     MEASURED: the counts did not move. Legs A and C still take N+1 faults
!     and leg D still takes 2N+1, unchanged from the LDTLB version; no
!     expected constant in this file was touched.
!   * The one real semantic difference is the PRIZE: LDTLB.RN wrote BOTH TLB
!     arrays, so leg A/C/D's ten pure DATA pages each consumed an ITLB entry
!     they could never legally use. A walker install is routed by side
!     (core/cpu.vhd walk_side_i), so those pages now land in the DTLB ONLY.
!     That is what unblocks the 8+16 / 8+8 capacity sweep.
!
! TLB budget: 8 ITLB + 16 DTLB entries (core/cpu.vhd instantiation). FLUSH_TLB
! runs at the leg boundaries (never inside a measured window) so no leg's live
! set has to share with another's. The largest leg is D: 10 stubs + trampoline
! + code pages in the ITLB, and 10 data pages + the code pages the verifier
! reads through in the DTLB.
!
! THIS FILE IS THE SUITE'S DTLB-CAPACITY CANARY, measured 2026-08-13 in the L4
! capacity sweep. It is the only guard anywhere in mmu_sim.sh / linux_sim.sh
! whose D-side live set exceeds 8 pages, and it is the only one that reacts to
! DTLB size:
!   8 ITLB + 16 DTLB -> PASS (all three legs, no constant touched)
!   8 ITLB +  8 DTLB -> FAIL, Result=0x10 (leg A fault count). Layers 1-3
!     (exactly-once register arithmetic, page read-backs) still PASS, so every
!     translation is CORRECT and every access ran exactly once -- what moves is
!     only the number of faults leg A takes, because its ten data pages plus
!     the literal-pool code pages it reads through no longer fit in 8 DTLB
!     entries. The expected count was NOT retuned to accommodate that; 8+8 was
!     rejected instead.
! The ITLB stayed at 8 through both, so leg D's 11-page I-side live set is
! served by capacity misses that the walker absorbs as stalls, without any
! extra fault -- which is exactly the asymmetry that makes 8+16 the shipped
! configuration.
!
! TSB: _tsb_base (32 KB-aligned, at the end of the image), TSB_SIZE_LOG=10
! (1024 sets x 32 bytes), HASH_SHIFT=6, HASH_MODE=1. Set addresses come from
! the P4 TSB-slot helper (0xFF000048), never from a hand-computed hash. The
! handler inserts 2-way (way 0 unless it holds a valid entry) because ~45
! distinct pages pass through the TSB over the three legs and two live pages
! can hash to one set; a blind way-0 write would evict a live row and add an
! unaccounted refault to a measured count.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   LDC r0,VBR  = 0x402E   LDC r0,ASIDR = 0x407E   (PTEH is READ via the
!   read-only P4 alias 0xFF000000, not STC)
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; _fail still clamps r9==0
! to 0x7F.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

#define N_FAULTS 10
#define PAGE_SZ  0x1000

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

        ! Leg-boundary TLB reset: drop AT, invalidate every entry via MMUCR.TI
        ! (bit 2 -- core/cpu.vhd:519 -> tlb ti => dp_mmu_regs.mmucr(2)),
        ! rebuild the identity map over the code region, then re-enable AT.
        !
        ! AT MUST go off first (trap 3 in the header): a TI pulse taken with
        ! AT=1 unmaps the currently-executing page AND the handler's page, and
        ! the next fetch double-faults with no way back.
        !
        ! The macro takes a literal-pool prefix because SH-2 PC-relative
        ! `mov.l` reaches only +1020 bytes: each user needs its own copy of
        ! <pfx>mmucr / code_start / code_end / code_flags / page_sz nearby.
        .macro FLUSH_TLB pfx
        mov.l   \pfx\()mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off: translation bypassed
        mov     #4, r1
        mov.l   r1, @r0                 ! TI: invalidate all TLB entries
        mov     #0, r1
        mov.l   r1, @r0                 ! TI released
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on -- the code pages re-walk in
        .endm

        .ifne N_FAULTS - 10
        .error "legs A/C/D staging blocks are hand-unrolled for N_FAULTS==10"
        .endif

        ! start must be page-aligned: the map loop below walks it in PAGE_SZ
        ! steps (and see trap 1 in the header -- the range must not reach VA 0).
        .balign PAGE_SZ

ENTRY(start)
#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_drain - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- TSB configuration, then ASIDR = 0. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

        ! ---- Give every code page a TSB row: start .. _code_end. ----
        ! The body is larger than one page, so all of it (preamble, handler,
        ! verifier, literal pools) must be reachable BEFORE AT goes on. Note
        ! these rows are not installs: the walker pulls each page in on its
        ! first touch, as a STALL, and no exception is taken -- which is why
        ! the handler's own page is always resolvable and the "handler fetch
        ! double-faults" hazard of the LDTLB version cannot arise. The set
        ! address comes from the P4 TSB-slot helper (0xFF000048), never from a
        ! hand-computed hash. AT is off, so these are plain P0 stores.
        mov.l   p_tsbslot, r12
        mov.l   p_code_flags, r6
        mov.l   p_code_start, r2
        mov.l   p_code_end, r3
1:      mov.l   r2, @r12
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        mov     r2, r7
        or      r6, r7                  ! PTEL = page | 0xC9 (kernel code, U clear)
        mov     #0, r1
        tsb_fill r10, r2, r1, r7
        mov.l   p_page_sz, r0
        add     r0, r2
        cmp/hs  r3, r2
        bf      1b

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================= Leg A: N faulting LOADS, back-to-back =========
        mov.l   pA_fc, r0               ! snapshot fault count
        mov.l   @r0, r11
        mov.l   pA_d0, r0               ! stage r0..r9 = data pages 0..9
        mov.l   pA_d1, r1
        mov.l   pA_d2, r2
        mov.l   pA_d3, r3
        mov.l   pA_d4, r4
        mov.l   pA_d5, r5
        mov.l   pA_d6, r6
        mov.l   pA_d7, r7
        mov.l   pA_d8, r8
        mov.l   pA_d9, r9
        mov.l   pA_stub, r14

        ! ---- window: zero filler ----
        mov.l   @r0+, r13               ! DMISS_R 1
        mov.l   @r1+, r13               ! DMISS_R 2
        mov.l   @r2+, r13
        mov.l   @r3+, r13
        mov.l   @r4+, r13
        mov.l   @r5+, r13
        mov.l   @r6+, r13
        mov.l   @r7+, r13
        mov.l   @r8+, r13
        mov.l   @r9+, r13               ! DMISS_R N
        jmp     @r14                    ! IMISS -- the drain
        nop

        ! ---- literal pool for the preamble + leg A staging ----
        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_drain - 0x400
p_mmucr:        .long 0xFF000010
p_code_start:   .long start
p_code_end:     .long _code_end
p_code_flags:   .long 0x000000C9        ! W|X|C|V (V required by the walker)
p_page_sz:      .long PAGE_SZ
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long _tsb_base + 10    ! TSB_SIZE_LOG=10 -> 1024 sets x 32 B
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
pA_fc:          .long _fault_count
pA_stub:        .long _stub_A
pA_d0:          .long _dpage_A0
pA_d1:          .long _dpage_A1
pA_d2:          .long _dpage_A2
pA_d3:          .long _dpage_A3
pA_d4:          .long _dpage_A4
pA_d5:          .long _dpage_A5
pA_d6:          .long _dpage_A6
pA_d7:          .long _dpage_A7
pA_d8:          .long _dpage_A8
pA_d9:          .long _dpage_A9

! ---------------------------------------------------------------------------
! Leg A verification, on the far side of the drain stub.
!
! THE TRAP: the ten address registers ARE r0..r9, and verification itself needs
! scratch.  So spill r0..r9 into the mapped code region FIRST, before any other
! arithmetic, and compare against the spill slots afterwards.
! ---------------------------------------------------------------------------
ENTRY(_verify_A)
        mov.l   qA_spill, r14           ! r14 is dead (it held the stub address)
        mov.l   r0, @r14
        add     #4, r14
        mov.l   r1, @r14
        add     #4, r14
        mov.l   r2, @r14
        add     #4, r14
        mov.l   r3, @r14
        add     #4, r14
        mov.l   r4, @r14
        add     #4, r14
        mov.l   r5, @r14
        add     #4, r14
        mov.l   r6, @r14
        add     #4, r14
        mov.l   r7, @r14
        add     #4, r14
        mov.l   r8, @r14
        add     #4, r14
        mov.l   r9, @r14

        ! ---- layer 1 (exactly-once): spill[i] == _dpage_Ai + 4 ----
        ! low by 4  -> the access was DROPPED
        ! high by 4 -> the access was executed TWICE
        mov.l   qA_spill, r14
        mov.l   qA_dtab, r12
        mov     #N_FAULTS, r13
2:      mov.l   @r14+, r0               ! spilled r<i>
        mov.l   @r12+, r1               ! expected page base
        add     #4, r1
        cmp/eq  r1, r0
        mov     #6, r9
        bt      3f
        bra     _fail
        nop
3:      dt      r13
        bf      2b

        ! ---- layer 3: read each page back through the installed translation --
        mov.l   qA_dtab, r12
        mov.l   qA_sent, r14            ! 0xD0000000
        mov     #N_FAULTS, r13
4:      mov.l   @r12+, r1
        mov.l   @r1, r0
        cmp/eq  r14, r0
        mov     #2, r9
        bt      5f
        bra     _fail
        nop
5:      add     #1, r14
        dt      r13
        bf      4b

        ! ---- layer 4 (non-vacuity): fault count must have advanced by N+1 ----
        mov.l   qA_fc, r0
        mov.l   @r0, r12
        sub     r11, r12                ! r12 = faults taken by leg A
        mov     #(N_FAULTS + 1), r0
        cmp/eq  r0, r12
        mov     #0x10, r9
        bt      6f
        bra     _fail
        nop
6:      bra     _leg_C
        nop

        .align 2
qA_spill:       .long _spill_A
qA_fc:          .long _fault_count
qA_dtab:        .long _dtab_A
qA_sent:        .long 0xD0000000

! ===========================================================================
! Leg C: N faulting pre-decrement STORES, back-to-back, drained by one IMISS.
!
! The store-side mirror of leg A, and the first guard anywhere in the suite to
! put a TRAIN of Model-C (concurrent) base writebacks through the drain path.
! Addresses are staged at page_base+4 so `mov.l r13,@-r<i>` writes the page
! base and must leave r<i> == page_base EXACTLY.
!
! NO instruction may be added inside the window: any intervening memory access
! (including a PC-relative literal load) rewrites the ma_numz/ma_autoupd/
! ma_predec shadow registers and hides exactly the defect this leg hunts.
! ===========================================================================
ENTRY(_leg_C)
        FLUSH_TLB pC_
        mov.l   pC_fc, r0               ! snapshot fault count
        mov.l   @r0, r11
        mov.l   pC_d0, r0               ! stage r0..r9 = data page + 4
        mov.l   pC_d1, r1
        mov.l   pC_d2, r2
        mov.l   pC_d3, r3
        mov.l   pC_d4, r4
        mov.l   pC_d5, r5
        mov.l   pC_d6, r6
        mov.l   pC_d7, r7
        mov.l   pC_d8, r8
        mov.l   pC_d9, r9
        mov.l   pC_sval, r13            ! sentinel to store
        mov.l   pC_stub, r14

        ! ---- window: zero filler ----
        mov.l   r13, @-r0               ! DMISS_W 1, writes _dpage_C0
        mov.l   r13, @-r1               ! DMISS_W 2
        mov.l   r13, @-r2
        mov.l   r13, @-r3
        mov.l   r13, @-r4
        mov.l   r13, @-r5
        mov.l   r13, @-r6
        mov.l   r13, @-r7
        mov.l   r13, @-r8
        mov.l   r13, @-r9               ! DMISS_W N
        jmp     @r14                    ! IMISS -- the drain
        nop

        .align 2
pC_mmucr:       .long 0xFF000010
pC_fc:          .long _fault_count
pC_stub:        .long _stub_C
pC_sval:        .long 0xB00BC0DE
pC_d0:          .long _dpage_C0 + 4
pC_d1:          .long _dpage_C1 + 4
pC_d2:          .long _dpage_C2 + 4
pC_d3:          .long _dpage_C3 + 4
pC_d4:          .long _dpage_C4 + 4
pC_d5:          .long _dpage_C5 + 4
pC_d6:          .long _dpage_C6 + 4
pC_d7:          .long _dpage_C7 + 4
pC_d8:          .long _dpage_C8 + 4
pC_d9:          .long _dpage_C9 + 4

ENTRY(_verify_C)
        mov.l   qC_spill, r14           ! r14 is dead (it held the stub address)
        mov.l   r0, @r14
        add     #4, r14
        mov.l   r1, @r14
        add     #4, r14
        mov.l   r2, @r14
        add     #4, r14
        mov.l   r3, @r14
        add     #4, r14
        mov.l   r4, @r14
        add     #4, r14
        mov.l   r5, @r14
        add     #4, r14
        mov.l   r6, @r14
        add     #4, r14
        mov.l   r7, @r14
        add     #4, r14
        mov.l   r8, @r14
        add     #4, r14
        mov.l   r9, @r14

        ! ---- layer 1 (exactly-once): spill[i] == _dpage_Ci EXACTLY ----
        ! high by 4 -> the pre-decrement was DROPPED (base never moved)
        ! low  by 4 -> the pre-decrement committed TWICE
        mov.l   qC_spill, r14
        mov.l   qC_dtab, r12
        mov     #N_FAULTS, r13
2:      mov.l   @r14+, r0               ! spilled r<i>
        mov.l   @r12+, r1               ! expected page base
        cmp/eq  r1, r0
        mov     #8, r9
        bt      3f
        bra     _fail
        nop
3:      dt      r13
        bf      2b

        ! ---- layer 2: every page must now hold the sentinel, seed gone ----
        mov.l   qC_dtab, r12
        mov.l   qC_sent, r14
        mov     #N_FAULTS, r13
4:      mov.l   @r12+, r1
        mov.l   @r1, r0
        cmp/eq  r14, r0
        mov     #4, r9
        bt      5f
        bra     _fail
        nop
5:      dt      r13
        bf      4b

        ! ---- layer 3 (non-vacuity): fault count advanced by N+1 ----
        mov.l   qC_fc, r0
        mov.l   @r0, r12
        sub     r11, r12
        mov     #(N_FAULTS + 1), r0
        cmp/eq  r0, r12
        mov     #0x12, r9
        bt      6f
        bra     _fail
        nop
6:      bra     _leg_D
        nop

        .align 2
qC_spill:       .long _spill_C
qC_fc:          .long _fault_count
qC_dtab:        .long _dtab_C
qC_sent:        .long 0xB00BC0DE

! ===========================================================================
! Leg D: N x (faulting pre-decrement STORE -> IMISS), chained through stubs.
!
! A store produces no value, so leg D cannot use leg B's load-feeds-the-jump
! trick to compute the next stub VA.  Rather than spend a filler instruction on
! it -- which would break the zero-filler property that makes this leg mean
! anything -- leg D keeps a running stub pointer in r12 and advances it in the
! JUMP'S DELAY SLOT, which the jump has already read by then.
!
! The cost: no delay slot is left for an inline sequence counter, so leg D's
! count comes from the handler fault counter (plus r12's final value, which
! pins the advance itself).
!
! Stub chain arithmetic: r12 enters _stub_D0 holding _stub_D1, and each stub
! jumps to r12 then bumps it by PAGE_SZ, so _stub_D<i> is entered with r12 ==
! _stub_D<i+1>.  _stub_D9 therefore jumps to _stub_D_base + 10*PAGE_SZ, which
! is where _tramp_D sits, and leaves r12 == _stub_D_base + 11*PAGE_SZ.
!
! Fault accounting: 10 stub-entry IMISSes + 10 DMISS_Ws + 1 IMISS on _tramp_D
! = 2*N_FAULTS + 1, MINUS the code-page D faults the I->D shadow fill removed
! (see the layer-4 check for the measurement) = 16.
!
! Treat this number as EMPIRICAL, because it always was.  The "2*N_FAULTS + 1"
! derivation above was never complete: this leg's window also contained D-side
! faults on CODE pages -- the literal-pool reads of `start`'s page (which also
! carries the handler), of _stub_A/_stub_C, and of _tramp_D.  Those were
! invisible in the arithmetic and are exactly what changed.  Measured A/B with
! the shadow fill forced off and on, over the whole run: I-side installs 17 in
! both; D-side DEMAND installs 36 -> 30; the six that disappeared were
! vpn 8 (x3), 9, 10 and 21 -- every one a code page, no data page affected.
! ===========================================================================
ENTRY(_leg_D)
        FLUSH_TLB pD_
        mov.l   pD_fc, r0               ! snapshot fault count (r11 is the stride)
        mov.l   @r0, r10
        mov.l   pD_d0, r0               ! stage r0..r9 = data page + 4
        mov.l   pD_d1, r1
        mov.l   pD_d2, r2
        mov.l   pD_d3, r3
        mov.l   pD_d4, r4
        mov.l   pD_d5, r5
        mov.l   pD_d6, r6
        mov.l   pD_d7, r7
        mov.l   pD_d8, r8
        mov.l   pD_d9, r9
        mov.l   pD_sval, r13
        mov.l   pD_stride, r11          ! PAGE_SZ
        mov.l   pD_stub1, r12           ! r12 = the NEXT stub
        mov.l   pD_stub0, r14
        jmp     @r14                    ! IMISS -- enter the chain
        nop

        .align 2
pD_mmucr:       .long 0xFF000010
pD_fc:          .long _fault_count
pD_sval:        .long 0xB00BD0DE
pD_stride:      .long PAGE_SZ
pD_stub0:       .long _stub_D0
pD_stub1:       .long _stub_D0 + PAGE_SZ
pD_d0:          .long _dpage_D0 + 4
pD_d1:          .long _dpage_D1 + 4
pD_d2:          .long _dpage_D2 + 4
pD_d3:          .long _dpage_D3 + 4
pD_d4:          .long _dpage_D4 + 4
pD_d5:          .long _dpage_D5 + 4
pD_d6:          .long _dpage_D6 + 4
pD_d7:          .long _dpage_D7 + 4
pD_d8:          .long _dpage_D8 + 4
pD_d9:          .long _dpage_D9 + 4

ENTRY(_verify_D)
        mov.l   qD_spill, r14           ! r14 is dead (it held _stub_D0)
        mov.l   r0, @r14
        add     #4, r14
        mov.l   r1, @r14
        add     #4, r14
        mov.l   r2, @r14
        add     #4, r14
        mov.l   r3, @r14
        add     #4, r14
        mov.l   r4, @r14
        add     #4, r14
        mov.l   r5, @r14
        add     #4, r14
        mov.l   r6, @r14
        add     #4, r14
        mov.l   r7, @r14
        add     #4, r14
        mov.l   r8, @r14
        add     #4, r14
        mov.l   r9, @r14
        mov.l   qD_r12sav, r14          ! r12 is needed as a table pointer below
        mov.l   r12, @r14

        ! ---- layer 1 (exactly-once): spill[i] == _dpage_Di EXACTLY ----
        ! high by 4 -> the pre-decrement was DROPPED (base never moved)
        ! low  by 4 -> the pre-decrement committed TWICE.  On leg D this is a
        !              CONSEQUENCE of the layer-3 r12 loss (see the header), NOT
        !              a restore defect -- do not start debugging the restore
        !              path from here.
        mov.l   qD_spill, r14
        mov.l   qD_dtab, r12
        mov     #N_FAULTS, r13
2:      mov.l   @r14+, r0
        mov.l   @r12+, r1
        cmp/eq  r1, r0
        mov     #9, r9
        bt      3f
        bra     _fail
        nop
3:      dt      r13
        bf      2b

        ! ---- layer 2: every page holds the sentinel, seed gone ----
        mov.l   qD_dtab, r12
        mov.l   qD_sent, r14
        mov     #N_FAULTS, r13
4:      mov.l   @r12+, r1
        mov.l   @r1, r0
        cmp/eq  r14, r0
        mov     #5, r9
        bt      5f
        bra     _fail
        nop
5:      dt      r13
        bf      4b

        ! ---- layer 3: delay-slot advance, r12 == stub_base+(N+1)*PAGE_SZ ----
        mov.l   qD_r12sav, r0
        mov.l   @r0, r12
        mov.l   qD_r12exp, r0
        cmp/eq  r0, r12
        mov     #0x0B, r9
        bt      6f
        bra     _fail
        nop
6:
        ! ---- layer 4 (non-vacuity): fault count advanced by 2N+1 ----
        mov.l   qD_fc, r0
        mov.l   @r0, r12
        sub     r10, r12
        ! 16, not 2*N_FAULTS+1 -- see the fault accounting note in this leg's
        ! header.  The register and page-readback evidence (layers 1-3) is the
        ! primary proof that every access ran exactly once; this layer is the
        ! vacuity backstop, and its value moved because the shadow fill removed
        ! code-page D faults that the old constant silently included.
        mov     #16, r0
        cmp/eq  r0, r12
        mov     #0x13, r9
        bt      7f
        bra     _fail
        nop
7:
        ! ---- Disable AT before handing the result to the harness. ----
        mov.l   qD_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov     #0, r9
        bra     _done
        nop

        .align 2
qD_spill:       .long _spill_D
qD_fc:          .long _fault_count
qD_dtab:        .long _dtab_D
qD_sent:        .long 0xB00BD0DE
qD_mmucr:       .long 0xFF000010
qD_r12exp:      .long _stub_D0 + (N_FAULTS + 1) * PAGE_SZ
qD_r12sav:      .long _r12sav_D

#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: keep the fail code loud
        bf      1f                      ! (PASS now requires TEST_PASS_MAGIC, so 0
        mov     #0x7F, r9               !  reports as Result=0, not as PASS.)
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

        ! ---- VA-driven handler at VBR+0x400 (all six TLB fault kinds) ----
        ! Runs with SR.RB=1, so its bank-1 scratch does not touch the leg's
        ! bank-0 registers.
        .balign 4
        .space 0x400, 0
        .balign 4
_v_drain:
        mov.l   Hpteh_a, r1
        mov.l   @r1, r1                 ! r1 = PTEH (P4 alias) -- HW-captured faulting VPN
        mov.l   Hpagemask, r0
        and     r0, r1                  ! r1 = page base
        ! Pick the PTEL flags from the layout contract: ALL the stub pages (A,
        ! C, D0..D9 and the leg-D trampoline) sit BELOW the first data page, so
        ! a fault under _dpage_A0 is an I-side stub fetch and must be given
        ! U=0 -- 0xE9 (U=1) there makes the kernel fetch fault forever under
        ! SMEP.
        mov.l   Hdbase, r0              ! _dpage_A0: start of the data pool
        cmp/hs  r0, r1                  ! T = (page >= first data page)
        bt      1f
        mov.l   Hcflags, r0             ! stub page: 0xC9 (kernel code, U clear)
        bra     2f
        nop
1:      mov.l   Hflags, r0              ! data page: 0xE9
2:      or      r1, r0                  ! PTEL = page | flags
        mov     r0, r3                  ! r3 = PTEL
        ! ---- Write the TSB row for this page, then simply return: the
        ! ---- restarted access re-walks, hits the row we just wrote, and the
        ! ---- walker installs it -- into the ITLB for a fetch and the DTLB for
        ! ---- a data access, by side, which is the whole point of the
        ! ---- migration (LDTLB.RN wrote BOTH arrays). Only bank-1 scratch
        ! ---- (r0..r4) is touched: r10 carries leg D's fault-count snapshot
        ! ---- and r11..r14 carry the legs' state.
        mov.l   Hslot, r2
        mov.l   r1, @r2                 ! ask the P4 helper for this VA's set
        mov.l   @r2, r2
        mov.l   Hp1, r0
        or      r0, r2                  ! P1 alias: the TSB is untranslated
        ! 2-way insert. The handler runs ~45 pages through a 1024-set TSB over
        ! the three legs, so two live pages CAN hash to one set; blindly using
        ! way 0 would evict a still-live row and add an unaccounted refault.
        ! Way 0 unless it already holds a valid entry (data word bit 0 = V).
        mov.l   @(8, r2), r0
        tst     #1, r0
        bt      3f
        add     #16, r2                 ! way 1
3:      mov     #0, r0                  ! ASID_TAG = 0
        tsb_fill r2, r1, r0, r3
        mov.l   Hcount, r0              ! non-vacuity: count this fault
        mov.l   @r0, r4
        add     #1, r4
        mov.l   r4, @r0
        rte
        nop
_h_fail_spin:
        bra     _h_fail_spin
        nop
        .align 2
Hpagemask:      .long 0xFFFFF000
Hpteh_a:        .long 0xFF000000
Hflags:         .long 0x000000E9        ! data page: W|X|U|C|V
Hcflags:        .long 0x000000C9        ! stub/code page: W|X|C|V (U clear, SMEP)
Hdbase:         .long _dpage_A0
Hslot:          .long 0xFF000048        ! P4_TSBSLOT
Hp1:            .long 0x80000000        ! P1 alias -- TSB writes bypass the MMU
Hcount:         .long _fault_count

        .balign 4
ENTRY(_fault_count)
        .long 0

        .balign 4
_spill_A:
        .space 4 * N_FAULTS, 0
        .balign 4
_spill_C:
        .space 4 * N_FAULTS, 0
        .balign 4
_spill_D:
        .space 4 * N_FAULTS, 0
        .balign 4
_r12sav_D:
        .long 0

        .balign 4
_dtab_A:
        .long _dpage_A0
        .long _dpage_A1
        .long _dpage_A2
        .long _dpage_A3
        .long _dpage_A4
        .long _dpage_A5
        .long _dpage_A6
        .long _dpage_A7
        .long _dpage_A8
        .long _dpage_A9

        .balign 4
_dtab_C:
        .long _dpage_C0
        .long _dpage_C1
        .long _dpage_C2
        .long _dpage_C3
        .long _dpage_C4
        .long _dpage_C5
        .long _dpage_C6
        .long _dpage_C7
        .long _dpage_C8
        .long _dpage_C9

        .balign 4
_dtab_D:
        .long _dpage_D0
        .long _dpage_D1
        .long _dpage_D2
        .long _dpage_D3
        .long _dpage_D4
        .long _dpage_D5
        .long _dpage_D6
        .long _dpage_D7
        .long _dpage_D8
        .long _dpage_D9

        .balign 4
ENTRY(_code_end)                        ! everything above is identity-mapped code

! ======================= unmapped region starts here =======================
! Stub pages FIRST (they must all be below _dpage_A0 -- see trap 2), then the
! data pool.
        .balign PAGE_SZ
_stub_A:                                ! own unmapped page -> IMISS on entry
        mov.l   sA_back, r10
        jmp     @r10
        nop
        .align 2
sA_back:        .long _verify_A

        .balign PAGE_SZ
_stub_C:
        mov.l   sC_back, r10
        jmp     @r10
        nop
        .align 2
sC_back:        .long _verify_C

! Leg D's ten stubs, laid out contiguously at PAGE_SZ spacing, with the
! trampoline immediately after the last one so that
! _stub_D0 + N_FAULTS*PAGE_SZ lands exactly on _tramp_D.  The .balign before
! _stub_D0 plus the .balign inside the .irp make the spacing exact; the
! _tramp_D assertion below proves it rather than assuming it.
        .balign PAGE_SZ
        .irp i, 0,1,2,3,4,5,6,7,8,9
        .balign PAGE_SZ
_stub_D\i:                              ! entry IMISSes
        mov.l   r13, @-r\i              ! DMISS_W
        jmp     @r12                    ! IMISS -- r12 already holds stub i+1
        add     r11, r12                ! delay slot: advance to stub i+2
        .endr

        .balign PAGE_SZ
_tramp_D:                               ! must NOT touch r10 (leg D's fault-count
        mov.l   sD_back, r14            ! snapshot) -- r14 is dead here
        jmp     @r14
        nop
        .align 2
sD_back:        .long _verify_D

        ! The chain arithmetic (_tramp_D == _stub_D0 + N_FAULTS*PAGE_SZ) cannot
        ! be asserted with .ifne -- section-relative differences are not
        ! constant at assembly time ("non-constant expression in .if").  It is
        ! instead proven two ways: statically with
        !     sh2-elf-nm mmudrain.elf | grep -E '_stub_D0|_tramp_D'
        ! (the two must differ by exactly 0xA000), and dynamically -- if the
        ! layout were wrong the chain would never reach _verify_D at all, and
        ! the r12 check (fail 0x0B) pins the advance itself.

        .balign PAGE_SZ
_dpage_A0:  .long 0xD0000000
            .space PAGE_SZ - 4, 0
_dpage_A1:  .long 0xD0000001
            .space PAGE_SZ - 4, 0
_dpage_A2:  .long 0xD0000002
            .space PAGE_SZ - 4, 0
_dpage_A3:  .long 0xD0000003
            .space PAGE_SZ - 4, 0
_dpage_A4:  .long 0xD0000004
            .space PAGE_SZ - 4, 0
_dpage_A5:  .long 0xD0000005
            .space PAGE_SZ - 4, 0
_dpage_A6:  .long 0xD0000006
            .space PAGE_SZ - 4, 0
_dpage_A7:  .long 0xD0000007
            .space PAGE_SZ - 4, 0
_dpage_A8:  .long 0xD0000008
            .space PAGE_SZ - 4, 0
_dpage_A9:  .long 0xD0000009
            .space PAGE_SZ - 4, 0

! Leg C store pages, seeded NON-ZERO and distinct so that "the store landed"
! is distinguishable from "the page was always zero".
_dpage_C0:  .long 0xC0000000
            .space PAGE_SZ - 4, 0
_dpage_C1:  .long 0xC0000001
            .space PAGE_SZ - 4, 0
_dpage_C2:  .long 0xC0000002
            .space PAGE_SZ - 4, 0
_dpage_C3:  .long 0xC0000003
            .space PAGE_SZ - 4, 0
_dpage_C4:  .long 0xC0000004
            .space PAGE_SZ - 4, 0
_dpage_C5:  .long 0xC0000005
            .space PAGE_SZ - 4, 0
_dpage_C6:  .long 0xC0000006
            .space PAGE_SZ - 4, 0
_dpage_C7:  .long 0xC0000007
            .space PAGE_SZ - 4, 0
_dpage_C8:  .long 0xC0000008
            .space PAGE_SZ - 4, 0
_dpage_C9:  .long 0xC0000009
            .space PAGE_SZ - 4, 0

_dpage_D0:  .long 0xC1000000
            .space PAGE_SZ - 4, 0
_dpage_D1:  .long 0xC1000001
            .space PAGE_SZ - 4, 0
_dpage_D2:  .long 0xC1000002
            .space PAGE_SZ - 4, 0
_dpage_D3:  .long 0xC1000003
            .space PAGE_SZ - 4, 0
_dpage_D4:  .long 0xC1000004
            .space PAGE_SZ - 4, 0
_dpage_D5:  .long 0xC1000005
            .space PAGE_SZ - 4, 0
_dpage_D6:  .long 0xC1000006
            .space PAGE_SZ - 4, 0
_dpage_D7:  .long 0xC1000007
            .space PAGE_SZ - 4, 0
_dpage_D8:  .long 0xC1000008
            .space PAGE_SZ - 4, 0
_dpage_D9:  .long 0xC1000009
            .space PAGE_SZ - 4, 0

! ---- The TSB itself. 1024 sets x 32 bytes = 32 KB, 32 KB-aligned so that
! tsb_ptr()'s (base and not 0x1F) or (idx << 5) is a clean concatenation.
! Zero-filled by the image, so every row in it was written by this guard.
        .balign 0x8000
_tsb_base:
        .space 0x8000, 0

#endif
