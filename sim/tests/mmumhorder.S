! mmumhorder.S -- MEASUREMENT guard for task #12: is an I-side TLB MULTI_HIT
! (which belongs to an instruction being FETCHED, i.e. YOUNGER than anything
! in EX/MA) delivered ahead of an OLDER in-flight D-side fault, and if so, is
! the older instruction merely re-ordered (benign) or LOST (serious)?
!
! ---- Why this file exists (do not "fix" the RTL from analysis alone) ----
!
! Read off the tree, not re-derived here:
!   * decode/decode_core.vhm's tlb_exc latch takes every fault kind EXCEPT
!     IMISS/IPROT onto the held path, and the `and texc_req = '0'` term makes
!     that latch FIRST-COME. MULTI_HIT rides it, so a YOUNGER I-side MULTI_HIT
!     can occupy the latch while an OLDER D-side fault cannot be latched.
!   * core/cpu.vhd guards the ENTIRE D-side detection branch on `exc_en = '0'`.
!     Any I-side fault raised in the same cycle leaves exc_en='1', so the older
!     D-side fault is not merely out-ranked -- it is never DETECTED that cycle.
!   * core/cpu.vhd's deferral narrowing (`exc_kind = IMISS or exc_kind = IPROT`)
!     deliberately does NOT defer MULTI_HIT. That narrowing is about the
!     restart-PC side channel and is CORRECT; ordering is an independent
!     property it does not address. Leave it alone.
!
! What was NOT known when this guard was written, and is what it measures:
!   (a) whether the race is reachable at all in practice;
!   (b) whether the older D-side access is delivered FIRST (correct) or the
!       younger MULTI_HIT pre-empts it;
!   (c) whether the older instruction survives -- re-executed after the
!       MULTI_HIT is serviced -- or is squashed and never retried.
!
! (b) and (c) get SEPARATE fail codes on purpose: "MULTI_HIT delivered first"
! and "delay-slot load lost" are different defects with different fixes
! (relaxing the first-come `texc_req = '0'` term vs. deferring MULTI_HIT with
! the instruction the way IMISS/IPROT are), and one code would conflate them.
! The 2026-08-06 handover recorded a mis-ordering as a defect on the strength
! of a broken instrument and it later proved benign; this guard is written to
! distinguish those two outcomes rather than assume either.
!
! ==== WHAT WAS MEASURED (2026-08-07, this guard, this tree) ================
!
! (a) REACHABLE -- yes. The construction fires; the guard is red, with a
!     precise code, under all three mutations listed under "Non-vacuity".
!
! (b) The RTL does dispatch the younger MULTI_HIT first, and the older D-side
!     fault then lands ON TOP of that dispatch -- but the software-visible
!     order is still correct. Read off `cpu_ctb --log-ops`:
!
!         IF 0x001092  JMP @R1                 <- the branch
!         IF 0x001094  MOV.L @R13, R12         <- delay slot (OLDER)
!         IF 0x041000                          <- candidate PA fetched, squashed
!         IF 0x00129C                          <- VBR+0x100, the MULTI_HIT
!         IF 0x00159C                          <- VBR+0x400, the D-side fault
!         ... _h_tlb ... rte ...
!         IF 0x001092  JMP @R1                 <- SPC = the branch; load retries
!
!     The GI dispatch happens and is then superseded one fetch later; its
!     first instruction never retires. Everything that dispatch wrote --
!     EXPEVT, SSR, SPC -- is overwritten by the D-side dispatch, and the
!     D-side restart PC is the branch, so the delay-slot load re-executes,
!     succeeds, the branch target re-fetches, MULTI_HITs again, and only then
!     does the GI handler run to completion. Handlers therefore observe
!     D-then-MULTI_HIT, which is the correct order.
!
!     NOTE the transient GI dispatch is NOT observable from software: any
!     instrumentation placed at VBR+0x100 is itself pre-empted before it
!     retires (the first revision of this guard tried exactly that). It was
!     read off the instruction trace. This guard cannot regress-test it.
!
! (c) NOTHING IS LOST -- r12 holds the seeded word. The older instruction is
!     re-executed, not squashed-and-dropped.
!
! CONCLUSION: the §5 remedies (defer MULTI_HIT with the instruction; or relax
! the first-come `texc_req = '0'` term) are NOT justified by a measured
! user-visible defect. Like the 2026-08-06 mis-ordering, this one is benign as
! it stands. This guard exists to keep it that way.
!
! WHAT REMAINS OPEN, and is NOT measured here: the second (D-side) dispatch
! nests on a partially-taken first (MULTI_HIT) dispatch. Whether that window
! is safe with respect to SR.BL -- i.e. whether some timing of it can be taken
! as a double fault instead (cf. sim/tests/mmudblflt.S) -- was not established.
! Do not read this guard as evidence that it is.
!
! ---- The race ----
!
!         jmp     @r1             ! target page V: I-fetch MULTI_HITs  (YOUNGER)
!         mov.l   @r13, r12       ! delay slot: D-side DMISS_R         (OLDER)
!
! The delay-slot load is architecturally older than the branch target's fetch,
! and both are outstanding in the same cycle. On a correct machine the older
! DMISS_R is delivered first, its handler maps the data page, the restart PC
! lands back on the jmp, the load then succeeds, and only then does the branch
! target's fetch raise MULTI_HIT.
!
! ---- WALKER-INSTALL VERSION (L2 of "retire LDTLB") ----
!
! Every TLB entry in this file is installed by the HARDWARE TSB WALKER. The
! race, the order log, every check and every result code are unchanged. Three
! things had to change, all forced by the walker:
!
!   (i)   it installs only on a MISS, so the three coexisting entries on VPN V
!         are now provoked by three ACCESSES under three different ASIDs
!         instead of three back-to-back installs;
!   (ii)  it installs into ONE array, by side. This construction needs the I
!         array, so each of the three installs is a real INSTRUCTION FETCH of
!         V. All three candidate PAs already carried `jmp @r14 / nop`, so each
!         install jumps into V and bounces back to a label parked in r14;
!   (iii) the GI handler no longer reinstalls anything by hand -- see
!         "Servicing the MULTI_HIT" below.
!
! ---- Reaching a GENUINE MULTI_HIT ----
!
! A two-entry install can no longer reach it: install-time overlap eviction
! merges them (sim/tests/mmumultihit.S documents this at length). The
! reachable construction is copied from m8_multihit_ifetch.S sub-test 1 -- see
! that file's header for the full derivation against core/tlb.vhd. In brief:
! install THREE entries on one VPN V -- A under ASID_A (non-global), B under
! ASID_B (non-global), C global -- because the dedup scan latches on the
! FIRST overlapping match and never re-fires. The walker supplies the two
! extra misses: with A resident and non-global under ASID_A, a fetch of V
! under ASID_B misses again and walks in B; with A and B both resident and
! neither matching, a fetch of V under a THIRD ASID (0) misses again and walks
! in C from the row whose PTEL is global. Installing C evicts A and leaves B
! untouched; with ASIDR=ASID_B, B (asid match) and C (global) both match one
! lookup and the scan raises MULTI_HIT.
!
! ---- Servicing the MULTI_HIT (why the handler flushes) ----
!
! The VBR+0x100 handler must genuinely RESOLVE the multi-hit and `rte` to the
! hardware SPC. It deliberately does NOT redirect SPC to a chosen label the way
! m8_multihit_ifetch.S's handler does: overriding SPC would destroy the very
! recovery path that decides question (c). If the machine delivers MULTI_HIT
! first but SPC still points at the older jmp, the delay-slot load re-executes
! and nothing is lost -- a benign re-ordering. Redirecting SPC would report
! that case as a lost instruction, which is exactly the false positive this
! guard exists to avoid.
!
! Resolution is a full TI flush, and NOTHING ELSE. There is no targeted
! single-entry invalidate, so the whole array goes -- and under walker-only
! install that is sufficient, where under LDTLB it was not. The TSB SURVIVES a
! TI flush, and after the flush ASIDR is ASID_B, so the next fetch of V walks
! the ONE row hashed for (V, ASID_B) and installs exactly ONE entry. A single
! walk cannot produce two entries by construction. The LDTLB version had to
! reinstall the code map, a single mapping for V and the data page by hand,
! precisely because re-installing over V never converged: each global install
! evicts only the first of the two overlapping entries and adds one back, so
! the count stayed at two forever.
!
! The data page comes back the same way, from the row the D-side handler
! published, so the flush still cannot manufacture a second, spurious DMISS_R
! and perturb the order log.
!
! All three of page V's candidate backing pages are seeded via P1 with
! `jmp @r14 / nop` (0x4E2B 0x0009), so once V resolves to a single mapping --
! now PA_B, the row reachable under ASID_B, rather than PA_C -- control lands
! there and bounces to `after_race` in r14. That works whether SPC pointed at
! the branch target (lands directly in V) or at the older jmp (re-runs the --
! now idempotent, base r13 != dest r12 -- load and jumps to V).
!
! ---- The order log ----
!
! Each handler appends a TAG, not EXPEVT, as the ordering token: TAG_D=1 from
! VBR+0x400, TAG_MH=2 from VBR+0x100. On this core ALL SIX TLB fault kinds
! vector to VBR+0x400 and are distinguished only by EXPEVT, while MULTI_HIT
! dispatches through General Illegal at VBR+0x100 -- so the vector reached is
! already an unambiguous side discriminator, and the tag cannot be poisoned by
! an EXPEVT read failing. KIND is still asserted separately: the GI handler
! checks EXPEVT=0x180 and MMUFSR=0x1700 (fail 5/6, exactly as
! m8_multihit_ifetch.S does -- an unmapped/zero-filled page would also trap
! through VBR+0x100 as an illegal instruction, and those two checks are what
! keep that from being mistaken for a MULTI_HIT), and the D-side handler
! records its EXPEVT for a 0x060 = DMISS_R check at the end (fail 7).
!
! MULTI_HIT's MMUFSR low byte is zero -- it is not a page fault
! (docs/architecture/tlb.md).
!
! SPC at the MULTI_HIT is recorded in _spc_at_mh. It is NOT asserted on (the
! correct value depends on the answer this guard is measuring); it is there so
! a red run can be read straight out of memory rather than re-instrumented.
!
! ---- Result codes ----
!   0  pass
!   1  NO fault at all -- the race never happened. ANTI-VACUITY: the whole
!      guard is trivially satisfiable by a construction that stops faulting.
!   2  first logged fault was NOT the D-side one. ORDERING DEFECT: the younger
!      I-side MULTI_HIT pre-empted the older in-flight D-side access.
!   3  no second fault, or it was not the MULTI_HIT. The construction did not
!      reach i_multihit (or the MULTI_HIT was swallowed).
!   4  r12 != the seeded data word. INSTRUCTION LOST: the older delay-slot load
!      was squashed and never re-executed. Distinct from 2 on purpose.
!   5  VBR+0x100 handler: EXPEVT != 0x180 (not a genuine MULTI_HIT)
!   6  VBR+0x100 handler: MMUFSR != 0x1700
!   7  D-side EXPEVT != 0x060 (the older fault was not DMISS_R)
!   8  fault log full -- the run is not converging (a handler is re-faulting
!      forever). Reported from inside whichever handler overflowed, so a
!      livelock surfaces as a result code instead of a stop-time timeout.
!
! ---- Non-vacuity (MEASURED 2026-08-07, not reasoned) ----
! A guard for a race that never occurs passes trivially -- that exact failure
! was found in the m8 axes on 2026-08-07. Each of the three live checks was
! mutated red independently, and each reported ITS OWN code, not a timeout and
! not a neighbour's code:
!
!   1. Clear the GLOBAL bit in page V's third TSB row (entry C is no longer
!      global, so under ASID_B only B matches) -> the construction can no
!      longer multi-hit.                                        Result=3.
!   2. Point the delay-slot load at an already-mapped address -> the older
!      D-side leg of the race disappears, so the MULTI_HIT is logged first.
!                                                               Result=2.
!   3. Seed the data page with a value other than the expected one -> the load
!      commits but yields the wrong word, i.e. the check really does read the
!      delay-slot load's result and not a constant.             Result=4.
!   4. Corrupt the GI handler's expected MMUFSR -> Result=6, i.e. the handler
!      really is reading a live MULTI_HIT and not a stale register.
!
! All four re-measured on the walker-install version (2026-08-13); re-run them
! after any change to the construction.
!
! PTEL flag bit layout (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C
! bit2=G bit1=STALE bit0=V. Kernel non-global code: W|X|C|V = 0xC9; the global
! variant ORs in bit2 (0xCD). Bit0 (V) MUST be set in a TSB entry:
! core/tlb_walk.vhd rejects a data word with V=0 or STALE=1 as "no entry", so
! the LDTLB version's 0xC8/0xCC become 0xC9/0xCD here. U stays 0 throughout:
! page V is FETCHED, and a kernel fetch of a U=1 page is an SMEP protection
! fault. Every mapping published from a HANDLER is global so it survives (and
! does not disturb) the ASIDR=ASID_B the multi-hit construction depends on --
! no handler here touches ASIDR.
!
! TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x 32 bytes = 8 KB),
! HASH_SHIFT=6, HASH_MODE=1. Slot addresses are never hand-computed: the guard
! and both handlers ask the P4 TSB-slot helper (0xFF000048, the single
! tsb_ptr() implementation the walker and TSBPTR also use). The image is padded
! past the END of the TSB, because the walker reads it by PHYSICAL address and
! a physical alias is backed by SRAM only within the loaded image extent.
!
! Handlers are entered with SR.RB=1, so they use only r0-r7 (bank 1); r9 and
! r12-r14 are non-banked and carry state across faults untouched.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   LDC r0,VBR = 0x402E   LDC r0,ASIDR = 0x407E
!   STC EXPEVT,r0 = 0x0052   STC SPC,r0 = 0x0042
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS, and _fail clamps r9==0 to
! 0x7F so an un-set fail code is never mistaken for PASS.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

        .section .vect
        .long   start
        .long   0x00007000
        .long   start
        .long   0x00007000
        .rept   60
        .long   0
        .endr
        .long   SIM_INSTR_MAGIC
        .long   _sim_instr_end
        .long   _done
        .long   _fail
        .long   CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
        ! start must be page-aligned: the code-mapping loop walks it in
        ! PAGE_SZ steps.
        .balign 0x1000
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). REQUIRED: the I-side TLB fault path is
        ! gated on SR.RB='0' (core/cpu.vhd); with RB=1 (reset default)
        ! I-fetches bypass the TLB and page V never multi-hits. ----
        stc     sr, r0
        mov.l   s_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _vbase (so VBR+0x100 = General Illegal / MULTI_HIT and
        ! VBR+0x400 = all six TLB fault kinds). ----
        mov.l   s_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Clean-slate TLB. ----
        mov.l   s_mmucr, r0
        mov     #4, r1
        mov.l   r1, @r0                 ! TI: invalidate all 32 entries
        mov     #0, r1
        mov.l   r1, @r0                 ! TI released

        ! ---- Seed the backing pages via P1 (untranslated, AT-independent)
        ! before AT goes on. ALL THREE candidate PAs need real content, not
        ! just the survivor: a multi-hit still causes a real (squashed) bus
        ! fetch of at least one candidate PA before the fault pre-empts it
        ! (MEASURED -- the trace shows a fetch of PA_B immediately before the
        ! VBR+0x100 dispatch), and the sim's memory model reports a bus error
        ! on a never-written location.
        !
        ! All three get the SAME payload, `jmp @r14 / nop`. m8_multihit_ifetch.S
        ! deliberately poisons the non-survivors with `bra $` so a stray
        ! successful fetch spins; here that is the wrong trade. A construction
        ! that stops multi-hitting lands on B and, poisoned, would hang to
        ! stop-time -- red, but diagnosed only as "timeout". With the payload
        ! on every candidate, the same broken construction bounces to
        ! after_race and reports the precise code (3: MULTI_HIT never arrived).
        ! Nothing is weakened: the checks at after_race, not the landing page,
        ! are what decide PASS. ----
        mov.l   s_payload_instr, r4     ! 0x4E2B0009 = "jmp @r14 / nop"
        mov.l   s_p1_a, r2 ; mov.l r4, @r2
        mov.l   s_p1_b, r2 ; mov.l r4, @r2
        mov.l   s_p1_c, r2 ; mov.l r4, @r2

        ! ---- Seed the delay-slot load's data word through P1, on a page
        ! deliberately left UNMAPPED so the load takes DMISS_R. ----
        mov.l   s_p1_data, r2
        mov.l   s_dataword, r3
        mov.l   r3, @r2

        ! ---- Order log: empty. ----
        mov.l   s_log_ptr, r0
        mov.l   s_log_base, r1
        mov.l   r1, @r0

        ! ---- Configure the TSB and fill it from the (VA, ASID, PTEL) table.
        ! ---- For each row the set address is asked of the P4 helper UNDER
        ! ---- THAT ROW'S ASID, so no hash is hand-computed. AT is still off,
        ! ---- so these are plain untranslated P0 stores. ----
        mov.l   s_tsbbr_addr, r0
        mov.l   s_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   s_tsbcfg_addr, r0
        mov.l   s_tsbcfg_val, r1
        mov.l   r1, @r0

        mov.l   s_tsbslot, r12
        mov.l   s_tab, r14
        mov.l   s_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID_TAG
        mov.l   @r14+, r8               ! PTEL
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        mov     #0, r0
        .word   0x407E                  ! ASIDR := 0, the ASID the code
        nop                             ! superpage is first walked in under
        nop

        bra     _run
        nop

        ! ---- Literal pool 1 (setup). SH-2 `mov.l @(disp,PC)` is FORWARD-only
        ! ---- and reaches +1020 bytes, so the constants are split into this
        ! ---- setup pool and a body pool after the checks; a couple are
        ! ---- duplicated in both. ----
        .align  2
s_rbclear:      .long   0xDFFFFFFF
s_vbr_val:      .long   _vbase
s_mmucr:        .long   0xFF000010
s_payload_instr:.long   0x4E2B0009      ! "jmp @r14" / nop delay slot
s_p1_a:         .long   0x80040000      ! P1(0x40000)
s_p1_b:         .long   0x80041000      ! P1(0x41000)
s_p1_c:         .long   0x80042000      ! P1(0x42000)
s_p1_data:      .long   0x80030000      ! P1(0x30000)
s_dataword:     .long   0x5A5AC3C3      ! what the delay-slot load must yield
s_log_ptr:      .long   _log_ptr
s_log_base:     .long   _log
s_tsbbr_addr:   .long   0xFF000014
s_tsbbr_val:    .long   0x00014008      ! base=0x00014000, TSB_SIZE_LOG=8
s_tsbcfg_addr:  .long   0xFF000018
s_tsbcfg_val:   .long   0x00000061      ! HASH_SHIFT=6, HASH_MODE=1
s_tsbslot:      .long   0xFF000048      ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
s_tab:          .long   _tsb_tab
s_tab_end:      .long   _tsb_tab_end

        ! ---- TSB fill table: VA, ASID_TAG, PTEL.
        ! The code region is ONE 16 KB GLOBAL identity page (VA 0..0x3FFF,
        ! page_mask=1). The walker's tag compare is EXACT on the 4 KB VPN even
        ! for a superpage entry, so each of VPN 0..3 needs its own row;
        ! whichever is touched first installs the same 16 KB mapping and the
        ! rest then hit without walking.
        ! Each code row is duplicated under EVERY ASID this guard uses (0,
        ! ASID_A, ASID_B). core/tlb_walk.vhd requires tag_lo = asidr EXACTLY,
        ! global bit or not, so a row is only reachable under its own ASID.
        ! The global TLB entry means the ASIDR churn during the A/B/C installs
        ! never re-walks code -- but the GI handler's TI flush drops it, and
        ! the fetches after that RTE run under ASID_B.
        ! Page V gets its three rows; the DATA page deliberately gets NONE --
        ! it must miss, and its row is published by the D-side handler.
        .balign 4
_tsb_tab:
        .long   0x00000000, 0x00000000, 0x000001CD  ! code 16K global W|X|C|V
        .long   0x00001000, 0x00000000, 0x000001CD
        .long   0x00002000, 0x00000000, 0x000001CD
        .long   0x00003000, 0x00000000, 0x000001CD
        .long   0x00000000, 0x00000011, 0x000001CD
        .long   0x00001000, 0x00000011, 0x000001CD
        .long   0x00002000, 0x00000011, 0x000001CD
        .long   0x00003000, 0x00000011, 0x000001CD
        .long   0x00000000, 0x00000022, 0x000001CD
        .long   0x00001000, 0x00000022, 0x000001CD
        .long   0x00002000, 0x00000022, 0x000001CD
        .long   0x00003000, 0x00000022, 0x000001CD
        .long   0x00020000, 0x00000011, 0x000400C9  ! V: PA 0x40000, non-global
        .long   0x00020000, 0x00000022, 0x000410C9  ! V: PA 0x41000, non-global
        .long   0x00020000, 0x00000000, 0x000420CD  ! V: PA 0x42000, GLOBAL
_tsb_tab_end:

ENTRY(_run)
        ! ---- Enable AT. The data page and page V's single resolution are
        ! left to the handlers / the walker. ASIDR is 0 here, so the next
        ! fetch and the next literal load each walk the code superpage in --
        ! one into u_itlb, one into u_dtlb. BOTH arrays matter: the handlers
        ! run with SR.RB=1, where core/cpu.vhd's walk_req is NOT armed, so a
        ! D-miss on the handler's own literal pool would be an unrecoverable
        ! nested fault. Under LDTLB the pre-AT map loop wrote both arrays for
        ! free; the walker installs one side per miss. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================================================================
        ! Build the three-entry MULTI_HIT construction on VPN V. Each entry
        ! is installed by a real INSTRUCTION FETCH of V under its own ASID:
        ! the walker installs only on a MISS, and only into the array of the
        ! missing side -- and this construction needs the I array. All three
        ! candidate PAs already carry `jmp @r14 / nop`, so each install jumps
        ! into V and bounces straight back to the label parked in r14.
        ! ================================================================
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR := ASID_A
        nop
        nop
        mov.l   p_ret_a, r14
        mov.l   p_v_va, r1
        jmp     @r1                     ! install A: PA_A, non-global
        nop
ENTRY(_mh_ret_a)
        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR := ASID_B
        nop
        nop
        mov.l   p_ret_b, r14
        mov.l   p_v_va, r1
        jmp     @r1                     ! install B: A is non-global with
        nop                             ! asid_tag=ASID_A, so V misses again
ENTRY(_mh_ret_b)
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR := 0, a THIRD ASID --
        nop                             ! load-bearing: it is what makes the
        nop                             ! third fetch of V miss
        mov.l   p_ret_c, r14
        mov.l   p_v_va, r1
        jmp     @r1                     ! install C: PA_C, GLOBAL. The dedup
        nop                             ! scan latches on the FIRST overlap
ENTRY(_mh_ret_c)
        ! -> A evicted (first match found), B survives, C occupies A's slot.

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR := ASID_B (matches B)
        nop
        nop

        ! ================================================================
        ! THE RACE. r12/r13/r14 are non-banked and survive both handlers.
        ! The load's base (r13) and destination (r12) are DISJOINT, so a
        ! legitimate re-execution after the older fault is serviced is
        ! idempotent and lands the right value; only a load that never
        ! re-executes leaves the sentinel behind.
        ! ================================================================
        mov.l   p_after_race, r14       ! where page V bounces back to
        mov.l   p_data_va, r13          ! unmapped -> DMISS_R (OLDER)
        mov.l   p_v_va, r1              ! multi-hitting page (YOUNGER)
        mov     #0x55, r12              ! sentinel: load never committed
        jmp     @r1
        mov.l   @r13, r12               ! delay slot -- OLDER than @r1's fetch

ENTRY(after_race)
        ! ---- AT off before the checks; everything below is P0 identity. ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! (1) ANTI-VACUITY: at least one fault was taken.
        mov.l   p_log_ptr, r0
        mov.l   @r0, r1                 ! r1 = write pointer
        mov.l   p_log_base, r2          ! r2 = log base
        cmp/eq  r1, r2
        bf      1f
        mov     #1, r9
        bra     _bail
        nop
1:
        ! (2) ORDERING: the OLDER D-side fault must be delivered FIRST.
        mov.l   @r2, r3
        mov.l   p_tag_d, r4
        cmp/eq  r3, r4
        bt      2f
        mov     #2, r9
        bra     _bail
        nop
2:
        ! (3) the MULTI_HIT must then arrive, second.
        add     #4, r2
        cmp/hs  r1, r2                  ! r2 >= r1 -> only one entry logged
        bf      3f
        mov     #3, r9
        bra     _bail
        nop
3:
        mov.l   @r2, r3
        mov.l   p_tag_mh, r4
        cmp/eq  r3, r4
        bt      4f
        mov     #3, r9
        bra     _bail
        nop
4:
        ! (4) INSTRUCTION LOST: the older delay-slot load must have produced
        !     its value. Distinct fail code from (2) -- see header.
        mov.l   p_dataword, r4
        cmp/eq  r4, r12
        bt      5f
        mov     #4, r9
        bra     _bail
        nop
5:
        ! (5) the older fault must have been DMISS_R, not some other kind.
        mov.l   p_d_expevt, r0
        mov.l   @r0, r3
        mov.l   p_expevt_dmiss_r, r4
        cmp/eq  r3, r4
        bt      6f
        mov     #7, r9
        bra     _bail
        nop
6:
        mov     #0, r9
        bra     _done
        nop

_bail:
        mov.l   p_fail, r0
        jmp     @r0
        nop

        .align  2
p_mmucr:        .long   0xFF000010
p_asid_a:       .long   0x00000011      ! ASID_A
p_asid_b:       .long   0x00000022      ! ASID_B != ASID_A
p_dataword:     .long   0x5A5AC3C3      ! what the delay-slot load must yield
p_v_va:         .long   0x00020000      ! VPN V = 0x20
p_ret_a:        .long   _mh_ret_a
p_ret_b:        .long   _mh_ret_b
p_ret_c:        .long   _mh_ret_c
p_data_va:      .long   0x00030000      ! unmapped at race time -> DMISS_R
p_after_race:   .long   after_race
p_log_ptr:      .long   _log_ptr
p_log_base:     .long   _log
p_tag_d:        .long   1               ! TAG_D  -- entered VBR+0x400
p_tag_mh:       .long   2               ! TAG_MH -- entered VBR+0x100
p_d_expevt:     .long   _d_expevt
p_expevt_dmiss_r: .long 0x00000060
p_fail:         .long   _fail

! _done/_fail and their literal pool sit OUTSIDE the CONFIG_PRIV_ARCH guard,
! matching m8_multihit_ifetch.S: the .vect table above references both symbols
! unconditionally, so guarding them breaks the base-J2 link with "undefined
! reference to _done/_fail". With them out here a base build falls through
! from `start` straight into _done and reports PASS trivially; the real work
! only exists on the J4/PRIV overlay, where sim/mmu_sim.sh runs it as a guard.
#endif  ! CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop

ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: keep fail code loud
        bf      1f                      ! (PASS requires TEST_PASS_MAGIC, so a
        mov     #0x7F, r9               ! bare 0 reports Result=0, not PASS)
1:      mov.l   r9, @r0
        bra     _fail
        nop

        .align  2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ================================================================
        ! Vector table. VBR = _vbase; only two entry points are live:
        !   +0x100 General Illegal -- MULTI_HIT dispatches here
        !   +0x400 ALL SIX TLB fault kinds (they differ only by EXPEVT)
        ! ================================================================
        .balign 4
_vbase:
        .space  0x100, 0
        bra     _h_gi                   ! _vbase + 0x100
        nop
        .space  0x400 - 0x104, 0
        bra     _h_tlb                  ! _vbase + 0x400
        nop

        ! ================================================================
        ! D-side TLB fault handler. Appends TAG_D, records EXPEVT/SPC/TEA
        ! (last entry wins; a passing run enters here exactly once), maps the
        ! data page, and returns to the hardware SPC. Does NOT touch ASIDR:
        ! the multi-hit construction depends on ASIDR=ASID_B, so the mapping
        ! installed here is GLOBAL instead.
        !
        ! THE MAPPING IS INSTALLED BY CONSTANT VA, NOT FROM TEA. This is not
        ! a simplification, it is required: MEASURED on this exact scenario,
        ! the machine dispatches to VBR+0x100 for the younger I-side MULTI_HIT
        ! and the older D-side fault then lands ON TOP of that dispatch, one
        ! fetch later. TEA at that point carries the I-side multi-hit VA, not
        ! the load's address, so a TEA-driven handler installs a fresh
        ! overlapping entry on V (which cannot even reduce the multi-hit --
        ! each global install evicts only the FIRST of the two overlapping
        ! entries and adds one back) and never maps the data page, so the load
        ! re-faults forever. That livelock is what the first revision of this
        ! guard hit. Only this handler's own page can fault here, so the
        ! constant is exact and TEA is kept purely as a diagnostic.
        ! ================================================================
        .balign 4
_h_tlb:
        mov.l   Tlog_ptr, r1
        mov.l   @r1, r2
        mov.l   Tlog_end, r3
        cmp/hs  r3, r2                  ! log full -> the run is not converging
        bf      1f
        mov     #8, r9
        mov.l   Tfail, r0
        jmp     @r0
        nop
1:
        mov.l   Ttag_d, r3
        mov.l   r3, @r2
        add     #4, r2
        mov.l   r2, @r1

        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Td_expevt, r1
        mov.l   r0, @r1
        .word   0x0042                  ! STC SPC, r0
        mov.l   Td_spc, r1
        mov.l   r0, @r1                 ! diagnostic, never asserted on
        mov.l   Ttea_addr, r0
        mov.l   @r0, r2
        mov.l   Td_tea, r1
        mov.l   r2, @r1                 ! diagnostic, never asserted on

        ! ---- Publish the data page's TSB row and let the WALKER install it.
        ! The row is addressed THROUGH THE P1 ALIAS: AT is on here and the TSB
        ! is unmapped, so a P0 store from the handler would fault inside the
        ! handler. It is tagged with the ASID in force at the fault (ASID_B) --
        ! core/tlb_walk.vhd requires tag_lo = asidr EXACTLY, global bit or not.
        ! Then a plain RTE: the load retries, misses again, and the walker
        ! installs. The row SURVIVES the GI handler's TI flush, which is what
        ! keeps that flush from manufacturing a second, spurious DMISS_R.
        mov.l   Tdata_va, r2
        mov.l   Tslot, r0
        mov.l   r2, @r0
        mov.l   @r0, r3
        mov.l   Tp1, r0
        or      r0, r3
        mov.l   Tasid_b, r4
        mov.l   Tdata_ptel, r5
        mov.l   r5, @(8, r3)            ! data first ...
        mov.l   r4, @(4, r3)            ! ... tag_lo second ...
        mov.l   r2, @(0, r3)            ! ... tag_hi LAST (the commit point)
        rte                             ! PC <- SPC (hardware restart PC)
        nop

        .align  2
Tlog_ptr:       .long   _log_ptr
Tlog_end:       .long   _log_end
Tfail:          .long   _fail
Ttag_d:         .long   1
Td_expevt:      .long   _d_expevt
Td_spc:         .long   _d_spc
Td_tea:         .long   _d_tea
Ttea_addr:      .long   0xFF00000C
Tdata_va:       .long   0x00030000
Tdata_ptel:     .long   0x000300CD      ! PA 0x30000 identity | W|X|C|G|V
Tslot:          .long   0xFF000048      ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
Tp1:            .long   0x80000000
Tasid_b:        .long   0x00000022      ! ASID_B -- the ASID in force at the race

        ! ================================================================
        ! General Illegal handler = MULTI_HIT. Appends TAG_MH, records SPC
        ! (diagnostic only), asserts this really is a MULTI_HIT (EXPEVT and
        ! MMUFSR), then RESOLVES the multi-hit -- AT off, TI flush, reinstall
        ! the code map + a SINGLE mapping for V + the data page -- and
        ! returns to the HARDWARE SPC. It deliberately does not redirect SPC;
        ! see the header for why that would invalidate the measurement.
        ! ================================================================
        .balign 4
_h_gi:
        mov.l   Glog_ptr, r1
        mov.l   @r1, r2
        mov.l   Glog_end, r3
        cmp/hs  r3, r2                  ! log full -> the run is not converging
        bf      0f
        mov     #8, r9
        mov.l   Gfail, r0
        jmp     @r0
        nop
0:
        mov.l   Gtag_mh, r3
        mov.l   r3, @r2
        add     #4, r2
        mov.l   r2, @r1
        .word   0x0042                  ! STC SPC, r0
        mov.l   Gspc_at_mh, r1
        mov.l   r0, @r1                 ! diagnostic, never asserted on

        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Gexp_expevt, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #5, r9
        mov.l   Gfail, r0
        jmp     @r0
        nop
1:
        mov.l   Gfsr_addr, r0
        mov.l   @r0, r2                 ! r2 = MMUFSR
        mov.l   Gexp_fsr, r1
        cmp/eq  r1, r2
        bt      2f
        mov     #6, r9
        mov.l   Gfail, r0
        jmp     @r0
        nop
2:
        ! ---- Resolve: AT off + TI flush, then AT back on and RTE. There is
        ! no targeted single-entry invalidate, so the whole array goes.
        !
        ! Under LDTLB this handler then had to REINSTALL by hand (code map, a
        ! single mapping for V, the data page) because the flush left nothing
        ! behind. Under walker-only install that software reinstall is not
        ! merely unnecessary, it is how the multi-hit is resolved: the TSB
        ! SURVIVES a TI flush, and after the flush ASIDR is ASID_B, so the
        ! next fetch of V walks the ONE row hashed for (V, ASID_B) and
        ! installs exactly one entry. Re-installing over V by hand never
        ! converged -- each global install evicts only the FIRST of the two
        ! overlapping entries and adds one back -- whereas a single walk
        ! cannot produce two entries by construction.
        !
        ! The code superpage and the data page come back the same way, from
        ! their own rows, on demand. The data row was published by the D-side
        ! handler, so the flush still cannot manufacture a spurious second
        ! DMISS_R and perturb the order log.
        !
        ! Note the landing page is now PA_B, the row reachable under ASID_B,
        ! rather than PA_C. All three candidate PAs carry the same
        ! `jmp @r14 / nop` payload, so the recovery path is unchanged.
        mov.l   Gmmucr, r0
        mov     #4, r1
        mov.l   r1, @r0                 ! AT off + TI
        mov     #0, r1
        mov.l   r1, @r0                 ! TI released

        mov.l   Gmmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT back on
        rte                             ! PC <- SPC (hardware restart PC)
        nop

        .align  2
Glog_ptr:       .long   _log_ptr
Glog_end:       .long   _log_end
Gtag_mh:        .long   2
Gspc_at_mh:     .long   _spc_at_mh
Gexp_expevt:    .long   0x00000180
Gfsr_addr:      .long   0xFF00002C
Gexp_fsr:       .long   0x00001700
Gfail:          .long   _fail
Gmmucr:         .long   0xFF000010

        ! ---- Order log and diagnostics, inside the identity-mapped,
        ! writable code region. ----
        .balign 4
_log_ptr:       .long   0
_d_expevt:      .long   0xFFFFFFFF      ! unset sentinel
_d_spc:         .long   0xFFFFFFFF      ! diagnostic, never asserted on
_d_tea:         .long   0xFFFFFFFF      ! diagnostic, never asserted on
_spc_at_mh:     .long   0xFFFFFFFF      ! diagnostic, never asserted on
_log:           .rept   16
                .long   0
                .endr
_log_end:

! _code_end marks the end of everything that must be mapped BEFORE AT goes on:
! the body, the report epilogue, both handlers, the vector table, every
! literal pool, and the log.
ENTRY(_code_end)

        ! ---- The image must reach past the END of the guard's TSB: the
        ! ---- walker reads it by PHYSICAL address, and a physical alias is
        ! ---- backed by SRAM only within the loaded image extent. (.org is
        ! ---- section-relative and .text starts at 0x1000, so 0x15000 ->
        ! ---- 0x16000, just past the TSB's end at 0x00016000.)
        .org 0x15000

#endif  ! CONFIG_PRIV_ARCH
