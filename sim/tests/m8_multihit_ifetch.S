! m8_multihit_ifetch.S -- genuine TLB MULTI_HIT (I-side and D-side), and the
! I-side restart-shadow clobber commit 30af728 fixed.
!
! sim/tests/mmumultihit.S documents that a normal LDTLB install sequence can
! no longer reach S-I5 MULTI_HIT: install-time overlap eviction (task 3)
! collapses any two entries whose ranges overlap under the SAME asid-or-
! global gate -- EXCEPT when more than one pre-existing entry independently
! overlaps a single new install, since LDTLB only evicts the FIRST match it
! finds in slot order (core/tlb.vhd's install loop latches `dedup` on the
! first hit and never re-fires). This guard builds exactly that case:
!
!   1. Install A: ASID=ASID_A, non-global, VPN=V.
!   2. Install B: ASID=ASID_B (B!=A), non-global, SAME VPN=V. A and B coexist:
!      the dedup/eviction predicate is
!        (entry.global='1' or new.global='1' or entry.asid_tag=asidr)
!      an OR-gate -- between two differently-ASID'd non-global entries every
!      term is FALSE, so installing B does not touch A's slot. B lands in a
!      strictly LATER slot (NRU is install-order only; core/tlb.vhd never
!      sets `used` on a lookup hit, only at install/flush, so slot order is
!      deterministic from the LDTLB sequence alone).
!   3. Install C: global, SAME VPN=V. C's global bit makes the OR-gate TRUE
!      against ANY resident overlapping entry, so the install-time dedup scan
!      fires -- but the scan latches `dedup` on the FIRST match (A, the lower
!      slot) and never reconsiders B. A is evicted; B survives untouched.
!   4. ASIDR := ASID_B, access VA in V. Two usable matches, one lookup:
!      B (asid match) and C (global) -- a genuine S-I5 MULTI_HIT.
!
! Verified against core/tlb.vhd before writing this file (all three hold,
! no surprises):
!   (a) the install-time dedup/eviction predicate is exactly that OR-gate
!       (core/tlb.vhd, `elsif (tlb_wr = '1') then` block).
!   (b) `if (not dedup and ...) then idx := k; dedup := true; end if;` inside
!       the `for k in 0 to 31 loop` -- only the first match sets idx; later
!       matches are ignored once dedup='1'.
!   (c) i_multihit / d_multihit assert combinationally on a 2nd+ usable match
!       in the lookup scan (`if (hit_found='1') then multihit := '1'`), and
!       core/cpu.vhd dispatches MULTI_HIT through the General Illegal vector
!       (VBR+0x100), EXPEVT=0x180, MMUFSR=0x1700 (KIND=7) -- confirmed
!       against sim/tests/mmufsr.S sub-test G, which reaches a (D-side)
!       MULTI_HIT via an unrelated construction (superpage-evicts-only-one-
!       of-two-disjoint-pages) and reads exactly those two values.
!
! ---- Sub-tests ----
!
! 1 (Milestone 1): the ASID+global construction above, driving an
!    INSTRUCTION FETCH (jmp to VA in V) into the multi-hit. Proves the
!    construction reaches i_multihit; corroborated by EXPEVT=0x180 and
!    MMUFSR=0x1700 read in the VBR+0x100 handler. If the construction fails
!    to multi-hit, control lands cleanly on B's or C's page instead -- both
!    are left unseeded (zero-filled RAM), which SH-2 decodes as an illegal
!    instruction and (coincidentally) also traps through VBR+0x100, but
!    with a stale/zero MMUFSR -- caught by the MMUFSR check (result 3), not
!    silently mistaken for MULTI_HIT.
!
! 2 (Milestone 2): same I-side construction, but a `mov.l @Rn+, Rm` against
!    an ordinary mapped scratch word runs immediately before the faulting
!    jmp (no intervening memory access -- ma_base/ma_numz/ma_autoupd are
!    written only at the memory-access pipeline point and would otherwise
!    be scrubbed by any load in between, see sim/tests/mmushadowld.S's
!    construction hazard note). Before commit 30af728, an I-side MULTI_HIT
!    had tlb_exc_is_i='0' (that signal is deliberately narrowed to
!    IMISS/IPROT for restart-PC selection) and fell into the D-side restore
!    arm, which trusted the STALE shadow and wrote the I-fetch's faulting
!    VA into Rn. This sub-test asserts Rn holds EXACTLY its own post-
!    increment value (scratch_addr + 4) after the fault -- not "not the
!    fault VA", the precise expected value, so a partially-wrong restore
!    fails too.
!
! 3 (Milestone 3, the control): a D-side MULTI_HIT, reached the same way but
!    as the faulting access of a `mov.l @Rn+, Rm` itself (Rn points into V).
!    A genuine D-side MULTI_HIT is fundamentally a D-side fault
!    (tlb_exc_ifetch='0') and MUST still arm the restore normally: Rn must
!    land back at exactly its PRE-increment value (the fault VA), undoing
!    the speculative slot-0 bump. This guards the most likely wrong fix for
!    Milestone 2 -- gating the restore off for MULTI_HIT unconditionally
!    (instead of specifically for the I-side case) would pass sub-test 2
!    while silently breaking this one.
!
!    NON-VACUITY. Proven directly (2026-08-05), at the RTL interception
!    point core/datapath.vhm's restore_fire (the base-restore arm shared by
!    I-side and D-side): forcing `restore_fire <= '0'` unconditionally (the
!    base restore never fires, for ANY kind/side) turns this sub-test RED
!    with Result=17 ("D-side restore did NOT fire"), while all other
!    sub-tests still see their expected exception path. This is a lower,
!    more direct mutation than either of the two that were tried first and
!    did NOT turn it red: reverting commit 30af728 (which mutates the
!    tlb_restore_pend ARMING predicate, not restore_fire itself, and left
!    this control green because 30af728's revert only reintroduced the
!    tlb_exc_is_i mix-up on the I-side, leaving the D-side arm untouched),
!    and a hand-added "disable restore for all MULTI_HITs" clause (which is
!    reachable only through the same arming predicate and is apparently
!    short-circuited before reaching this sub-test's D-side path). The
!    restore_fire mutation is not side-selective, so it does not by itself
!    prove the I-side/D-side DISCRIMINATOR is exercised here -- that half
!    is already covered by sub-test 2 -- but it does prove sub-test 3
!    genuinely observes whether the D-side restore fires at all, which is
!    what it was written to check.
!
! Result codes:
!   0   pass
!   1   sub-test 1: no exception (multi-hit not reached)
!   2   sub-test 1: EXPEVT != 0x180
!   3   sub-test 1: MMUFSR != 0x1700
!   6   sub-test 2: no exception
!   7   sub-test 2: EXPEVT != 0x180
!   8   sub-test 2: MMUFSR != 0x1700
!   11  sub-test 2: Rn (shadow base) != scratch_addr + 4 (Defect: I-side
!       MULTI_HIT clobbered the shadow register from the stale D-side path)
!   12  sub-test 3: no exception
!   13  sub-test 3: EXPEVT != 0x180
!   14  sub-test 3: MMUFSR != 0x1700
!   17  sub-test 3: Rn (shadow base) != VA (the D-side restore did NOT fire /
!       fired wrong -- the "grace" regression this sub-test guards against)
!
! PTEL flag bit layout (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C
! bit2=G bit1=STALE bit0=V. Kernel non-global code: W|X|C = 0xC8. Kernel
! non-global data (read/write, no exec needed): W|C = 0x88. Global variant
! ORs in bit2 (0x04).
!
! VPNs (0x20/0x21/0x22, VA 0x20000/0x21000/0x22000) and their backing PAs
! (0x40000+) are chosen far above this file's own code footprint so the
! code-identity-mapping loop below can never collide with them.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   LDC r0,VBR = 0x402E   LDC r0,PTEH = 0x405E   LDC r0,PTEL = 0x406E
!   LDC r0,ASIDR = 0x407E   LDTLB = 0x0038   LDC r0,SPC = 0x404E
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; a bare 4-byte write of 0
! reports as Result=0 (FAIL), and _fail clamps r9==0 to 0x7F so an early,
! un-set fail code is never mistaken for PASS.
#include "sim_instr.h"
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
        ! start must be page-aligned: the code-mapping loop below walks it
        ! in PAGE_SZ steps.
        .balign 0x1000
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_gi - 0x100 (so VBR+0x100 = _v_gi, the single General
        ! Illegal handler MULTI_HIT dispatches through). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Clean-slate TLB: drop AT (already 0), TI-flush, then map the
        ! code region (start.._code_end) identity, kernel, non-global. ----
        mov.l   p_mmucr, r0
        mov     #4, r1
        mov.l   r1, @r0                 ! TI: invalidate all 32 entries
        mov     #0, r1
        mov.l   r1, @r0                 ! TI released

        mov.l   p_code_start, r2
        mov.l   p_code_end, r3
1:      mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov     r2, r0
        mov.l   p_code_flags, r1
        or      r1, r0                  ! PTEL = page | 0xC8
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        mov.l   p_page_sz, r0
        add     r0, r2
        cmp/hs  r3, r2
        bf      1b

        ! ---- Seed every candidate backing page (A/B/C x 3 sub-tests) via
        ! P1 (untranslated, AT-independent) before AT goes on. The sim's bus
        ! memory model reports an "invalid read addr" bus error on a truly
        ! never-written location -- multi-hit still causes a real (squashed)
        ! bus fetch of at least one candidate PA before the fault preempts
        ! it, so every candidate page needs real backing content, not just
        ! the ones expected to actually be used. I-side pages get a tight
        ! self-branch (`bra $`, opcode 0xAFFE 0x0009) so a stray successful
        ! fetch spins harmlessly (timing out, reported FAIL by the harness)
        ! instead of running off into further uninitialized memory; D-side
        ! pages get a plain sentinel word (content is never asserted on).
        mov.l   p_poison_instr, r3      ! 0xAFFE0009 = "bra $ / nop"
        mov.l   p_poison_data, r4       ! 0xDEADBEEF
        mov.l   p1_p1_a, r2 ; mov.l r3, @r2
        mov.l   p1_p1_b, r2 ; mov.l r3, @r2
        mov.l   p1_p1_c, r2 ; mov.l r3, @r2
        mov.l   p2_p1_a, r2 ; mov.l r3, @r2
        mov.l   p2_p1_b, r2 ; mov.l r3, @r2
        mov.l   p2_p1_c, r2 ; mov.l r3, @r2
        mov.l   p3_p1_a, r2 ; mov.l r4, @r2
        mov.l   p3_p1_b, r2 ; mov.l r4, @r2
        mov.l   p3_p1_c, r2 ; mov.l r4, @r2

        ! ---- Enable AT once; stays on for the whole guard body (the
        ! VBR+0x100 handler disables it before each resume, sub-tests
        ! re-enable it before their own multi-hit access). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================================================================
        ! Sub-test 1 (Milestone 1): I-side MULTI_HIT, no shadow arming.
        ! ================================================================
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR (install A under ASID_A)
        mov.l   p1_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN V1)
        mov.l   p1_ptel_a, r0           ! PA_A | W|X|C, non-global
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR (install B under ASID_B)
        mov.l   p1_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH  (same VPN V1)
        mov.l   p1_ptel_b, r0           ! PA_B | W|X|C, non-global
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR (install C: ASID irrelevant, global)
        mov.l   p1_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH  (same VPN V1)
        mov.l   p1_ptel_c, r0           ! PA_C | W|X|C|GLOBAL
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB
        ! -> A evicted (first match found), B survives, C occupies A's slot.

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR := ASID_B (matches B)

        mov.l   p_g_exp_expevt, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! result-1 sentinel: no exception
        mov.l   p_g_bad_expevt, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! EXPEVT mismatch -> result 2
        mov.l   p_g_bad_fsr, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! MMUFSR mismatch -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_after_1, r1
        mov.l   r1, @r0                 ! resume label on success

        mov.l   p1_va, r0
        jmp     @r0                     ! MUST fault -> _v_gi, MULTI_HIT
        nop
ENTRY(after_1)
        ! The VBR+0x100 handler disables AT before rte (mirrors mmufsr.S);
        ! each sub-test must re-enable it before its own multi-hit access.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================================================================
        ! Sub-test 2 (Milestone 2): same shape, distinct VPN V2, with the
        ! shadow armed by an ordinary post-increment load IMMEDIATELY
        ! before the faulting jmp -- nothing else may touch memory in
        ! between (mmushadowld.S's construction hazard).
        ! ================================================================
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p2_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN V2)
        mov.l   p2_ptel_a, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p2_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p2_ptel_b, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p2_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p2_ptel_c, r0           ! global
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR := ASID_B

        mov.l   p_g_exp_expevt, r0
        mov     #6, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_expevt, r0
        mov     #7, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_fsr, r0
        mov     #8, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_2, r1
        mov.l   r1, @r0

        ! Preload everything the window needs BEFORE arming the shadow: the
        ! jmp target and the scratch base. No memory access may occur
        ! between the arming load and the faulting jmp.
        mov.l   p2_va, r1               ! r1 = fault target (I-fetch VA)
        mov.l   p_scratch_addr, r2      ! r2 = scratch word address
        ! ==================== THE WINDOW: nothing between ================
        mov.l   @r2+, r12               ! arms ma_base/ma_numz/ma_autoupd
        jmp     @r1                     ! MUST fault -> _v_gi, MULTI_HIT
        nop
        ! ====================================================================
ENTRY(after_2)
        ! Re-enable AT again -- the handler always leaves it disabled.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! r2 must hold EXACTLY scratch_addr + 4 -- the load's OWN
        ! post-increment, untouched by any bogus MULTI_HIT restore.
        mov.l   p_scratch_addr, r0
        add     #4, r0
        cmp/eq  r0, r2
        mov     #11, r9
        bf      _fail

        ! ================================================================
        ! Sub-test 3 (Milestone 3, control): D-side MULTI_HIT as the fault
        ! of the post-increment load itself. The restore MUST still fire:
        ! Rn lands back at exactly the pre-increment VA.
        ! ================================================================
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p3_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN V3)
        mov.l   p3_ptel_a, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p3_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p3_ptel_b, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   p3_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p3_ptel_c, r0           ! global
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        mov.l   p_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR := ASID_B

        mov.l   p_g_exp_expevt, r0
        mov     #12, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_expevt, r0
        mov     #13, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_fsr, r0
        mov     #14, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_3, r1
        mov.l   r1, @r0

        mov.l   p3_va, r3               ! r3 = the multi-hit VA (D-side target)
        mov.l   @r3+, r13               ! MUST fault -> _v_gi, MULTI_HIT (D-side)
ENTRY(after_3)
        ! r3 must hold EXACTLY the pre-increment VA (the fault VA) -- the
        ! restore undid the speculative slot-0 bump, exactly as it does for
        ! any other faulting @Rn+ load.
        mov.l   p3_va, r0
        cmp/eq  r0, r3
        mov     #17, r9
        bf      _fail

        ! ---- Disable AT before handing back to the result harness. ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov     #0, r9
        bra     _done
        nop

        .align  2
p_rbclear:      .long   0xDFFFFFFF
p_vbr_val:      .long   _v_gi - 0x100
p_mmucr:        .long   0xFF000010
p_code_start:   .long   start
p_code_end:     .long   _code_end
p_code_flags:   .long   0x000000CC      ! kernel W|X|C|GLOBAL: the code's own
                                        ! identity map must survive ASIDR
                                        ! churn from the A/B/C installs below,
                                        ! or the very next code fetch after
                                        ! an ASIDR-poisoning LDTLB IMISSes
                                        ! with no handler installed.
p_page_sz:      .long   0x1000
p_asid_a:       .long   0x00000011      ! ASID_A
p_asid_b:       .long   0x00000022      ! ASID_B != ASID_A
p_scratch_addr: .long   _scratch_word
p_poison_instr: .long   0xAFFE0009      ! "bra $" / nop delay slot
p_poison_data:  .long   0xDEADBEEF
p1_p1_a:        .long   0x80040000      ! P1(0x40000)
p1_p1_b:        .long   0x80041000      ! P1(0x41000)
p1_p1_c:        .long   0x80042000      ! P1(0x42000)
p2_p1_a:        .long   0x80043000      ! P1(0x43000)
p2_p1_b:        .long   0x80044000      ! P1(0x44000)
p2_p1_c:        .long   0x80045000      ! P1(0x45000)
p3_p1_a:        .long   0x80046000      ! P1(0x46000)
p3_p1_b:        .long   0x80047000      ! P1(0x47000)
p3_p1_c:        .long   0x80048000      ! P1(0x48000)

        ! Sub-test 1 (VPN V1 = 0x20, VA 0x20000).
p1_pteh:        .long   0x00020000
p1_ptel_a:      .long   0x000400C8      ! PA 0x40000 | W|X|C, non-global
p1_ptel_b:      .long   0x000410C8      ! PA 0x41000 | W|X|C, non-global
p1_ptel_c:      .long   0x000420CC      ! PA 0x42000 | W|X|C|GLOBAL
p1_va:          .long   0x00020000

        ! Sub-test 2 (VPN V2 = 0x21, VA 0x21000).
p2_pteh:        .long   0x00021000
p2_ptel_a:      .long   0x000430C8      ! PA 0x43000 | W|X|C, non-global
p2_ptel_b:      .long   0x000440C8      ! PA 0x44000 | W|X|C, non-global
p2_ptel_c:      .long   0x000450CC      ! PA 0x45000 | W|X|C|GLOBAL
p2_va:          .long   0x00021000

        ! Sub-test 3 (VPN V3 = 0x22, VA 0x22000).
p3_pteh:        .long   0x00022000
p3_ptel_a:      .long   0x000460C8      ! PA 0x46000 | W|X|C, non-global
p3_ptel_b:      .long   0x000470C8      ! PA 0x47000 | W|X|C, non-global
p3_ptel_c:      .long   0x000480CC      ! PA 0x48000 | W|X|C|GLOBAL
p3_va:          .long   0x00022000

        ! ---- Handler globals (shared VBR+0x100 handler; each sub-test
        ! overwrites these before its own multi-hit access). ----
p_g_exp_expevt: .long   _g_exp_expevt
p_g_bad_expevt: .long   _g_bad_expevt
p_g_bad_fsr:    .long   _g_bad_fsr
p_g_resume:     .long   _g_resume
p_after_1:      .long   after_1
p_after_2:      .long   after_2
p_after_3:      .long   after_3

        .align  2
_scratch_word:  .long   0xCAFEF00D
                .long   0               ! post-increment landing pad, never read

! _done/_fail and their literal pool sit OUTSIDE the CONFIG_PRIV_ARCH guard,
! matching m8_runtime.inc. The .vect table above references both symbols
! unconditionally, so guarding them breaks the base-J2 link with
! "undefined reference to _done/_fail" -- which fails `make all` and takes
! regression.sh Step 6 down with it before a single test runs.
! With them out here, a base build falls through from `start` straight into
! _done and the image reports PASS trivially; the real MULTI_HIT work only
! exists on the J4/PRIV overlay, where sim/mmu_sim.sh runs it as a guard.
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
        bf      1f                      ! (PASS now requires TEST_PASS_MAGIC,
        mov     #0x7F, r9               ! so a bare 0 reports Result=0, not
1:      mov.l   r9, @r0                 ! PASS)
        bra     _fail
        nop

        .align  2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ================================================================
        ! Single MULTI_HIT handler at VBR+0x100 (General Illegal). MULTI_HIT
        ! writes its own EXPEVT=0x180 via microcode (does not go through the
        ! TLB-fault EXPEVT/VBR+0x400 path -- core/cpu.vhd, sim/tests/
        ! mmufsr.S sub-test G). Disables AT, checks EXPEVT then MMUFSR
        ! (both against the caller-selected globals), then resumes at the
        ! caller-selected label with SPC/rte.
        ! ================================================================
        .balign 4
        .space  0x100, 0
        .balign 4
_v_gi:                                  ! = VBR + 0x100
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1                 ! r1 = 0x180 expected
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Hfsr_addr, r0
        mov.l   @r0, r2                 ! r2 = MMUFSR
        mov.l   Hexp_fsr, r1
        mov.l   @r1, r1                 ! r1 = 0x1700 expected
        cmp/eq  r1, r2
        bf      _h_bad_fsr
        mov.l   Hresume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_expevt:
        mov.l   Hbad_expevt, r0
        mov.l   @r0, r9
        bra     _fail
        nop

_h_bad_fsr:
        mov.l   Hbad_fsr, r0
        mov.l   @r0, r9
        bra     _fail
        nop

        .align  2
Hmmucr:         .long   0xFF000010
Hfsr_addr:      .long   0xFF000028
Hexp_fsr:       .long   c_fsr_multihit
Hexp_expevt:    .long   c_expevt_multihit
Hresume:        .long   _g_resume
Hbad_expevt:    .long   _g_bad_expevt
Hbad_fsr:       .long   _g_bad_fsr

        .align  2
c_fsr_multihit:    .long 0x00001700
c_expevt_multihit: .long 0x00000180

        ! ---- Handler globals. ----
        .balign 4
_g_exp_expevt:  .long   0xFFFFFFFF      ! unset sentinel; a sub-test always overwrites
_g_bad_expevt:  .long   0x5A            ! loud fail-code sentinel: names early fault
_g_bad_fsr:     .long   0x5B
_g_resume:      .long   0

! _code_end marks the end of everything that must be mapped BEFORE AT goes
! on: preamble, all three sub-tests, the VBR+0x100 handler, and every
! literal pool/global touched while AT is still enabled (the handler
! disables AT on entry, but the vector fetch itself and the handler's own
! body run translated).
ENTRY(_code_end)

#endif  ! CONFIG_PRIV_ARCH
