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
! UNIMPLEMENTED (future work; do NOT assume coverage):
!   B  N x (faulting LOAD  -> IMISS)
!   D  N x (faulting STORE -> IMISS)
! Both alternating shapes are still uncovered.
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
!   Result=6 / 8        -> real defect: an access was dropped or doubled
!   Result=2 / 4        -> real defect: a page holds the wrong data
!   Result=0x10 / 0x12  -> vacuity: every access ran but the pages were mapped
!
! ---- three traps this file already stepped on (do not re-introduce) ----
!  1. Do NOT extend the identity-map range down to VA 0.  A VPN==0 entry makes
!     the very first D-side miss hang (the handler is never even entered); map
!     from `start`'s page instead.  `start` is .balign PAGE_SZ for that reason.
!  2. The handler must install STUB (instruction) pages with U=0.  0xE8 sets U,
!     and a kernel instruction fetch from a U=1 page is blocked by SMEP, so an
!     IMISS installed with 0xE8 re-faults forever.  The handler picks 0xC8 for
!     any VA below the data pool and 0xE8 inside it -- which is why the layout
!     contract below puts ALL the stub pages (A, C, D0..D9, the leg-D
!     trampoline) BELOW the first data page.
!  3. FLUSH_TLB drops AT first.  Pulsing MMUCR.TI with AT=1 invalidates the
!     page the CPU is currently executing from, so the very next fetch IMISSes
!     into a handler whose own page is also gone -- an unrecoverable double
!     fault.  With AT=0 the flush and the code re-map run untranslated, exactly
!     like the preamble, and AT goes back on only once the map is rebuilt.
!
! Layout contract: [ code | _code_end | stub pages | data pages ].  Everything
! below _code_end is identity-mapped by the preamble (and re-mapped by
! FLUSH_TLB) and must never fault; everything above it is unmapped so it faults
! on first touch.
!
! TLB budget: the TLB has 32 entries (core/tlb.vhd).  FLUSH_TLB runs at the leg
! boundaries (never inside a measured window) so no leg's live set has to share
! with another's.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   STC PTEH,r1 = 0x0153   LDC r0,VBR  = 0x402E   LDC r0,PTEH  = 0x405E
!   LDC r0,PTEL = 0x406E   LDC r0,ASIDR= 0x407E   LDTLB = 0x0038  LDTLB.RN = 0x0078
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; _fail still clamps r9==0
! to 0x7F.
#include "sim_instr.h"
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
        mov.l   r1, @r0                 ! TI: invalidate all 32 entries
        mov     #0, r1
        mov.l   r1, @r0                 ! TI released
        mov.l   \pfx\()code_start, r2
        mov.l   \pfx\()code_end, r3
1:      mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov     r2, r0
        mov.l   \pfx\()code_flags, r1
        or      r1, r0                  ! PTEL = page | 0xC8 (kernel code, U clear)
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        mov.l   \pfx\()page_sz, r0
        add     r0, r2
        cmp/hs  r3, r2
        bf      1b
        mov.l   \pfx\()mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on
        .endm

        .ifne N_FAULTS - 10
        .error "legs A/C/D staging blocks are hand-unrolled for N_FAULTS==10"
        .endif

        ! start must be page-aligned: the map loop below walks it in PAGE_SZ
        ! steps (and see trap 1 in the header -- the range must not reach VA 0).
        .balign PAGE_SZ

ENTRY(start)
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

        ! ---- Identity-map every code page: start .. _code_end. ----
        ! The body is larger than one page, so all of it (preamble, handler,
        ! verifier, literal pools) must be mapped BEFORE AT goes on -- otherwise
        ! the first fault's own handler fetch IMISSes and double-faults.
        mov.l   p_code_start, r2
        mov.l   p_code_end, r3
1:      mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov     r2, r0
        mov.l   p_code_flags, r1
        or      r1, r0                  ! PTEL = page | 0xC8 (kernel code, U clear)
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
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
p_code_flags:   .long 0x000000C8
p_page_sz:      .long PAGE_SZ
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
pC_code_start:  .long start
pC_code_end:    .long _code_end
pC_code_flags:  .long 0x000000C8
pC_page_sz:     .long PAGE_SZ
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
6:
        ! ---- Disable AT before handing the result to the harness. ----
        mov.l   qC_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov     #0, r9
        bra     _done
        nop

        .align 2
qC_mmucr:       .long 0xFF000010
qC_spill:       .long _spill_C
qC_fc:          .long _fault_count
qC_dtab:        .long _dtab_C
qC_sent:        .long 0xB00BC0DE

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

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- VA-driven handler at VBR+0x400 (all six TLB fault kinds) ----
        ! Runs with SR.RB=1, so its bank-1 scratch does not touch the leg's
        ! bank-0 registers.
        .balign 4
        .space 0x400, 0
        .balign 4
_v_drain:
        .word   0x0153                  ! STC PTEH, r1 -- HW-captured faulting VPN
        mov.l   Hpagemask, r0
        and     r0, r1                  ! r1 = page base
        ! Pick the PTEL flags from the layout contract: ALL the stub pages (A,
        ! C, D0..D9 and the leg-D trampoline) sit BELOW the first data page, so
        ! a fault under _dpage_A0 is an I-side stub fetch and must be installed
        ! with U=0 -- installing 0xE8 (U=1) there makes the kernel fetch fault
        ! forever under SMEP.
        mov.l   Hdbase, r0              ! _dpage_A0: start of the data pool
        cmp/hs  r0, r1                  ! T = (page >= first data page)
        bt      1f
        mov.l   Hcflags, r0             ! stub page: 0xC8 (kernel code, U clear)
        bra     2f
        nop
1:      mov.l   Hflags, r0              ! data page: 0xE8
2:      or      r1, r0                  ! PTEL = page | flags
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   Hcount, r0              ! non-vacuity: count this fault
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        .word   0x0078                  ! LDTLB.RN -- install + return atomically
_h_fail_spin:
        bra     _h_fail_spin
        nop
        .align 2
Hpagemask:      .long 0xFFFFF000
Hflags:         .long 0x000000E8
Hcflags:        .long 0x000000C8
Hdbase:         .long _dpage_A0
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


#endif
