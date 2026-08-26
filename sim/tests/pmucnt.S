! pmucnt.S -- the PMU counters count the right thing, to the count.
!
! Covers the PMU block at 0xFF001000 (core/perf.vhd, decoded in
! core/datapath.vhm; docs/pmu/perf-counters.md, docs/soc/p4-mmio-map.md 3
! "PMU (Performance Monitoring Unit)").
!
! WHY EVERY ASSERTION HERE IS AN EXACT DELTA AND NOT "> 0". A counter that
! increments AT ALL looks like a working counter: a cycle counter mis-wired to
! the instruction-dispatch event, an instruction counter that also counts the
! second slot of multi-slot ops, and a reference counter that counts a held
! request once per stall cycle all pass a "did it move" test. Each check below
! pins a delta that only the intended event produces.
!
! THE WINDOW-DIFFERENCE TECHNIQUE. Each phase takes three or four snapshots of
! the same counter, separated by nop blocks of 0, 8 and 16 instructions, using
! an IDENTICAL read sequence every time. The cost of the read sequence itself
! therefore appears in every delta and cancels out of the DIFFERENCE of two
! deltas -- so the expectations below are pure architecture (8 instructions in
! an 8-nop block) with no measured magic number in them and nothing that a
! pipeline change may legitimately move.
!
! Reads use displacement addressing off one base register (r8 = 0xFF001000) so
! that no literal-pool load lands INSIDE a measured window; a literal load is a
! D-bus access and would show up in PMDAR.
!
! Result codes (r9):
!   0x01  PMIDR != 0x4A5020FF -- the block is absent, or its identity register
!         disagrees with PMU_NUM_CNT/PMU_CNT_W in core/perf_pkg.vhd
!   0x02  PMCR does not read 0x00000001 out of reset (EN must reset SET)
!   0x03  0xFF001100 does not read as zero -- bits [11:8] of the PMU page are
!         not being decoded, so every register has 16 writable aliases
!   0x04  0xFF001120 does not read as zero -- same defect, counter window
!   0x05  PMCYC itself reads zero -- reserved anti-vacuity partner for 0x03
!         and 0x04, which would both pass on a block that answers nowhere
!   0x10  PMINS delta over an 8-nop block is not exactly 8 (window 2)
!   0x11  PMINS delta over an 8-nop block is not exactly 8 (window 3)
!   0x20  PMCYC delta is zero -- reserved anti-vacuity
!   0x21  PMCYC does not advance linearly across two equal nop blocks
!   0x30  PMDAR delta over 8 loads is not exactly 8 more than over 8 nops
!   0x31  PMINS deltas differ between the nop window and the load window --
!         the two windows hold the same instruction count by construction
!   0x40  PMCYC deltas are IDENTICAL for the nop and load windows, i.e. PMCYC
!         is tracking instructions rather than cycles
!   0x50  PMIFR did not move -- reserved anti-vacuity
!   0x51  PMIFR does not advance linearly across two equal nop blocks
!   0x60  PMDAW did not move over a window containing 8 loads
!   0x61  PMDAW over the load window is not greater than over the nop window
!   0x70  PMINS deltas differ between a window of 8 nops and a window of 8
!         MOV.L @Rm+,Rn -- both are 8 INSTRUCTIONS, so PMINS is counting
!         SLOTS (or something else per-slot) rather than instructions
!
! No MMU translation is set up and none is needed: P4 is untranslated, and this
! guard never touches a mapped page. The repo's no-identity-mapping rule is
! therefore not engaged -- there is no mapping here at all.
#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

! Counter offsets from the PMU base, in bytes. These ARE the counter indices
! times four, offset by 0x20 -- see core/perf_pkg.vhd.
#define O_PMCR   0
#define O_PMOVF  4
#define O_PMIDR  8
#define O_PMCYC  32
#define O_PMINS  36
#define O_PMIFR  40
#define O_PMIFW  44
#define O_PMDAR  48
#define O_PMDAW  52
#define O_PMWLK  56
#define O_PMWHT  60

        .macro  NOP8
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        .endm

        ! Post-increment loads. MOV.L @Rm+,Rn is one of the MULTI-SLOT forms
        ! (core/decode/decode_core.vhm's delay_slot_o comment names
        ! "MOV.{B,W,L} @Rm+,Rn, CAS.L, MAC.{L,W}" as the ops that spend slot0
        ! on the access), which is exactly what phase 6 needs: a window whose
        ! SLOT count differs from its INSTRUCTION count.
        .macro  AINC8 rbase, rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        mov.l   @\rbase+, \rdst
        .endm

        .macro  LOAD8 rbase, rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        mov.l   @\rbase, \rdst
        .endm

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

        mov.l   p_pmubase, r8           ! r8 = 0xFF001000, kept live throughout
        mov.l   p_scratch, r11          ! r11 = a plain P0 word to load from

        ! ================= 1: the block identifies itself =================
        ! An undecoded P4 offset reads as a hard zero and raises nothing
        ! (docs/soc/p4-mmio-map.md, "Undecoded P4 offsets fail SILENTLY"), so
        ! without a magic there is no way to tell "PMU absent" from "PMU
        ! present and idle". Everything below would pass vacuously on a build
        ! that decoded nothing, because zero minus zero is zero -- except that
        ! the exact-delta checks demand 8, not 0. This check makes the failure
        ! immediate and legible rather than leaving it to check 0x10.
        mov.l   @(O_PMIDR,r8), r1
        mov.l   p_idr_exp, r2
        cmp/eq  r1, r2
        mov     #0x01, r9
        bf      _fail

        ! ================= 2: PMCR resets with EN set =====================
        mov.l   @(O_PMCR,r8), r1
        mov     #1, r2
        cmp/eq  r1, r2
        mov     #0x02, r9
        bf      _fail

        ! ================= 3: the page decodes 12 bits, not 8 =============
        ! Every other arm of the P4 chain in core/datapath.vhm matches on
        ! ma_ad(7 downto 0) alone; the PMU arm deliberately matches on
        ! ma_ad(11 downto 0). If it is ever "tidied" back to 8 bits for
        ! symmetry, 0xFF001100 becomes a second, WRITABLE PMCR and 0xFF001120
        ! a second, WRITABLE PMCYC -- addresses the P4 map records as
        ! reserved. The same edit also makes the three PMU decode lines match
        ! the P4_DECODE_RE in jcore-workspace scripts/check-doc-facts.py,
        ! which would then read them as P4 offsets 0x000/0x004/0x008 -- which
        ! belong to PTEH, PTEL and TTB. This check is what turns both of those
        ! from a review catch into a test failure.
        mov.l   p_alias1, r1            ! 0xFF001100 = PMCR + 0x100
        mov.l   @r1, r2
        tst     r2, r2
        mov     #0x03, r9
        bf      _fail
        mov.l   p_alias2, r1            ! 0xFF001120 = PMCYC + 0x100
        mov.l   @r1, r2
        tst     r2, r2
        mov     #0x04, r9
        bf      _fail
        ! Anti-vacuity partner. "Reads zero" is what an UNDECODED P4 offset
        ! does -- and also what a completely dead block does, so the two checks
        ! above are worth nothing without a live register to contrast against.
        ! PMCYC has been free-running since reset and cannot be zero here.
        mov.l   @(O_PMCYC,r8), r2
        tst     r2, r2
        mov     #0x05, r9
        bt      _fail

        ! ================= Phase 1: PMCYC and PMINS linearity =============
        ! Four snapshots, three windows: 0 nops, 8 nops, 16 nops.
        mov.l   @(O_PMCYC,r8), r1
        mov.l   @(O_PMINS,r8), r2
        mov.l   @(O_PMCYC,r8), r3
        mov.l   @(O_PMINS,r8), r4
        NOP8
        mov.l   @(O_PMCYC,r8), r5
        mov.l   @(O_PMINS,r8), r6
        NOP8
        NOP8
        mov.l   @(O_PMCYC,r8), r7
        mov.l   @(O_PMINS,r8), r10

        ! ---- Derive the three window deltas BEFORE destroying any snapshot.
        ! ---- (An earlier draft of this guard folded the subtractions in
        ! ---- place and silently compared s2 - (s1 - s0) against 8.)
        mov     r4, r12
        sub     r2, r12                 ! r12 = ins(w1), the read sequence alone
        mov     r6, r13
        sub     r4, r13                 ! r13 = ins(w2) = ins(w1) + 8
        mov     r10, r14
        sub     r6, r14                 ! r14 = ins(w3) = ins(w1) + 16

        ! ---- PMINS: each 8-nop block must add EXACTLY 8. The read sequence is
        ! ---- identical in all three windows, so its own instruction count
        ! ---- cancels out of the difference and what is left is the nop block:
        ! ---- 8 instructions, no more and no fewer. A counter that fired once
        ! ---- per SLOT rather than once per instruction would still pass on
        ! ---- nops -- which is why phase 2 repeats the comparison against a
        ! ---- window of loads, and phase 3 against cycles.
        mov     r13, r0
        sub     r12, r0                 ! r0 = ins(w2) - ins(w1)
        cmp/eq  #8, r0
        mov     #0x10, r9
        bf      _fail
        mov     r14, r0
        sub     r13, r0                 ! r0 = ins(w3) - ins(w2)
        cmp/eq  #8, r0
        mov     #0x11, r9
        bf      _fail

        ! ---- PMCYC over the same three windows must advance LINEARLY: two nop
        ! ---- blocks of equal length cost equal cycles, whatever a nop costs on
        ! ---- this pipeline. No magic constant, so a legitimate pipeline change
        ! ---- does not falsify this guard.
        mov     r3, r12
        sub     r1, r12                 ! r12 = cyc(w1)
        mov     r5, r13
        sub     r3, r13                 ! r13 = cyc(w2)
        mov     r7, r14
        sub     r5, r14                 ! r14 = cyc(w3)
        mov     r13, r0
        sub     r12, r0                 ! r0 = cyc(w2) - cyc(w1) = cost of 8 nops
        tst     r0, r0
        mov     #0x20, r9
        bt      _fail                   ! reserved: the counter is dead
        mov     r0, r12                 ! keep the per-block cost
        mov     r14, r0
        sub     r13, r0                 ! r0 = cyc(w3) - cyc(w2)
        cmp/eq  r12, r0
        mov     #0x21, r9
        bf      _fail

        ! ================= Phase 2: PMDAR is a REFERENCE counter ==========
        ! Two windows of the SAME instruction count: 8 nops, then 8 loads from
        ! one address. A P4 CSR read issues no bus transaction (datapath.vhm
        ! serves it internally), so the read sequence contributes nothing to
        ! PMDAR and the difference between the two windows is exactly the 8
        ! loads. A counter that counted `db_o.en` levels instead of completed
        ! accesses would over-count here by the stall cycles.
        !
        ! THE SEPARATING nop AFTER EACH BLOCK IS LOAD-BEARING, and finding out
        ! why is a result of this guard. The counters are read as REGISTERED
        ! values, so an event whose cycle coincides with the cycle the P4 read
        ! is served is not yet in the value returned -- and datapath.vhm issues
        ! the next access in the SAME process evaluation that clears the
        ! previous one on ack, so without the nop the eighth load acks exactly
        ! as the following counter read is served. Measured: the difference is
        ! 7 without the nop and 8 with it. That is not a counter defect, it is
        ! what "sample the counter" means; the nop appears after BOTH blocks so
        ! the two windows stay structurally identical.
        mov.l   @(O_PMDAR,r8), r1
        mov.l   @(O_PMINS,r8), r2
        NOP8
        nop
        mov.l   @(O_PMDAR,r8), r3
        mov.l   @(O_PMINS,r8), r4
        mov.l   @(O_PMDAR,r8), r5
        mov.l   @(O_PMINS,r8), r6
        LOAD8   r11, r12
        nop
        mov.l   @(O_PMDAR,r8), r7
        mov.l   @(O_PMINS,r8), r10

        sub     r1, r3                  ! r3 = dar(nop window)
        sub     r5, r7                  ! r7 = dar(load window)
        sub     r3, r7                  ! r7 = difference
        mov     #8, r0
        cmp/eq  r0, r7
        mov     #0x30, r9
        bf      _fail

        sub     r2, r4                  ! r4 = ins(nop window)
        sub     r6, r10                 ! r10 = ins(load window)
        cmp/eq  r4, r10
        mov     #0x31, r9
        bf      _fail

        ! ================= Phase 3: PMCYC is not PMINS ====================
        ! Same two windows again. Phase 2 has just proved their INSTRUCTION
        ! counts are equal; if PMCYC were wired to the dispatch event its two
        ! deltas would be equal too. They must not be: a load costs more cycles
        ! than a nop.
        mov.l   @(O_PMCYC,r8), r1
        NOP8
        nop
        mov.l   @(O_PMCYC,r8), r3
        mov.l   @(O_PMCYC,r8), r5
        LOAD8   r11, r12
        nop
        mov.l   @(O_PMCYC,r8), r7

        sub     r1, r3                  ! r3 = cyc(nop window)
        sub     r5, r7                  ! r7 = cyc(load window)
        cmp/eq  r3, r7
        mov     #0x40, r9
        bt      _fail

        ! ================= Phase 4: PMIFR linearity =======================
        ! Instruction-fetch references. Constant-free again: two nop blocks of
        ! equal length must produce equal fetch traffic.
        mov.l   @(O_PMIFR,r8), r1
        mov.l   @(O_PMIFR,r8), r3
        NOP8
        mov.l   @(O_PMIFR,r8), r5
        NOP8
        NOP8
        mov.l   @(O_PMIFR,r8), r7

        mov     r3, r12
        sub     r1, r12                 ! r12 = ifr(w1)
        mov     r5, r13
        sub     r3, r13                 ! r13 = ifr(w2)
        mov     r7, r14
        sub     r5, r14                 ! r14 = ifr(w3)
        mov     r13, r0
        sub     r12, r0                 ! r0 = fetches added by one 8-nop block
        tst     r0, r0
        mov     #0x50, r9
        bt      _fail                   ! reserved: the counter is dead
        mov     r0, r12
        mov     r14, r0
        sub     r13, r0
        cmp/eq  r12, r0
        mov     #0x51, r9
        bf      _fail

        ! ================= Phase 5: PMDAW counts WAIT CYCLES ==============
        ! The complement of PMDAR over the same outstanding-access cycles. A
        ! window of 8 loads must wait; a window of 8 nops has no data access to
        ! wait for, so its only PMDAW contribution is the read sequence's --
        ! which is identical in both windows.
        mov.l   @(O_PMDAW,r8), r1
        NOP8
        nop
        mov.l   @(O_PMDAW,r8), r3
        mov.l   @(O_PMDAW,r8), r5
        LOAD8   r11, r12
        nop
        mov.l   @(O_PMDAW,r8), r7

        sub     r5, r7                  ! r7 = daw(load window)
        tst     r7, r7
        mov     #0x60, r9
        bt      _fail                   ! reserved: the counter is dead
        sub     r1, r3                  ! r3 = daw(nop window)
        cmp/hi  r3, r7                  ! unsigned: r7 > r3 ?
        mov     #0x61, r9
        bf      _fail

        ! ================= Phase 6: PMINS counts INSTRUCTIONS, not SLOTS ==
        ! Every window so far has held only single-slot instructions, so a
        ! counter wired to the SLOT-commit pulse instead of the instruction
        ! dispatch would have passed all of them -- verified by mutation, not
        ! assumed: `pmu_ev(PMU_INS) <= slot` left phases 1-5 entirely green.
        ! This window swaps in eight MOV.L @Rm+,Rn, a multi-slot form, against
        ! eight nops. Both blocks are 8 INSTRUCTIONS; only their SLOT counts
        ! differ, so the two PMINS deltas must be EXACTLY equal.
        mov.l   @(O_PMINS,r8), r1
        NOP8
        nop
        mov.l   @(O_PMINS,r8), r3
        mov     r11, r13                ! reload the walking base
        mov.l   @(O_PMINS,r8), r5
        AINC8   r13, r12
        nop
        mov.l   @(O_PMINS,r8), r7

        sub     r1, r3                  ! r3 = ins(nop window)
        sub     r5, r7                  ! r7 = ins(post-increment window)
        cmp/eq  r3, r7
        mov     #0x70, r9
        bf      _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_pmubase: .long 0xFF001000              ! PMU block base (P4, privileged)
p_alias1:  .long 0xFF001100              ! must NOT alias PMCR  (check 0x03)
p_alias2:  .long 0xFF001120              ! must NOT alias PMCYC (check 0x04)
p_idr_exp: .long 0x4A5020FF              ! magic "JP", width 32, 8 counters
p_scratch: .long 0x00002000              ! plain P0 RAM, backed by the cosim
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: never write the PASS
        bf      1f                      ! token from the failure path.
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC
