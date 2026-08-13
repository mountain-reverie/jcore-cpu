! m8_multihit_ifetch.S -- genuine TLB MULTI_HIT (I-side and D-side), and the
! I-side restart-shadow clobber commit 30af728 fixed.
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). Every TLB entry in this file
! is installed by the HARDWARE TSB WALKER. The construction, the three
! sub-tests, every result code and every expected constant are unchanged; what
! changed is how the three coexisting entries are provoked, and that is forced
! by two properties of the walker:
!
!   (i)  it installs only on a MISS, so three installs over one VA now need
!        three MISSES -- supplied by ASID switching (see below);
!   (ii) it installs into ONE array, by side: an I-side miss into u_itlb, a
!        D-side miss into u_dtlb. LDTLB wrote BOTH arrays, so the I-side
!        multi-hit of sub-tests 1 and 2 came free from a data-driven install
!        sequence. It no longer does: every install for an I-side multi-hit
!        must be a real INSTRUCTION FETCH. PA_A/PA_B/PA_C for sub-tests 1 and
!        2 therefore now hold real code (`jmp @r14 / nop`) and are branched to
!        and returned from, one per ASID, instead of holding a `bra $` poison
!        word that was never executed.
!
! sim/tests/mmumultihit.S documents that a normal install sequence can no
! longer reach S-I5 MULTI_HIT: install-time overlap eviction (task 3) collapses
! any two entries whose ranges overlap under the SAME asid-or-global gate --
! EXCEPT when more than one pre-existing entry independently overlaps a single
! new install, since the install loop only evicts the FIRST match it finds in
! slot order (core/tlb.vhd's install loop latches `dedup` on the first hit and
! never re-fires). This guard builds exactly that case:
!
!   1. ASIDR := ASID_A, access VA in V. MISS -> walk reads the TSB slot hashed
!      for (V, ASID_A), whose PTEL is non-global -> install A.
!   2. ASIDR := ASID_B (B != A), access VA in V again. A is non-global with
!      asid_tag=ASID_A, so it does NOT match -> MISS -> the walk reads the slot
!      hashed for (V, ASID_B), also non-global -> install B. A and B coexist:
!      the dedup/eviction predicate is
!        (entry.global='1' or new.global='1' or entry.asid_tag=asidr)
!      an OR-gate -- between two differently-ASID'd non-global entries every
!      term is FALSE, so installing B does not touch A's slot. B lands in a
!      strictly LATER slot (NRU is install-order only; core/tlb.vhd never sets
!      `used` on a lookup hit, only at install/flush, so slot order is
!      deterministic from the install sequence alone).
!   3. ASIDR := ASID_Z (0, a THIRD ASID), access VA in V again. Neither A nor B
!      matches and nothing global covers V yet -> MISS -> the walk reads the
!      slot hashed for (V, ASID_Z), whose PTEL IS global -> install C. C's
!      global bit makes the OR-gate TRUE against ANY resident overlapping
!      entry, so the install-time dedup scan fires -- but the scan latches
!      `dedup` on the FIRST match (A, the lower slot) and never reconsiders B.
!      A is evicted; B survives untouched.
!      (Under LDTLB this step was done with ASIDR=0 too -- the value is the
!      same, but there it was arbitrary and here it is load-bearing: it is what
!      makes the third access miss.)
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
!    to multi-hit, the fetch lands cleanly on B's or C's page, which runs
!    `jmp @r14` and returns to a caller-selected label that FAILS with this
!    sub-test's own "no exception" code. That is STRONGER than the LDTLB
!    version, where the candidate pages held a `bra $` poison word and a
!    failure to multi-hit was reported only as a harness TIMEOUT.
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
!    with the three installs driven by ORDINARY LOADS (D-side misses install
!    into u_dtlb) and the faulting access being a `mov.l @Rn+, Rm` itself (Rn
!    points into V). A genuine D-side MULTI_HIT is fundamentally a D-side
!    fault (tlb_exc_ifetch='0') and MUST still arm the restore normally: Rn
!    must land back at exactly its PRE-increment value (the fault VA), undoing
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
!   1   sub-test 1: no exception (multi-hit not reached -- the fetch landed
!       on a candidate page and returned through its `jmp @r14`)
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
! bit2=G bit1=STALE bit0=V. Kernel non-global code: W|X|C|V = 0xC9. The global
! variant ORs in bit2 (0x04) -> 0xCD. Bit0 (V) MUST be set in a TSB entry:
! core/tlb_walk.vhd rejects a data word with V=0 or STALE=1 as "no entry", so
! the LDTLB version's 0xC8/0xCC become 0xC9/0xCD here. U stays 0 throughout:
! every one of these pages is FETCHED, and a kernel fetch of a U=1 page is an
! SMEP protection fault (core/tlb.vhd:247).
!
! The code region is ONE 16 KB GLOBAL identity page (VA 0x0000..0x3FFF,
! page_mask=1). Global for the same reason the LDTLB version's code map was
! global -- it must survive the ASIDR churn the sub-tests do -- and a single
! superpage rather than a per-page loop because the walker's tag compare is
! EXACT on the 4 KB VPN, so each of VPN 0..3 gets its own TSB row installing
! the same 16 KB mapping; whichever is touched first installs it and the rest
! then hit without walking. The first I-fetch and the first literal load after
! AT goes on each take one walk, and nothing re-walks code after that. Both
! ARRAYS get the entry that way (the I-side from the fetch, the D-side from
! the literal load) -- which matters because the VBR+0x100 handler runs with
! RB=1, where core/cpu.vhd's walk_req is NOT armed, so a D-miss inside the
! handler would be an unrecoverable nested fault.
!
! VPNs (0x20/0x21/0x22, VA 0x20000/0x21000/0x22000) and their backing PAs
! (0x40000+) are chosen far above this file's own code footprint so the code
! superpage can never collide with them.
!
! TSB: base 0x00006000, TSB_SIZE_LOG=8 (256 sets x 32 bytes = 8 KB),
! HASH_SHIFT=6, HASH_MODE=1. Slot addresses are NOT hand-computed: the guard
! asks the P4 TSB-slot helper (0xFF000048, the single tsb_ptr()
! implementation the walker and TSBPTR also use) for each (VA, ASID) pair at
! fill time. The image is padded past the END of the TSB, because the walker
! reads it by PHYSICAL address and a physical alias is backed by SRAM only
! within the loaded image extent.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   LDC r0,VBR = 0x402E   LDC r0,ASIDR = 0x407E   LDC r0,SPC = 0x404E
!   STC EXPEVT,r0 = 0x0052
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; a bare 4-byte write of 0
! reports as Result=0 (FAIL), and _fail clamps r9==0 to 0x7F so an early,
! un-set fail code is never mistaken for PASS.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

        ! ASIDR := *\lit, with the two settle slots every other guard uses.
        .macro  SET_ASIDR lit
        mov.l   \lit, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        .endm

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
        ! start must be page-aligned: it is the base of the identity-mapped
        ! code region.
        .balign 0x1000
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). core/cpu.vhd's walk_req is gated on
        ! ---- dp_sr.rb='0' and the cosim starts in bank 1; without this no
        ! ---- walk is ever armed and nothing installs. ----
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

        ! ---- Clean-slate TLB: drop AT (already 0), TI-flush. ----
        mov.l   p_mmucr, r0
        mov     #4, r1
        mov.l   r1, @r0                 ! TI: invalidate all 32 entries
        mov     #0, r1
        mov.l   r1, @r0                 ! TI released

        ! ---- Seed every candidate backing page (A/B/C x 3 sub-tests) via
        ! P1 (untranslated, AT-independent) before AT goes on.
        !
        ! The I-side candidates of sub-tests 1 and 2 are now EXECUTED, not
        ! merely fetched-and-squashed: each of the three installs over a VPN
        ! is an instruction fetch that must come back. Their first word is
        ! `jmp @r14 / nop` (0x4E2B 0x0009) and the caller parks a return
        ! label in r14 before every jump. That doubles as the "no exception"
        ! detector for the final, faulting jump: if the multi-hit is not
        ! reached, the fetch succeeds, the page returns through r14, and the
        ! sub-test fails LOUDLY with its own code instead of timing out.
        !
        ! Each page is filled well past its first cache line: an executed (or
        ! loaded-from) page takes a real line fill, and the sim's bus memory
        ! model reports an "invalid read addr" bus error on a truly
        ! never-written location.
        mov.l   p_iseed_tab, r14
        mov.l   p_iseed_end, r5
        mov.l   p_jmp_r14, r3           ! 0x4E2B0009 = "jmp @r14 / nop"
        mov.l   p_nopnop, r4            ! 0x00090009 = "nop / nop"
        bsr     _seed_pages
        nop

        mov.l   p_dseed_tab, r14
        mov.l   p_dseed_end, r5
        mov.l   p_poison_data, r3       ! 0xDEADBEEF (content never asserted on)
        mov     r3, r4
        bsr     _seed_pages
        nop

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the TSB from the (VA, ASID, PTEL) table. For each row the
        ! ---- set address is asked of the P4 helper UNDER THAT ROW'S ASID, so
        ! ---- no hash is hand-computed here. AT is still off, so these are
        ! ---- plain untranslated P0 stores. The table's last row carries
        ! ---- ASID 0, which is also the ASID in force when AT goes on and the
        ! ---- code superpage is walked in. ----
        mov.l   p_tsbslot, r12          ! r12 = 0xFF000048
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
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

        bra     _run
        nop

! ---- Page seeder: r14 = table of P1 page addresses, r5 = its end, r3 = the
! ---- word to write at the page base, r4 = the fill word for the rest.
_seed_pages:
2:      mov.l   @r14+, r2
        mov.l   r3, @r2
        mov     #16, r0
3:      add     #4, r2
        mov.l   r4, @r2
        dt      r0
        bf      3b
        cmp/hs  r5, r14
        bf      2b
        rts
        nop

        ! ---- Literal pool 1: the setup above. SH-2 `mov.l @(disp,PC)` is
        ! ---- FORWARD-only and reaches +1020 bytes, so the constants are
        ! ---- split into a setup pool here and a test pool after the body;
        ! ---- a few are duplicated in both. ----
        .align  2
p_rbclear:      .long   0xDFFFFFFF
p_vbr_val:      .long   _v_gi - 0x100
p_mmucr:        .long   0xFF000010
p_jmp_r14:      .long   0x4E2B0009      ! "jmp @r14" / "nop" delay slot
p_nopnop:       .long   0x00090009
p_poison_data:  .long   0xDEADBEEF
p_iseed_tab:    .long   _iseed_tab
p_iseed_end:    .long   _iseed_end
p_dseed_tab:    .long   _dseed_tab
p_dseed_end:    .long   _dseed_end
p_tsbbr_addr:   .long   0xFF000014
p_tsbbr_val:    .long   0x00006008      ! base=0x00006000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long   0xFF000018
p_tsbcfg_val:   .long   0x00000061      ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long   0xFF000048      ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:          .long   _tsb_tab
p_tab_end:      .long   _tsb_tab_end

        .balign 4
_iseed_tab:
        .long   0x80040000              ! P1(0x40000)  sub-test 1 PA_A
        .long   0x80041000              ! P1(0x41000)  sub-test 1 PA_B
        .long   0x80042000              ! P1(0x42000)  sub-test 1 PA_C
        .long   0x80043000              ! P1(0x43000)  sub-test 2 PA_A
        .long   0x80044000              ! P1(0x44000)  sub-test 2 PA_B
        .long   0x80045000              ! P1(0x45000)  sub-test 2 PA_C
_iseed_end:
_dseed_tab:
        .long   0x80046000              ! P1(0x46000)  sub-test 3 PA_A
        .long   0x80047000              ! P1(0x47000)  sub-test 3 PA_B
        .long   0x80048000              ! P1(0x48000)  sub-test 3 PA_C
_dseed_end:

        ! ---- TSB fill table: VA, ASID, PTEL. ----
        ! Rows 1-4 are the code superpage. The walker's tag compare is EXACT
        ! on the 4 KB VPN even for a superpage entry, so whichever of VPN 0..3
        ! is touched first must have a row; the PTEL installs the same 16 KB
        ! global identity mapping in every case.
        .balign 4
_tsb_tab:
        .long   0x00000000, 0x00000000, 0x000001CD  ! code 16K global W|X|C|V
        .long   0x00001000, 0x00000000, 0x000001CD
        .long   0x00002000, 0x00000000, 0x000001CD
        .long   0x00003000, 0x00000000, 0x000001CD
        .long   0x00020000, 0x00000011, 0x000400C9  ! 1: PA 0x40000, non-global
        .long   0x00020000, 0x00000022, 0x000410C9  ! 1: PA 0x41000, non-global
        .long   0x00020000, 0x00000000, 0x000420CD  ! 1: PA 0x42000, GLOBAL
        .long   0x00021000, 0x00000011, 0x000430C9  ! 2: PA 0x43000, non-global
        .long   0x00021000, 0x00000022, 0x000440C9  ! 2: PA 0x44000, non-global
        .long   0x00021000, 0x00000000, 0x000450CD  ! 2: PA 0x45000, GLOBAL
        .long   0x00022000, 0x00000011, 0x000460C9  ! 3: PA 0x46000, non-global
        .long   0x00022000, 0x00000022, 0x000470C9  ! 3: PA 0x47000, non-global
        .long   0x00022000, 0x00000000, 0x000480CD  ! 3: PA 0x48000, GLOBAL
_tsb_tab_end:

ENTRY(_run)
        ! ---- Enable AT once; it stays on for the whole guard body (the
        ! VBR+0x100 handler disables it before each resume, sub-tests
        ! re-enable it before their own multi-hit access). ASIDR is 0 here, so
        ! the next fetch and the next literal load each walk the code
        ! superpage in -- one into u_itlb, one into u_dtlb. ----
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================================================================
        ! Sub-test 1 (Milestone 1): I-side MULTI_HIT, no shadow arming.
        ! Three FETCHES of VA V1, one per ASID, build A / B / C.
        ! ================================================================
        SET_ASIDR q_asid_a
        mov.l   q_ret_1a, r14
        mov.l   q_p1_va, r0
        jmp     @r0                     ! install A (I-side miss under ASID_A)
        nop
ENTRY(_ret_1a)
        SET_ASIDR q_asid_b
        mov.l   q_ret_1b, r14
        mov.l   q_p1_va, r0
        jmp     @r0                     ! install B (A does not match ASID_B)
        nop
ENTRY(_ret_1b)
        SET_ASIDR q_asid_z
        mov.l   q_ret_1c, r14
        mov.l   q_p1_va, r0
        jmp     @r0                     ! install C, GLOBAL -> evicts A only
        nop
ENTRY(_ret_1c)
        ! -> A evicted (first match found), B survives, C occupies A's slot.

        SET_ASIDR q_asid_b              ! ASIDR := ASID_B (matches B)

        mov.l   q_g_exp_expevt, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! result-1 sentinel: no exception
        mov.l   q_g_bad_expevt, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! EXPEVT mismatch -> result 2
        mov.l   q_g_bad_fsr, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! MMUFSR mismatch -> result 3
        mov.l   q_g_resume, r0
        mov.l   q_after_1, r1
        mov.l   r1, @r0                 ! resume label on success

        mov.l   q_nx_1, r14             ! if the fetch SUCCEEDS, the candidate
                                        ! page returns here -> result 1
        mov.l   q_p1_va, r0
        jmp     @r0                     ! MUST fault -> _v_gi, MULTI_HIT
        nop
ENTRY(after_1)
        ! The VBR+0x100 handler disables AT before rte (mirrors mmufsr.S);
        ! each sub-test must re-enable it before its own multi-hit access.
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================================================================
        ! Sub-test 2 (Milestone 2): same shape, distinct VPN V2, with the
        ! shadow armed by an ordinary post-increment load IMMEDIATELY
        ! before the faulting jmp -- nothing else may touch memory in
        ! between (mmushadowld.S's construction hazard).
        ! ================================================================
        SET_ASIDR q_asid_a
        mov.l   q_ret_2a, r14
        mov.l   q_p2_va, r0
        jmp     @r0                     ! install A
        nop
ENTRY(_ret_2a)
        SET_ASIDR q_asid_b
        mov.l   q_ret_2b, r14
        mov.l   q_p2_va, r0
        jmp     @r0                     ! install B
        nop
ENTRY(_ret_2b)
        SET_ASIDR q_asid_z
        mov.l   q_ret_2c, r14
        mov.l   q_p2_va, r0
        jmp     @r0                     ! install C, GLOBAL
        nop
ENTRY(_ret_2c)
        SET_ASIDR q_asid_b              ! ASIDR := ASID_B

        mov.l   q_g_exp_expevt, r0
        mov     #6, r1
        mov.l   r1, @r0
        mov.l   q_g_bad_expevt, r0
        mov     #7, r1
        mov.l   r1, @r0
        mov.l   q_g_bad_fsr, r0
        mov     #8, r1
        mov.l   r1, @r0
        mov.l   q_g_resume, r0
        mov.l   q_after_2, r1
        mov.l   r1, @r0

        ! Preload everything the window needs BEFORE arming the shadow: the
        ! no-exception return label, the jmp target and the scratch base. No
        ! memory access may occur between the arming load and the faulting
        ! jmp.
        mov.l   q_nx_2, r14             ! no-exception return -> result 6
        mov.l   q_p2_va, r1             ! r1 = fault target (I-fetch VA)
        mov.l   q_scratch_addr, r2      ! r2 = scratch word address
        ! ==================== THE WINDOW: nothing between ================
        mov.l   @r2+, r12               ! arms ma_base/ma_numz/ma_autoupd
        jmp     @r1                     ! MUST fault -> _v_gi, MULTI_HIT
        nop
        ! ====================================================================
ENTRY(after_2)
        ! Re-enable AT again -- the handler always leaves it disabled.
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! r2 must hold EXACTLY scratch_addr + 4 -- the load's OWN
        ! post-increment, untouched by any bogus MULTI_HIT restore.
        mov.l   q_scratch_addr, r0
        add     #4, r0
        cmp/eq  r0, r2
        mov     #11, r9
        bf      _fail

        ! ================================================================
        ! Sub-test 3 (Milestone 3, control): D-side MULTI_HIT as the fault
        ! of the post-increment load itself. Because the walker installs by
        ! SIDE, all three installs here are ordinary LOADS, so A/B/C land in
        ! u_dtlb -- the array the faulting access will look up. The restore
        ! MUST still fire: Rn lands back at exactly the pre-increment VA.
        ! ================================================================
        SET_ASIDR q_asid_a
        mov.l   q_p3_va, r3
        mov.l   @r3, r0                 ! install A (D-side miss, ASID_A)
        SET_ASIDR q_asid_b
        mov.l   q_p3_va, r3
        mov.l   @r3, r0                 ! install B (A does not match ASID_B)
        SET_ASIDR q_asid_z
        mov.l   q_p3_va, r3
        mov.l   @r3, r0                 ! install C, GLOBAL -> evicts A only
        SET_ASIDR q_asid_b              ! ASIDR := ASID_B

        mov.l   q_g_exp_expevt, r0
        mov     #12, r1
        mov.l   r1, @r0
        mov.l   q_g_bad_expevt, r0
        mov     #13, r1
        mov.l   r1, @r0
        mov.l   q_g_bad_fsr, r0
        mov     #14, r1
        mov.l   r1, @r0
        mov.l   q_g_resume, r0
        mov.l   q_after_3, r1
        mov.l   r1, @r0

        mov.l   q_p3_va, r3             ! r3 = the multi-hit VA (D-side target)
        mov.l   @r3+, r13               ! MUST fault -> _v_gi, MULTI_HIT (D-side)
        ! Reached only if the load did NOT fault: the handler resumes at
        ! after_3 below, never here.
        mov     #12, r9
        bra     _fail
        nop
ENTRY(after_3)
        ! r3 must hold EXACTLY the pre-increment VA (the fault VA) -- the
        ! restore undid the speculative slot-0 bump, exactly as it does for
        ! any other faulting @Rn+ load.
        mov.l   q_p3_va, r0
        cmp/eq  r0, r3
        mov     #17, r9
        bf      _fail

        ! ---- Disable AT before handing back to the result harness. ----
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov     #0, r9
        bra     _done
        nop

! ---- "No exception" landing pads. A candidate page's `jmp @r14` returns
! ---- here when the multi-hit was NOT reached.
ENTRY(_nx_1)
        mov     #1, r9
        bra     _fail
        nop
ENTRY(_nx_2)
        mov     #6, r9
        bra     _fail
        nop

        ! ---- Literal pool 2: the test body. ----
        .align  2
q_mmucr:        .long   0xFF000010
q_asid_a:       .long   0x00000011      ! ASID_A
q_asid_b:       .long   0x00000022      ! ASID_B != ASID_A
q_asid_z:       .long   0x00000000      ! ASID_Z: the THIRD ASID, under which
                                        ! the GLOBAL row is published -- it is
                                        ! what makes the third access miss
q_scratch_addr: .long   _scratch_word
q_p1_va:        .long   0x00020000      ! sub-test 1 VPN V1
q_p2_va:        .long   0x00021000      ! sub-test 2 VPN V2
q_p3_va:        .long   0x00022000      ! sub-test 3 VPN V3
q_ret_1a:       .long   _ret_1a
q_ret_1b:       .long   _ret_1b
q_ret_1c:       .long   _ret_1c
q_ret_2a:       .long   _ret_2a
q_ret_2b:       .long   _ret_2b
q_ret_2c:       .long   _ret_2c
q_nx_1:         .long   _nx_1
q_nx_2:         .long   _nx_2

        ! ---- Handler globals (shared VBR+0x100 handler; each sub-test
        ! overwrites these before its own multi-hit access). ----
q_g_exp_expevt: .long   _g_exp_expevt
q_g_bad_expevt: .long   _g_bad_expevt
q_g_bad_fsr:    .long   _g_bad_fsr
q_g_resume:     .long   _g_resume
q_after_1:      .long   after_1
q_after_2:      .long   after_2
q_after_3:      .long   after_3

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
        !
        ! The handler runs with RB=1, where no walk can arm -- every page it
        ! touches (its own code, its literal pool, the globals below) lives in
        ! the 16 KB global code superpage, which is already resident in BOTH
        ! arrays by the time any sub-test can fault.
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
Hfsr_addr:      .long   0xFF00002C
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
! body run translated). It must stay below 0x4000 -- the end of the 16 KB
! code superpage.
ENTRY(_code_end)

        ! ---- The image must reach past the END of the guard's TSB: the
        ! ---- walker reads it by PHYSICAL address, and a physical alias is
        ! ---- backed by SRAM only within the loaded image extent.
        ! (.org is section-relative and .text starts at 0x1000; 0x7000 -> 0x8000,
        ! past the TSB's end at 0x00008000. It must also stay BELOW the M8
        ! harness scratch block at 0x00010000 -- sim/tests/Makefile fails the
        ! build if an m8_* image reaches it.)
        .org 0x7000

#endif  ! CONFIG_PRIV_ARCH
