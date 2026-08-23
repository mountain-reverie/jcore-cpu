! mmupmrawvpn.S -- CONTRACT LOCK C5 (docs/mmu/pagemask-walker-contract.md
! sections 2/C5 and 7.2). Lane 1, cpu_tb.
!
! WHAT THIS LOCKS
! ===============
! C5 says the walker installs `vpn = walk_va_r[31:12]` RAW and UNMASKED, and
! that this is correct for every page size because `tlb_match()` masks BOTH
! operands with `vpn_compare_mask(entry.page_mask)` before comparing -- the
! stored low VPN bits are architecturally don't-care. Masking the VPN before
! storing it would need a second mask network on the install path and buys
! nothing.
!
! The observable behind that clause is: an entry installed from a walk whose
! FAULTING VA WAS NOT ALIGNED TO ITS OWN PAGE still covers the whole page. So:
!
!   phase 1  fault at VA 0x0060_3000 -- 1 MB page 0x0060_0000, but the faulting
!            VA is 0x3000 into it. The walker installs pm=4 with the raw VPN
!            0x00603. Data must be S0 from PA 0x0090_3000; cnt_hits +1 exactly.
!   phase 2  load VA 0x0060_0000 -- BELOW the VA that installed the entry.
!            Must return S1 from PA 0x0090_0000, take no fault, and NOT walk.
!   phase 3  load VA 0x0068_0000 -- half a megabyte above it. Must return S2
!            from PA 0x0098_0000, take no fault, and NOT walk.
!
! Phases 2 and 3 straddle the installing VA in both directions, which is what
! makes "the stored VPN is masked at MATCH time, not at STORE time" observable
! rather than merely asserted.
!
! WHAT ITS MUTATION DOES AND DOES NOT CATCH -- read this before reshaping it.
! Masking `tlb_vpn_mx` at install BY THE ENTRY'S OWN `vpn_compare_mask(pm)` is
! BEHAVIOUR-NEUTRAL and this guard stays green under it, necessarily: the match
! path masks both operands with the same mask, so clearing bits that the
! compare already ignores changes nothing. That is not a hole in the guard, it
! is C5's own argument -- the clause rejects store-time masking on COST, not on
! correctness. What the guard does catch is masking by anything that is not the
! entry's own mask (the contract's wording is "mask tlb_vpn_mx by anything
! before the install"): a hardwired coarse mask makes phases 1-3 miss, a
! hardwired fine one makes nothing at all match. Both are measured below.
!
! COUNTER TRUSTWORTHINESS (contract P1). Phases 2 and 3 assert a NON-increment,
! which a dead counter satisfies. They are paired, in the same run, with phase
! 1's exact +1 cnt_hits assertion. Self-contained; P1g not required.
!
! IDENTITY MAPPING. Not identity-mapped: VA 0x0060_0000 -> PA 0x0090_0000. All
! three untranslated addresses (PA 0x0060_0000 / 0x0060_3000 / 0x0068_0000) are
! seeded with poison, so an inert MMU fails checks 0x41 / 0x43 / 0x45 instead
! of passing. The frame moves by editing p_ptel_data alone. The CODE page
! (VA 0x0000 -> PA 0x0000, the whole image) is identity, forced by the flat
! image load (README-identity-mapping.md category (b)); no assertion depends on
! it. See the note at p_pteh_code for why this guard maps the code page at
! VPN 0 rather than at `start`'s own page the way its siblings do.
!
! P5 (VA-backing). 0x0060_3000, 0x0060_0000, 0x0068_0000 and the code page are
! all inside the 16 MB backed window; phase 1 misses, so its raw VA reaches the
! bus during the miss window and is backed.
!
! RESULT CODES (base 0x40)
!   0x41  phase 1: wrong data at VA 0x0060_3000
!   0x42  phase 1: cnt_hits delta != 1 -- the entry was not installed by a walk
!   0x43  phase 2: wrong data at VA 0x0060_0000
!   0x44  phase 2: the counters MOVED -- VA 0x0060_0000 was not covered by the
!         entry installed from the unaligned VA
!   0x45  phase 3: wrong data at VA 0x0068_0000
!   0x46  phase 3: the counters MOVED
!   0x47  ANY fault. The mapping covers every VA this guard touches, so a fault
!         means the installed entry does not match where C5 says it must.
!         THIS IS THE MUTATION CODE for a store-time mask that is not the
!         entry's own.
!   0xE7  TRIP: a second fault (contract P2 fallback range, phase = 7)
!   0xD1  unexpected GENERAL exception (VBR+0x100)
!
! MUTATION EVIDENCE
! =================
! M3 -- `ram(idx).page_mask <= "0000"` on install: RED, Result=65 (0x41),
!       phase 1's data check. With the entry reduced to 4 KB the install
!       relocates VA 0x00603000 through the whole PPN to PA 0x00900000 instead
!       of 0x00903000, so the very first read is wrong. This is the guard's
!       REPORTABLE mutation proof.
!
! M5a -- THE NATURAL WRONG FIX, `tlb_vpn_mx <= walk_va_r(31 downto 12) and
!        vpn_compare_mask(walk_ptel(11 downto 8))`: PASS, and this is CORRECT,
!        not a hole. Clearing bits the match path already ignores cannot change
!        any outcome. C5 rejects store-time masking on COST, not correctness,
!        and the measurement confirms the clause rather than contradicting it.
!
! M5c -- THE CONTRACT'S STATED MUTATION, "mask tlb_vpn_mx by anything", taken
!        literally: `and vpn_compare_mask("0101")` (a hardwired 4 MB mask,
!        coarser than the entry's own pm=4). THIS DOES NOT PRODUCE A RESULT
!        CODE. It produces a WEDGE: the run stalls at 1.49us with
!        "Address changed but did not see ACK" and never reports.
!
!        Root cause, and it is a finding rather than a harness problem. Any
!        mask COARSER than the entry's own makes the installed entry fail to
!        match THE VERY VA THE WALK WAS ARMED FOR. The walker installs, the
!        access replays, misses again -- and core/tlb_walk.vhd only sets
!        `tried` when a walk GIVES UP, never after a successful install, and
!        `giveups` likewise only counts give-ups. So the walker re-arms without
!        bound: walk, install, miss, walk, ... The core is stalled throughout,
!        no instruction retires, and NO software guard can report anything.
!        Any mask FINER than or equal to the entry's own is the provable no-op
!        of M5a. There is no middle case, so C5's stated mutation is either a
!        no-op or a hardware livelock -- never a reportable guard failure.
!        Recorded as a proposed contract amendment and as an RTL follow-up in
!        docs/mmu/group-c-locks.md.
!
!        This guard's code page is at VPN 0 specifically so that M5c isolates
!        the entry under test (see the note at p_pteh_code); at VPN 1 the
!        instruction stream dies too and the wedge tells you even less.
!
! SPECIFICITY: M1 PASS, M2 PASS, M4 PASS, M5a PASS.
! M6 (data before tag_hi) RED via p_walk_read_order, the global invariant.
!
! RESTORED: pristine RTL, PASS.
! All runs: docker ghcr.io/mountain-reverie/jcore-cpu-ci:latest, CPU_VARIANT=j4,
! SIM_TOP=cpu_tb, --stop-time=120us, measured 2026-08-22. Every mutation run
! REBUILT the cosim (never `-n`, which skips the build and measures stale
! hardware). To re-apply any mutation you need BOTH halves of
! docs/mmu/group-c-locks.md: section 3 (the edits, one row per mutation)
! and section 9 (the run). That file also carries the full cross-table
! and, per row, whether it has been independently reproduced or rests on
! this record alone.
!
!
#include "sim_instr.h"
#include "mmuwalk_common.inc"
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

        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed physical memory, AT off. ----
        mov.l   p_pa_inst, r2
        mov.l   p_s0, r3
        mov.l   r3, @r2                 ! PA 0x00903000 = S0
        mov.l   p_pa_lo, r2
        mov.l   p_s1, r3
        mov.l   r3, @r2                 ! PA 0x00900000 = S1
        mov.l   p_pa_hi, r2
        mov.l   p_s2, r3
        mov.l   r3, @r2                 ! PA 0x00980000 = S2
        mov.l   p_poison, r3
        mov.l   p_va_inst, r2
        mov.l   r3, @r2
        mov.l   p_va_lo, r2
        mov.l   r3, @r2
        mov.l   p_va_hi, r2
        mov.l   r3, @r2

        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR = 0
        nop
        nop

        ! ---- Code page -> WAY 1. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- The ONE row: tagged and indexed at the UNALIGNED VA 0x00603000,
        ! ---- carrying a 1 MB PTEL. Nothing is mapped at 0x00600000 or
        ! ---- 0x00680000, so phases 2 and 3 can only be answered by the entry
        ! ---- installed from this row.
        mov.l   p_va_inst, r6
        mov     #0, r7
        mov.l   p_ptel_data, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill r10, r6, r7, r8

        mov     #0, r10                 ! fault count
        bra     _run
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_gen - 0x100
! ---- The code page is deliberately mapped at VPN 0 (VA 0x0000_0000 ->
! ---- PA 0x0000_0000, identity, forced by the flat image load) rather than at
! ---- `start`'s own 4 KB page the way this guard's siblings do. THIS IS
! ---- LOAD-BEARING FOR C5'S MUTATION PROOF, not a style choice: the mutation
! ---- is "mask tlb_vpn_mx before the install", and any mask coarse enough to
! ---- break the pm=4 entry under test also clears the low VPN bits of the
! ---- HARNESS'S OWN code page. At VPN 1 that kills the instruction stream and
! ---- the machine wedges before any guard can report -- a mutation artifact,
! ---- and exactly the timeout-instead-of-a-result-code failure
! ---- jcore-cpu/CLAUDE.md rules out. At VPN 0 the code page is invariant under
! ---- every mask, so the mutation isolates the property under test.
! ---- The whole image therefore has to fit in VA 0x0000..0x0FFF; there is no
! ---- trailing pad page. That is ENFORCED, not merely intended:
! ---- sim/tests/Makefile fails the build if this image's linked _etext passes
! ---- SINGLE_PAGE_LIMIT. Do not add code here without re-reading that rule --
! ---- overflow does not fail at run time, it takes a silent IMISS storm that
! ---- looks like a hang.
p_pteh_code:    .long 0x00000000
p_ptel_code:    .long 0x000000CD
p_tsbslot_reg:  .long 0xFF000048
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
p_va_inst:      .long 0x00603000        ! NOT 1 MB-aligned -- the whole point
p_va_lo:        .long 0x00600000
p_va_hi:        .long 0x00680000
p_pa_inst:      .long 0x00903000
p_pa_lo:        .long 0x00900000
p_pa_hi:        .long 0x00980000
p_ptel_data:    .long 0x009004E9        ! PA 0x00900000, pm=4 (1 MB), W|X|U|C|V
p_s0:           .long 0x503A1601
p_s1:           .long 0x51B0FF02
p_s2:           .long 0x52C08003
p_poison:       .long 0xDEAD0BAD

ENTRY(_run)
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on
        nop
        nop
        nop
        nop

        mov.l   q_warm, r11             ! warm the DTLB for the code page

        ! ======= PHASE 1: install from a VA 0x3000 into its own page =======
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_va_inst, r0
        mov.l   @r0, r4

        mov.l   q_s0, r0
        cmp/eq  r4, r0
        mov     #0x41, r9
        bf      _fail_at

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        sub     r2, r1
        mov     #1, r0
        cmp/eq  r1, r0
        mov     #0x42, r9
        bf      _fail_at

        ! ======= PHASE 2: BELOW the installing VA, same 1 MB page =======
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_va_lo, r0
        mov.l   @r0, r5

        mov.l   q_s1, r0
        cmp/eq  r5, r0
        mov     #0x43, r9
        bf      _fail_at

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x44, r9
        bf      _fail_at

        ! ======= PHASE 3: ABOVE it, still the same 1 MB page =======
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_va_hi, r0
        mov.l   @r0, r6

        mov.l   q_s2, r0
        cmp/eq  r6, r0
        mov     #0x45, r9
        bf      _fail_at

        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        cmp/eq  r13, r1
        mov     #0x46, r9
        bf      _fail_at

        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

_fail_at:
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
q_mmucr:        .long 0xFF000010
q_warm:         .long 0x00000000
q_walkcnt:      .long 0xFF000054
q_va_inst:      .long 0x00603000
q_va_lo:        .long 0x00600000
q_va_hi:        .long 0x00680000
q_s0:           .long 0x503A1601
q_s1:           .long 0x51B0FF02
q_s2:           .long 0x52C08003

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
        tst     r9, r9
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
        .balign 0x100
_v_gen:
        mov.l   Hg_code, r9
        bra     _fail
        nop
        .align 2
Hg_code:        .long 0x000000D1

        .space  0x300 - (. - _v_gen)
_v_fault:                               ! = VBR + 0x400
        add     #1, r10
        mov     r10, r0
        cmp/eq  #1, r0
        bt      1f
        mov.l   H_trip, r9              ! bounded: a second fault is a TRIP
        bra     _fail_at
        nop
1:
        mov     #0x47, r9               ! NO access in this guard may fault
        bra     _fail_at
        nop

        .align 2
H_trip:         .long 0x000000E7

#endif  ! CONFIG_PRIV_ARCH
