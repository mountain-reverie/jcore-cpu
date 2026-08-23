! mmup4priv.S -- P4 is supervisor-only. A USER-mode (SR.MD=0) data access to
! the P4 control-register segment must be REFUSED and must raise the SH-4 CPU
! address error.
!
! WHY THIS GUARD EXISTS. core/datapath.vhm gated the whole P4 MMU-register
! block on `seg_v = SEG_P4` and on nothing else -- never on this.sr.md. P4 is
! not TLB-translated (core/cpu.vhd asserts d_at_translated only for SEG_P0 /
! SEG_P3), so no protection bit could intervene either, and there was no
! address-error path at all. A user-mode `MOV.L Rm,@Rn` to 0xFF000010 therefore
! wrote MMUCR -- turning address translation off -- and one to 0xFF000014 wrote
! TSBBR, repointing the hardware TSB walker at attacker-chosen memory. Complete
! user->supervisor escape, from unprivileged code, with two instructions.
!
! THE GAP THAT LET IT THROUGH. sim/tests/mmup4alias.S covers every one of these
! registers, but only from SUPERVISOR mode: it proves each P4 alias reads back
! what LDC wrote. Nothing in the suite asserted that a user-mode access is
! DENIED, so the missing gate was invisible. This guard is the negative case.
!
! ARCHITECTURAL EXPECTATION (docs/soc/p4-mmio-map.md §1: P4 accesses are
! "untranslated (no MMU lookup), uncached, and accessible only with SR.MD = 1";
! docs/priv-arch/design-spec.md §4.5 puts address error on the general-exception
! vector VBR+0x100):
!
!   user READ  of any P4 address -> PC <- VBR+0x100, MMUFSR = 0x1818
!   user WRITE to any P4 address -> PC <- VBR+0x100, MMUFSR = 0x1919
!   EXPEVT = 0x0C0 in BOTH cases
!   SPC = the faulting instruction (restart semantics, as for DPROT_R/W)
!   TEA = the refused address
!   the destination GPR of a refused load is NOT written
!   every P4 CSR keeps the value supervisor code left in it
!
! ON EXPEVT -- A DELIBERATE, RECORDED DEVIATION FROM SH-4.
! SH-4 reports 0x0E0 (read) / 0x100 (write) for a CPU address error. This guard
! deliberately does NOT expect those: it expects 0x0C0, the code carried by the
! DPROT microcode entries the violation is dispatched through.
!
! That is DEFERRED BY CHOICE, not blocked by the hardware. The measurement, and
! what the real codes would actually cost, live in ONE place: jcore-cpu/core/
! components_pkg.vhd, the tlb_exc_kind_t comment. Deliberately not restated
! here -- restating it is how the claim it replaced drifted in the first place.
!
! What is NOT deviating: the VECTOR is VBR+0x100, which IS the architecturally
! correct one for an address error (priv-arch/design-spec.md §4.5); the fault is
! precise, with SPC on the faulting instruction; and the read/write direction is
! not lost -- MMUFSR carries it, which is precisely that register's stated
! purpose (mmu/hardware-spec.md §2.11: "EXPEVT alone cannot distinguish every
! fault cause", written of DPROT_R/W, which likewise share 0x0C0).
!
! Checks 2 and 5 assert BOTH the shared EXPEVT and the distinct MMUFSR kind.
! When the decoder does gain the real codes, p_expevt_val -- and _chk_expevt's
! single use of it -- is the only thing in this file that moves.
!
! MMUFSR layout (mmu/hardware-spec.md §2.11):
!   [12] VALID  [11:8] KIND  [7:5] rsvd(0)
!   [4] USER  [3] PROT  [2] ITLB  [1] INITIAL(0)  [0] WRITE
! KIND 1..7 are the TLB causes; 8 and 9 are the two P4 privilege violations.
!   user read  = VALID | KIND 8 | USER | PROT           = 0x1818
!   user write = VALID | KIND 9 | USER | PROT | WRITE   = 0x1919
! The full 32-bit word is compared, not a masked subset -- same rule as
! sim/tests/mmufsr.S, and for the same reason: it pins bits [31:13] and [7:5] to
! zero, which linux@jcore's entry.S depends on.
!
! MECHANISM. Each probe is one round trip:
!   supervisor: seed r4 (P4 address) / r5 (attack value) / r6 (poison),
!               zero the fault counter, clear SR.MD, execute ONE access.
!   hardware:   refuses it and vectors to _v_gen (= VBR+0x100).
!   _v_gen:     records EXPEVT and MMUFSR, bumps the fault count, sets SPC+2 and
!               SSR := supervisor (MD=1, RB=0), and RTEs -- so control resumes
!               in SUPERVISOR mode at the instruction after the probe and the
!               straight-line supervisor code just continues.
! SPC+2 is not a guess: for a fault dispatched through the DPROT microcode SPC
! is the faulting instruction's own PC (mmu/hardware-spec.md §5 "TLBPC-4
! (faulting-instruction restart PC)", pinned exactly by sim/tests/mmupcprobe.S),
! and every probe here is a 2-byte instruction that is not in a delay slot.
! Skipping rather than restarting is what makes the sweep terminate.
!
! ON THE UNFIXED RTL the very first probe does not fault: the load succeeds,
! the fault count stays 0 and check 1 fails with Result=1. (It also stays in
! user mode, so the next `stc sr` traps as General Illegal, whose MMUFSR is not
! 0x1818 -- check 2 catches that too. Either way: RED.)
!
! AT stays 0 throughout. The gate must hold with translation disabled -- that
! is the configuration in which the escape is cheapest -- and it keeps the
! guard free of TLB/TSB setup, so a failure here can only be the privilege
! gate.
!
! Register map (r8-r15 are unbanked, so they survive the RB=1 handler):
!   r8  probe-table pointer      r9  failure code
!   r10 fault count              r11 MMUFSR of the last fault
!   r12 expected MMUFSR, then the base-restore witness (checks 11-14)
!   r13 EXPEVT of the last fault r14 poison constant   r15 SP
! The handler touches only r0-r3 (bank 1 while RB=1), r10, r11 and r13. r12 is
! reused as a witness ONLY after the sweeps are done, and specifically because
! the handler does not write it -- r13 would have been clobbered mid-probe.
!
! Failure codes:
!   1  user READ  raised no exception, or more than one   <-- the escape
!   2  user READ  reported the wrong MMUFSR (expected 0x1818)
!   3  a refused LOAD wrote its destination register (state leak)
!   4  user WRITE raised no exception, or more than one   <-- the escape
!   5  user WRITE reported the wrong MMUFSR (expected 0x1919)
!   6  a refused STORE landed -- some P4 CSR moved when it must not have
!   7  TEA does not hold the last refused address
!   8  supervisor access to the same P4 register stopped working
!   9  a fault reached VBR+0x400 (TLB vector) -- wrong class entirely
!  10  a fault reported the wrong EXPEVT (expected 0x0C0)
!  11  user @Rn+ load  raised no exception, or more than one
!  12  user @Rn+ load  did not restore its pre-increment base
!  13  user @-Rn store raised no exception, or more than one
!  14  user @-Rn store did not restore its pre-decrement base
!  15  user MOV.B to MMUCR raised no exception
!  16  user MOV.W to MMUCR raised no exception
!  17  TSBSLOT moved across the user sweeps
!  18  the TSBVICT victim LFSR advanced on a refused user read
!
! Codes 3 and 6 are shared by design, and only ever by probes asserting the
! SAME defect: 3 is always "a refused load wrote its destination", 6 is always
! "a refused store landed". Every DISTINCT defect has its own id.
!
! Note that execution order is not numeric order -- 17 and 18 run before 8,
! because check 8 rewrites TSBBR and TSBSLOT is a function of it (see there).
!
! MUTATION EVIDENCE (measured 2026-08-22; a guard that has never been shown to
! fail proves nothing, and several of these checks pass vacuously without the
! specific probe that reaches them):
!   unfixed RTL, whole gate removed         -> Result=1   (the escape itself)
!   ma_* shadow widening reverted           -> Result=12
!   this.ma_predec forced '0'               -> Result=14
!   refusal leaks the TSBVICT LFSR step     -> Result=18
!   gate narrowed to `mem.size = long`      -> Result=15
!   cpu.vhd fva forced to 0 (TEA channel)   -> Result=7
!   gate narrowed to `p4_sel_v /= P4_NONE`  -> SRAM invalid-read + ACK timeout
!                                              on 0xFF000034 (hard red, no
!                                              numeric code: the access escapes
!                                              to the external bus and wedges)
! The fva line pins the one genuinely clever mechanism here: the refused VA
! reaches cpu.vhd through TEA rather than a dedicated port, and check 7 is what
! makes a corrupted channel visible instead of silent.
!
! The last line is why _p4tab carries UNDECODED P4 offsets. Narrowing the gate
! to decoded registers is the natural-looking "optimisation", and without those
! entries the whole guard stays green while a user-mode access to 0xFF000034
! escapes the CPU onto the external bus. Note the failure mode is a wedge
! rather than a Result code -- that is the bus rejecting an address the core
! should never have emitted, which is the point.
!
! Note the second line especially: under that mutation checks 1-10 ALL PASS.
! The plain-@Rn probes cannot see a stale restart shadow, because ma_autoupd
! and ma_predec are '0' for a plain access either way -- which is exactly why
! checks 11-14 exist and why they use the auto-update addressing forms.
!
! COVERAGE NOTE. Every P4 register with a WRITE case in datapath.vhm is pinned
! against a user write: MMUCR/TTB/TSBBR/TSBCFG/TRA + PTEL/ASIDR by check 6, TEA
! by check 7, TSBSLOT by check 17, TSBVSEED by check 18 (a leaked reseed would
! change the nomination sequence). PTEH is excluded on purpose -- the fault
! capture rewrites it from the faulting VA by design.
!
! HOW THIS BRANCH'S SUITE RESULT IS QUOTED, corrected. The commit that adds
! this guard -- "fix(mmu): require SR.MD=1 for the P4 MMU-register path" --
! RECORDED the regression as an aligned block reading
!
!   full MMU / priv-arch suite      108/108 PASS, 0 FAIL, 0 SKIP
!
! and that FORM is wrong. That message has since been reworded: it now states
! the run as "==> all guards PASSED" and gives 108 as a count over the
! runner's per-guard "  PASS  <name>" lines. So the offending form is quoted
! HERE, in the file, because this is the copy a reader can still find -- the
! log no longer carries it.
!
! sim/mmu_sim.sh prints one "  PASS  <name>" or
! "  FAIL  <name>" line per guard and one trailing "==> all guards PASSED".
! It has no aggregate of any kind -- no total, no ratio, no "0 FAIL" -- and no
! script in this repository has any notion of SKIP at all, so "0 SKIP" is
! describing a column that does not exist. Set out in a column like that, a
! hand tally reads as a capture.
!
! The 108 itself stands, and is not re-stated from a run here: it is 107 (the
! count recorded for master by "shadow an ITLB fill into the DTLB, one way
! only", a68c765 -- a merged commit, so that SHA will not move) plus this
! guard, and the +1 is checkable by eye -- the only change this branch makes
! to sim/mmu_sim.sh is inserting `mmup4priv` into the cpu_tb guard list. The
! MUTATION EVIDENCE table above is unaffected; those Result codes are real
! captures. When the total is wanted, count it and say so:
! `... | grep -c '^  PASS'`.
!
! Note the shape of both citations above, because this block has already been
! invalidated once by a reword: an UNMERGED commit is named by its subject
! line, never by a SHA that a rebase will silently retire.

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

        ! FAIL_BF <code> -- "load <code> into r9 and jump to _fail_at if T=0".
        ! The checks after the two sweeps sit further from _fail_at than BF's
        ! 8-bit displacement (+/-254 bytes) reaches. A bare `bf _fail_at`
        ! still assembles there, but only because the assembler rewrites it
        ! into a longer sequence -- warning as it does so -- and a guard that
        ! builds with warnings trains you to ignore them. BT over an explicit
        ! BRA (12-bit displacement) says the same thing in range, silently.
        .macro  FAIL_BF code
        bt      8887f
        mov     #\code, r9
        bra     _fail_at
        nop
8887:
        .endm

        ! ENTER_USER -- drop to user mode (SR.MD=0) and let the new SR commit.
        ! A macro, not six copies, precisely because the four NOPs are load
        ! bearing: LDC SR has pipeline latency, and a copy that lost a NOP would
        ! execute its probe while still privileged. The probe would then be
        ! SERVED, the check would report "no exception", and the failure would
        ! look like a broken gate rather than a broken preamble. One definition
        ! means every probe drains identically by construction.
        .macro  ENTER_USER
        stc     sr, r1
        mov.l   p_mdmask, r2
        and     r2, r1
        ldc     r1, sr
        nop
        nop
        nop
        nop
        .endm

! Raw encodings (the assembler does not know the J4 privileged CSRs):
!   STC SPC,r0   = 0x0042      LDC r0,SPC  = 0x404E
!   STC SSR,r1   = 0x0132      LDC r1,SSR  = 0x413E
!   LDC r0,VBR   = 0x402E

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

        ! ---- bank 0 ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR so that VBR+0x100 = _v_gen ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR
        nop
        nop

        mov.l   p_poison, r14

        ! ================= seed the writable P4 CSRs (supervisor) =========
        ! Distinct per register, so a user write that lands on the WRONG CSR
        ! is caught by check 6 just as surely as one that lands on the right
        ! one. MMUCR is seeded 0 -- AT must stay off for the whole guard.
        mov.l   p_mmucr,  r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   p_ttb,    r0
        mov.l   s_ttb,    r1
        mov.l   r1, @r0
        mov.l   p_tsbbr,  r0
        mov.l   s_tsbbr,  r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg, r0
        mov.l   s_tsbcfg, r1
        mov.l   r1, @r0
        mov.l   p_tra,    r0
        mov.l   s_tra,    r1
        mov.l   r1, @r0
        mov.l   p_tsbslot, r0
        mov.l   s_tsbslot, r1
        mov.l   r1, @r0
        ! PTEL and ASIDR have no P4 WRITE case (LDC is their only write path),
        ! but they do have P4 READ cases, so seed them via LDC and check them in
        ! check 6 anyway: a gate that leaked would expose them to a user read,
        ! and a decode that mis-routed a user write could still land on them.
        ! PTEH is deliberately NOT checked -- the fault capture rewrites it from
        ! the faulting VA by design, so it is expected to move.
        mov.l   s_ptel, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov.l   s_asidr, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

        ! ---- snapshot TSBSLOT for check 17 ----
        ! TSBSLOT reads back tsb_ptr(tsbslot_va, TSBCFG, TSBBR, ASIDR), not the
        ! raw VA, so it cannot be compared against its seed directly. Compare it
        ! against ITSELF across the sweeps instead: every input it depends on is
        ! separately asserted unchanged, so any movement is the write leaking.
        mov.l   p_tsbslot, r0
        mov.l   @r0, r1
        mov.l   p_scratch, r0
        mov.l   r1, @r0

        ! ---- snapshot the TSBVICT nomination sequence for check 18 ----
        ! TSBVICT's read ADVANCES the victim LFSR -- it is the one P4 register
        ! whose READ has a state side effect, so "the refusal runs no read side
        ! effect" is only an assertion until this measures it. Seed the LFSR,
        ! take four nominations, re-seed identically, and take four more after
        ! the sweeps: the sweeps include a refused user READ of TSBVICT (and a
        ! refused user WRITE of TSBVSEED), so if either got through, the second
        ! four cannot match the first.
        bsr     _vict_seed
        nop
        bsr     _vict4
        nop
        mov.l   p_scratch, r1
        mov.l   r0, @(4,r1)
        bsr     _vict_seed
        nop

        ! ================= PASS 1: every user READ is denied ==============
        mov.l   p_fsr_rd, r12           ! 0x1818
        mov.l   p_p4tab, r8
_rd_loop:
        mov.l   @r8, r4
        tst     r4, r4
        bt      _rd_done
        add     #4, r8

        mov     r14, r6                 ! poison the load destination
        mov     #0, r0
        mov     r0, r10                 ! fault count := 0
        mov     r0, r11                 ! MMUFSR   := 0
        mov     r0, r13                 ! EXPEVT   := 0

        ! ---- descend to user mode ----
        ENTER_USER
        ! ---- USER MODE: exactly one access ----
        mov.l   @r4, r6                 ! MUST FAULT (handler skips it)
        ! ---- SUPERVISOR again, courtesy of _v_gen ----

        mov     #1, r0
        cmp/eq  r0, r10
        FAIL_BF 1                       ! no exception, or more than one
        cmp/eq  r12, r11
        FAIL_BF 2                       ! wrong fault kind / USER / direction
        bsr     _chk_expevt
        nop
        cmp/eq  r14, r6
        FAIL_BF 3                       ! destination register was written
        bra     _rd_loop
        nop
_rd_done:

        ! ================= PASS 2: every user WRITE is denied =============
        mov.l   p_fsr_wr, r12           ! 0x1919
        mov.l   p_p4tab, r8
_wr_loop:
        mov.l   @r8, r4
        tst     r4, r4
        bt      _wr_done
        add     #4, r8

        mov.l   p_attack, r5
        mov     #0, r0
        mov     r0, r10
        mov     r0, r11
        mov     r0, r13

        ENTER_USER
        ! ---- USER MODE: exactly one access ----
        mov.l   r5, @r4                 ! MUST FAULT (handler skips it)
        ! ---- SUPERVISOR again ----

        mov     #1, r0
        cmp/eq  r0, r10
        FAIL_BF 4
        cmp/eq  r12, r11
        FAIL_BF 5
        bsr     _chk_expevt
        nop
        bra     _wr_loop
        nop
_wr_done:

        ! ================= 6: no CSR moved =================================
        ! Read back from SUPERVISOR mode. Every one of these must still be the
        ! seed, not p_attack. MMUCR and TSBBR are the escalation primitives;
        ! the rest are here so a gate that leaks on some other offset is caught
        ! too.
        mov.l   p_mmucr,  r0
        mov.l   @r0, r1
        tst     r1, r1
        FAIL_BF 6                       ! MMUCR must still be 0 (AT off!)
        mov.l   p_ttb,    r0
        mov.l   @r0, r1
        mov.l   s_ttb,    r2
        cmp/eq  r2, r1
        FAIL_BF 6
        mov.l   p_tsbbr,  r0
        mov.l   @r0, r1
        mov.l   s_tsbbr,  r2
        cmp/eq  r2, r1
        FAIL_BF 6
        mov.l   p_tsbcfg, r0
        mov.l   @r0, r1
        mov.l   s_tsbcfg, r2
        cmp/eq  r2, r1
        FAIL_BF 6
        mov.l   p_tra,    r0
        mov.l   @r0, r1
        mov.l   s_tra,    r2
        cmp/eq  r2, r1
        FAIL_BF 6
        mov.l   p_ptel,   r0
        mov.l   @r0, r1
        mov.l   s_ptel,   r2
        cmp/eq  r2, r1
        FAIL_BF 6
        mov.l   p_asidr,  r0
        mov.l   @r0, r1
        mov.l   s_asidr,  r2
        cmp/eq  r2, r1
        FAIL_BF 6

        ! ================= 7: TEA holds the refused address ===============
        ! The last probe of pass 2 is the last table entry, so TEA must be it.
        mov.l   p_tea,    r0
        mov.l   @r0, r1
        mov.l   p_p4last, r2
        cmp/eq  r2, r1
        FAIL_BF 7

        ! ================= 17: TSBSLOT unchanged ==========================
        mov.l   p_tsbslot, r0
        mov.l   @r0, r1
        mov.l   p_scratch, r0
        mov.l   @r0, r2
        cmp/eq  r2, r1
        FAIL_BF 17

        ! ================= 18: the victim LFSR did not advance ============
        ! See the snapshot site above. This is the ONLY assertion that the
        ! refusal suppresses a READ SIDE EFFECT rather than merely a value.
        bsr     _vict4
        nop
        mov.l   p_scratch, r1
        mov.l   @(4,r1), r2
        cmp/eq  r2, r0
        FAIL_BF 18

        ! ================= 8: supervisor access still works ===============
        ! The gate must deny USER mode and nothing else. Without this the guard
        ! would pass just as happily against RTL that broke P4 outright.
        !
        ! ORDERING: this MUST stay after check 17. It rewrites TSBBR, and
        ! TSBSLOT reads back tsb_ptr(VA, TSBCFG, TSBBR, ASIDR) -- so running it
        ! first moves TSBSLOT legitimately and check 17 reports a leak that did
        ! not happen. (Measured: it did exactly that, Result=17.)
        mov.l   p_tsbbr,  r0
        mov.l   s_tsbbr2, r1
        mov.l   r1, @r0
        mov.l   @r0, r2
        cmp/eq  r1, r2
        FAIL_BF 8

        ! ============ 11/12: @Rn+ refused, base register restored =========
        ! THE POINT OF THESE TWO PROBES. The refusal captures its own ma_*
        ! restart shadow (ma_dslot / ma_numz / ma_autoupd / ma_predec /
        ! ma_base). A plain @Rn probe cannot tell whether it did: ma_autoupd
        ! and ma_predec are both '0' for a plain access, so a stale shadow and
        ! a correct one look identical. Only the auto-update forms separate
        ! them -- with a stale shadow the fault restores the wrong register, or
        ! the wrong value, or does not restore at all.
        !
        ! @Rn+ : the faulting VA IS the pre-increment base, so r4 must come back
        !        holding the P4 address, NOT the address + 4.
        mov.l   p_mmucr, r4             ! r4 = 0xFF000010
        mov     r4, r12                 ! witness: the value r4 must come back as
        mov     r14, r6                 ! poison the load destination
        mov     #0, r0
        mov     r0, r10
        mov     r0, r11
        ENTER_USER
        mov.l   @r4+, r6                ! USER post-increment load -> MUST FAULT
        ! back in supervisor
        mov     #1, r0
        cmp/eq  r0, r10
        FAIL_BF 11
        cmp/eq  r12, r4
        FAIL_BF 12                      ! post-increment leaked past the fault
        cmp/eq  r14, r6
        FAIL_BF 3                       ! destination register was written

        ! ============ 13/14: @-Rn refused, base register restored =========
        ! @-Rn : the faulting VA is the ALREADY-decremented address, so the
        !        restore must use the shadowed PRE-decrement base instead. Set
        !        r4 one long ABOVE the target so the decremented VA lands on
        !        MMUCR, and require r4 to come back as the pre-decrement value.
        mov.l   p_mmucr, r4
        add     #4, r4                  ! VA = r4 - 4 = 0xFF000010
        mov     r4, r12                 ! witness
        mov.l   p_attack, r5
        mov     #0, r0
        mov     r0, r10
        mov     r0, r11
        ENTER_USER
        mov.l   r5, @-r4                ! USER pre-decrement store -> MUST FAULT
        ! back in supervisor
        mov     #1, r0
        cmp/eq  r0, r10
        FAIL_BF 13
        cmp/eq  r12, r4
        FAIL_BF 14                      ! pre-decrement leaked past the fault
        mov.l   p_mmucr, r0
        mov.l   @r0, r1
        tst     r1, r1
        FAIL_BF 6                       ! and the store itself must not have landed

        ! ============ 15/16: the gate is size-independent =================
        ! Pre-fix, the P4 write case did `this.mmu.mmucr := ma_dw` with no
        ! reference to mem.size, so a user MOV.B or MOV.W to 0xFF000010 wrote
        ! the FULL 32-bit word exactly as MOV.L did -- the escape was never
        ! long-only. The refusal sits ahead of the offset decode and is equally
        ! size-blind; these prove it rather than assuming it.
        mov.l   p_mmucr, r4
        mov.l   p_attack, r5
        mov     #0, r0
        mov     r0, r10
        mov     r0, r11
        ENTER_USER
        mov.b   r5, @r4                 ! USER byte store -> MUST FAULT
        ! back in supervisor
        mov     #1, r0
        cmp/eq  r0, r10
        FAIL_BF 15                      ! MOV.B raised no exception
        mov.l   p_mmucr, r0
        mov.l   @r0, r1
        tst     r1, r1
        FAIL_BF 6                       ! ... or it raised one and still landed

        mov.l   p_mmucr, r4
        mov.l   p_attack, r5
        mov     #0, r0
        mov     r0, r10
        mov     r0, r11
        ENTER_USER
        mov.w   r5, @r4                 ! USER word store -> MUST FAULT
        ! back in supervisor
        mov     #1, r0
        cmp/eq  r0, r10
        FAIL_BF 16                      ! MOV.W raised no exception
        mov.l   p_mmucr, r0
        mov.l   @r0, r1
        tst     r1, r1
        FAIL_BF 6                       ! ... or it raised one and still landed

        bra     _done
        nop

        ! ---- TSBVICT helpers (supervisor only; r0-r2 scratch) ----
_vict_seed:                             ! TSBVSEED <- a fixed, known seed
        mov.l   p_tsbvseed, r0
        mov.l   s_vseed, r1
        mov.l   r1, @r0
        rts
        nop

_vict4:                                 ! r0 = four consecutive nominations
        mov.l   p_tsbvict, r2
        mov     #0, r0
        mov.l   @r2, r1
        shll    r0
        or      r1, r0
        mov.l   @r2, r1
        shll    r0
        or      r1, r0
        mov.l   @r2, r1
        shll    r0
        or      r1, r0
        mov.l   @r2, r1
        shll    r0
        or      r1, r0
        rts
        nop

        ! Shared EXPEVT assertion. Both directions currently report the DPROT
        ! code; this is the one place to change if the decoder ROM ever gains
        ! SH-4's real 0x0E0/0x100 address-error codes.
_chk_expevt:
        mov.l   p_expevt_val, r0        ! 0x0C0
        cmp/eq  r0, r13
        FAIL_BF 10
        rts
        nop

_fail_at:
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off (harmless if already off)
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_mdmask:       .long 0xBFFFFFFF        ! clear SR.MD (bit 30)
p_vbr_val:      .long _v_base
p_poison:       .long 0x5EEDFACE
p_attack:       .long 0x5A5A5A5A        ! bit0 = 0, so even a leak leaves AT off
p_expevt_val:   .long 0x000000C0        ! shared with DPROT_R/W -- see the header
p_fsr_rd:       .long 0x00001818        ! VALID|KIND 8|USER|PROT
p_fsr_wr:       .long 0x00001919        ! VALID|KIND 9|USER|PROT|WRITE
p_ptel:         .long 0xFF000004
p_asidr:        .long 0xFF000038
p_tsbvseed:     .long 0xFF00004C
p_tsbvict:      .long 0xFF000050
s_ptel:         .long 0x000067E9
s_asidr:        .long 0x000000AB
s_vseed:        .long 0x0000BEEF
p_scratch:      .long _scratch          ! 2 longs; linker-placed, not a guessed address
p_mmucr:        .long 0xFF000010
p_ttb:          .long 0xFF000008
p_tea:          .long 0xFF00000C
p_tsbbr:        .long 0xFF000014
p_tsbcfg:       .long 0xFF000018
p_tra:          .long 0xFF000020
p_tsbslot:      .long 0xFF000048
s_ttb:          .long 0x11110000
s_tsbbr:        .long 0x00010006
s_tsbcfg:       .long 0x00000061
s_tra:          .long 0x00000144
s_tsbslot:      .long 0x22220000
s_tsbbr2:       .long 0x00020006
p_p4last:       .long 0xFF000054
p_p4tab:        .long _p4tab

        .align 2
        ! Every P4 offset core/datapath.vhm decodes, in decode order. Reads and
        ! writes are both swept over the whole list: a register that is
        ! read-only or write-only to SUPERVISOR code is still not a user's to
        ! touch, and the refusal happens ahead of the offset decode, so there is
        ! no reason for any of them to behave differently. 0 terminates.
_p4tab:
        .long 0xFF000000                ! PTEH
        .long 0xFF000004                ! PTEL
        .long 0xFF000008                ! TTB
        .long 0xFF00000C                ! TEA
        .long 0xFF000010                ! MMUCR   <-- AT off => escape
        .long 0xFF000014                ! TSBBR   <-- walker base => escape
        .long 0xFF000018                ! TSBCFG
        .long 0xFF00001C                ! TSBPTR
        .long 0xFF000020                ! TRA
        .long 0xFF000024                ! EXPEVT
        .long 0xFF000028                ! INTEVT
        .long 0xFF00002C                ! MMUFSR
        .long 0xFF000038                ! ASIDR
        .long 0xFF000048                ! TSBSLOT
        .long 0xFF00004C                ! TSBVSEED
        .long 0xFF000050                ! TSBVICT
        ! TLBINST: non-architectural read-only instrumentation (the I->D shadow
        ! fill's install counters). Still privileged -- it is a P4 CSR, and
        ! leaking the TLB install rate to user code is a side channel even
        ! though nothing here is writable.
        .long 0xFF000058                ! TLBINST (read-only)
        ! UNDECODED P4, deliberately. The gate is address-independent
        ! (seg_v = SEG_P4), so these must be refused exactly like a decoded CSR
        ! -- and nothing else in this guard would notice if they were not.
        ! Narrowing the gate to `p4_sel_v /= P4_NONE` keeps every other check
        ! green while user access to 0xFF000030/0x34 quietly succeeds: a live
        ! bug the day a register lands at 0x34, which datapath.vhm already
        ! reserves for a proposed PTEU.
        .long 0xFF000034                ! undecoded (reserved PTEU) -- P4 all the same
        ! And P4 is the whole 0xFF------ (datapath_pkg.vhd seg_decode: VA[31:24]
        ! = 0xFF), not just the 0xFF0000-- CSR window. Pin that too.
        .long 0xFFFFFFF0                ! top of P4, nowhere near the decode
        ! KEEP TSBCNT LAST: check 7 asserts TEA holds p_p4last after the final
        ! probe of pass 2, so appending past this line breaks it.
        .long 0xFF000054                ! TSBCNT  (= p_p4last, for check 7)
        .long 0

#else
        bra     _done
        nop
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
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        .balign 4
_v_base:                                ! VBR
        .space 0x100, 0

_v_gen:                                 ! VBR + 0x100 -- general exception
        ! Entered MD=RB=BL=1, so r0-r3 below are bank 1 and cannot disturb the
        ! probe's bank-0 registers. r10/r11 are unbanked and are the only state
        ! carried back to the sweep.
        .word   0x0042                  ! STC SPC, r0
        add     #2, r0                  ! skip the refused 2-byte access
        .word   0x404E                  ! LDC r0, SPC
        stc     sr, r1                  ! MD=RB=BL=1 here
        mov.l   H_rbclear, r2
        and     r2, r1                  ! return with RB=0 (bank 0), MD still 1
        .word   0x413E                  ! LDC r1, SSR
        mov.l   H_expevt, r3
        mov.l   @r3, r13                ! r13 = EXPEVT of this fault
        mov.l   H_mmufsr, r3
        mov.l   @r3, r11                ! r11 = MMUFSR of this fault
        add     #1, r10                 ! r10 = fault count
        rte
        nop

        .align 2
H_rbclear:      .long 0xDFFFFFFF
H_expevt:       .long 0xFF000024
H_mmufsr:       .long 0xFF00002C

        ! Pad to exactly VBR+0x400, computed rather than hand-counted so that
        ! editing the handler above cannot silently move the TLB vector.
        .space _v_base + 0x400 - ., 0
_v_tlb:                                 ! VBR + 0x400 -- must never be reached
        ! A P4 privilege violation is an ADDRESS ERROR, not a TLB fault. If the
        ! implementation routes it to the TLB vector instead, land here and say
        ! so rather than looping in a handler that has nothing to do.
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #9, r9
        ! Indirect, not BRA: _fail is a full vector page behind us and the
        ! 12-bit displacement does not reach it.
        mov.l   H_fail, r0
        jmp     @r0
        nop

        .align 2
H_mmucr:        .long 0xFF000010
H_fail:         .long _fail

        ! Scratch for the check-17/18 snapshots. A linker-placed object rather
        ! than a hand-picked RAM address: 0x00006000 happened to be free below
        ! the stack, but nothing enforced that and nothing would have caught it
        ! moving.
        .balign 4
_scratch:
        .space 8, 0

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

! CONFIG_PRIV_ARCH
#endif
