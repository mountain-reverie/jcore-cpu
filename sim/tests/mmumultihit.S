! mmumultihit.S -- S-I5: multiple TLB entries matching one lookup.
!
! WALKER-INSTALL VERSION (L1 pilot of "retire LDTLB"). Every TLB entry in this
! file is installed by the HARDWARE TSB WALKER; there is no LDTLB anywhere.
! The properties under test are unchanged, because the install-side dedup /
! overlap-eviction logic being tested lives in core/tlb.vhd's shared install
! process (the `tlb_wr` branch), which the walker drives through exactly the
! same {asidr, pteh_vpn, ptel} port LDTLB used. What changed is only HOW the
! second, overlapping install is provoked -- see "How the states are built".
!
! Two properties are verified, reflecting the dedup + install-time
! overlap-eviction design (jcore-soc components/cpu, task 3,
! "tlb-install-overlap"):
!
!  (A) DEDUP (the common case): installing a mapping that OVERLAPS a resident
!      one, under a predicate that makes the two the "same" mapping (same ASID,
!      or either side global), must REPLACE the resident entry in place -- one
!      valid entry, newest wins -- NOT leave two matching entries.
!      core/tlb.vhd's install loop scans for such an overlap and overwrites
!      that slot before falling back to NRU.
!
!  (B) INSTALL-TIME OVERLAP EVICTION ACROSS PAGE SIZES: dedup used to compare
!      VPN for EXACT equality only, so a small page installed inside the range
!      of a resident large page had a DIFFERENT exact VPN and was never
!      recognised as overlapping -- both entries stayed valid, and a lookup
!      landing in the overlap genuinely matched both, which the RTL (correctly,
!      at the time) reported as a fatal S-I5 multi-hit. Task 3 replaced the
!      exact-VPN compare with a MASKED overlap compare (under the intersection
!      -- the coarser -- of the two entries' page masks), so an install now
!      recognises this page-size-aliasing case as a genuine range overlap and
!      EVICTS the resident (large-page) entry at install time, same as (A).
!
!      The RTL's multi-hit detection itself (core/tlb.vhd tlb_match /
!      i_multihit / d_multihit, S-I5) is UNCHANGED and is the FAILURE MODE of
!      both tests here: if the overlapping install fails to evict, the lookups
!      at the end of each test match TWO entries and take General Illegal
!      (VBR+0x100), which the handler reports as result 1 / 5. So this guard
!      still exercises the S-I5 path -- as the thing that must NOT happen --
!      exactly as the LDTLB version did.
!
!      sim/tests/m8_multihit_ifetch.S remains the guard that reaches a genuine
!      S-I5 fault positively (three coexisting entries, only the first of which
!      the single-slot dedup can evict).
!
! ---- How the states are built WITHOUT LDTLB -------------------------------
! The walker only installs on a MISS, so "install twice over the same VA" can
! no longer be done by issuing two installs back to back: after the first
! install the VA hits and nothing walks. The lever that still produces a
! second, overlapping install is ASID + GLOBAL:
!
!   1. install a NON-GLOBAL entry under ASID A (a load under ASID A walks it in
!      from the TSB slot hashed for (VA, ASID A));
!   2. switch ASIDR to B. The resident entry is non-global with asid_tag=A, so
!      it does NOT match -> the same VA misses again -> a SECOND walk, which
!      reads the TSB slot hashed for (VA, ASID B). That slot holds a GLOBAL
!      PTEL, so the install's dedup predicate
!          (entry.global or ptel.global or entry.asid_tag = asidr)
!      is true against the resident ASID-A entry, and the masked-VPN overlap
!      compare decides whether the two ranges overlap;
!   3. switch ASIDR back to A. Now BOTH the (hypothetically surviving) ASID-A
!      entry and the new global entry would match the lookup. One entry ->
!      clean hit on the newest mapping. Two -> S-I5 multi-hit -> General
!      Illegal.
!
! That is the same shape as the LDTLB version -- resident entry, overlapping
! install, then a lookup that both would match -- with the ASID/global step
! supplying the second miss the walker needs. It is not weaker: step 3 makes
! the multi-hit the observable failure, which the LDTLB version's Test B had
! lost (there, a failure to evict merely returned other data).
!
! Construction (page sizes as in the LDTLB version):
!   - code: VA 0x0000..0x3FFF, GLOBAL 16 KB identity page (page_mask=1), W|X|C.
!     Global so that the ASID switches below never re-walk the code page and
!     perturb the walk counters. U=0 (SMEP: a kernel fetch of a U=1 page is a
!     protection fault).
!   - VPN 0x4 (VA 0x4000): walked in under ASID A -> PA 0x4000 (non-global),
!     then re-walked under ASID B -> PA 0x9000, GLOBAL. Exact-VPN overlap ->
!     dedup must collapse to ONE entry (newest, PA 0x9000, global).
!   - VPN 0x5 (VA 0x5000 -> PA 0x5000): single install -- negative control.
!   - VA 0x8000, page_mask=1 (16 KB, covers VA 0x8000..0xBFFF) -> PA 0x10000:
!     walked in under ASID A. Note the PA base is 0x10000, NOT 0x8000, so a
!     lookup of VA 0xA000 through the SUPERPAGE yields PA 0x12000 while a
!     lookup through the 4 KB entry yields PA 0xA000 -- the two are
!     distinguishable by the loaded data. (Under the old PA-0x8000 layout both
!     routes produced PA 0xA000 and the data check proved nothing.)
!   - VA 0xA000, 4 KB -> PA 0xA000, GLOBAL: walked in under ASID B (the
!     superpage is ASID-A non-global, so VA 0xA000 misses under B). Its masked
!     overlap compare against the resident superpage detects the overlap and
!     evicts it.
!
!   Test A: VA 0x4000 under ASID A after the global re-install -- must NOT
!     fault (dedup resolved it), must return PA 0x9000's data (newest install
!     won), and must NOT walk (it is served from the TLB, not re-fetched from
!     the TSB -- otherwise "the right answer" could come from a fresh walk
!     rather than from a correctly deduped array).
!   Negative control: VA 0x5000 -- must HIT, return PA 0x5000's data.
!   Test B: VA 0xA000 under ASID A after the global 4 KB install -- must NOT
!     fault (overlap eviction resolved it) and must return PA 0xA000's data,
!     not the superpage's PA 0x12000 data. Then VA 0x8000 must WALK again,
!     which is the POSITIVE witness that the superpage entry was really evicted
!     rather than merely shadowed.
!
! VBR = _v_gi - 0x100 so the General Illegal vector (VBR+0x100) hits _v_gi if
! any of these loads faults.
!
! PTEL flag bit layout (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C
!                                       bit2=G bit1=STALE bit0=V
! PTEL page_mask field: bits[11:8] (0x1 => ignore low 2 VPN bits, 16KB page).
! PTEL PA field: bits[27:12].
! NOTE bit0 (V) MUST be set in a TSB entry: core/tlb_walk.vhd rejects a data
! word with V=0 or STALE=1 as "no entry" (it would otherwise alias a zeroed
! TSB). The LDTLB version's PTELs ended in 0xC8; the walker needs 0xC9.
!
! TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x 32 bytes = 8 KB),
! HASH_SHIFT=6, HASH_MODE=1 -- the same configuration mmusplit.S /
! mmuwalkasid.S use, with a larger index so the nine entries below cannot
! collide. Slot addresses are NOT hand-computed: the guard asks the P4
! TSB-slot helper (0xFF000048, the single tsb_ptr() implementation the walker
! and TSBPTR also use) for each (VA, ASID) pair at fill time. Hand-derived
! hashes are exactly the kind of unchecked assertion this suite has been
! burned by.
!
! Result codes:
!   0    pass
!   1    Test A: VA 0x4000 under ASID A FAULTED after the global re-install --
!        the overlapping install did not replace in place, so the lookup
!        matched both entries (S-I5 multi-hit -> General Illegal)
!   2    Test A: wrong data -- the newest install (PA 0x9000) did not win
!   3    negative control (VA 0x5000) faulted unexpectedly
!   4    negative control returned wrong data
!   5    Test B: VA 0xA000 under ASID A FAULTED after the global 4 KB install
!        -- install-time overlap eviction did not resolve the large/small page
!        overlap before the lookup (a regression toward the pre-task-3
!        behaviour), so the lookup multi-hit
!   6    retired: previously "Test B load: EXPEVT != General Illegal", from
!        when Test B was expected to fault. No longer emitted; kept out of
!        reuse so any old failure logs referencing it are not misread.
!   7    Test B: VA 0xA000 returned wrong data -- the surviving mapping was not
!        the newest (4 KB, PA 0xA000) install
!   8    Test A: the settled VA 0x4000 lookup WALKED -- it was resolved by a
!        fresh TSB walk instead of by the deduped TLB entry
!   9    setup: VA 0x8000 did not return PA 0x10000's sentinel -- the superpage
!        was not installed as described
!   0x0A Test B: the superpage was NOT evicted -- VA 0x8000 still hit after the
!        overlapping 4 KB install (no walk)
!   0x0B setup: the first touch of VA 0x4000 under ASID A returned wrong data
!   0x0C setup: the superpage does not cover VA 0xA000 (it walked, or returned
!        data other than PA 0x12000's)
!   0x0D setup: a load faulted where the walker should have resolved it -- a
!        TSB entry is missing or landed in the wrong set
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS. Since the per-sub-test fail-code globals
! start at 0 until a sub-test sets them, a fault reaching _fail BEFORE the first
! sub-test runs would otherwise silently report PASS. _fail now clamps r9==0 to
! 0x7F before the store so 0 can never leave through the fail path. Fail-code
! globals below use loud sentinels (_g_exp_* = 0xFFFFFFFF, _g_bad_* = small
! distinct values) so an early exit still names its cause.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

        ! ASIDR is write-only through the J4 overlay encoding; two nops give
        ! the write time to land before the next translated access.
        .macro  SET_ASID lit
        mov.l   \lit, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_gi - 0x100 (so VBR+0x100 = _v_gi, the General
        ! Illegal vector). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed sentinels via P1 (untranslated, AT-independent). ----
        mov.l   p_sentinel_a, r3
        mov.l   p_p1_4000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_b, r3
        mov.l   p_p1_9000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_c, r3
        mov.l   p_p1_5000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_d, r3
        mov.l   p_p1_a000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_e, r3
        mov.l   p_p1_10000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_f, r3
        mov.l   p_p1_12000, r2
        mov.l   r3, @r2

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the TSB from the (VA, ASID, PTEL) table. For each row the
        ! ---- set address is asked of the P4 helper under that row's ASID, so
        ! ---- no hash is hand-computed here. AT is still off, so these are
        ! ---- plain untranslated P0 stores. ----
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

        ! ---- Literal pool 1: everything the setup above needs. SH-2
        ! ---- `mov.l @(disp,PC)` is FORWARD-only and reaches +1020 bytes, so
        ! ---- the constants are split into a setup pool here and a test pool
        ! ---- at the end of the body; a few are duplicated in both. ----
        .align 2
p_rbclear:                .long 0xDFFFFFFF
p_vbr_val:                .long _v_gi - 0x100
p_tsbbr_addr:             .long 0xFF000014
p_tsbbr_val:              .long 0x00014008  ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:            .long 0xFF000018
p_tsbcfg_val:             .long 0x00000061  ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:                .long 0xFF000048  ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:                    .long _tsb_tab
p_tab_end:                .long _tsb_tab_end
p_sentinel_a:             .long 0xA51DA51D        ! at PA 0x4000
p_sentinel_b:             .long 0xB33FB33F        ! at PA 0x9000
p_sentinel_c:             .long 0xC0FFEE00        ! at PA 0x5000
p_sentinel_d:             .long 0xD00D0000        ! at PA 0xA000
p_sentinel_e:             .long 0xE11CE11C        ! at PA 0x10000
p_sentinel_f:             .long 0xF00DF00D        ! at PA 0x12000
p_p1_4000:                .long 0x80004000
p_p1_9000:                .long 0x80009000
p_p1_5000:                .long 0x80005000
p_p1_a000:                .long 0x8000A000
p_p1_10000:               .long 0x80010000
p_p1_12000:               .long 0x80012000

        ! ---- TSB fill table: VA, ASID, PTEL. ----
        ! Rows 1-4 are the code page. The walker's tag compare is EXACT on the
        ! 4 KB VPN even for a superpage entry, so whichever of VPN 0..3 is
        ! touched first must have a row; the PTEL installs the same 16 KB
        ! global identity mapping in every case, and after the first install
        ! the other three VPNs hit and never walk.
        .balign 4
_tsb_tab:
        .long 0x00000000, 0x00000011, 0x000001CD  ! code 16K global W|X|C|V
        .long 0x00001000, 0x00000011, 0x000001CD
        .long 0x00002000, 0x00000011, 0x000001CD
        .long 0x00003000, 0x00000011, 0x000001CD
        .long 0x00004000, 0x00000011, 0x000040C9  ! PA 0x4000, 4K, W|C|V
        .long 0x00004000, 0x00000022, 0x000090CD  ! PA 0x9000, 4K, W|C|G|V
        .long 0x00005000, 0x00000011, 0x000050C9  ! PA 0x5000, 4K, W|C|V
        .long 0x00008000, 0x00000011, 0x000101C9  ! PA 0x10000, 16K, W|C|V
        .long 0x0000A000, 0x00000022, 0x0000A0CD  ! PA 0xA000, 4K, W|C|G|V
_tsb_tab_end:

ENTRY(_run)
        ! ---- ASIDR = A, then enable AT. The instruction stream and the
        ! ---- literal pools live in the global 16 KB code page, so the first
        ! ---- I-side and D-side accesses each take one walk and nothing after
        ! ---- that re-walks code. ----
        SET_ASID p_asid_a

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================= Setup: first install of VA 0x4000 =============
        ! Any fault from here on is a walk that failed to find its TSB entry.
        mov.l   p_g_exp_expevt, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0 (no fault expected)
        mov.l   p_g_bad_expevt, r0
        mov     #0x0D, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_l_setup_fault, r1
        mov.l   r1, @r0

        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! MISS -> walk -> PA 0x4000, ASID A
        mov.l   q_sentinel_a, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #0x0B, r9
        bra     _fail
        nop
1:
        ! ---- ASID B: the resident entry is non-global/ASID A, so this VA
        ! ---- misses again and the second walk installs the GLOBAL PA 0x9000
        ! ---- mapping. Its dedup predicate is true against the resident entry
        ! ---- (new entry is global) and its VPN is identical, so the resident
        ! ---- slot must be overwritten in place.
        SET_ASID p_asid_b

        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! MISS -> walk -> PA 0x9000, GLOBAL
        mov.l   q_sentinel_b, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #2, r9
        bra     _fail
        nop
1:
        ! ================= Test A: DEDUP (VA 0x4000 under ASID A) =========
        ! Both the (hypothetically surviving) ASID-A entry and the new global
        ! entry would match this lookup. A fault here IS the S-I5 multi-hit ->
        ! result 1. Correct dedup leaves exactly one entry: a clean hit that
        ! returns PA 0x9000's data and does NOT walk.
        SET_ASID p_asid_a

        mov.l   p_g_bad_expevt, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! any fault -> EXPEVT-mismatch -> result 1
        mov.l   p_g_resume, r0
        mov.l   p_l_dedup_fault, r1
        mov.l   r1, @r0                 ! (fluke EXPEVT match) -> result 1 too

        mov.l   p_walkcnt, r4
        mov.l   c_va4, r2
        mov.l   @r4, r13
        shlr16  r13                     ! r13 = cnt_walks before
        mov.l   @r2, r8                 ! must NOT fault
        mov.l   @r4, r3
        shlr16  r3
        sub     r13, r3                 ! r3 = walks taken by the lookup
        tst     r3, r3
        bt      1f
        mov     #8, r9                  ! served by a fresh walk, not the TLB
        bra     _fail
        nop
1:      mov.l   q_sentinel_b, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #2, r9                  ! newest install did not win
        bra     _fail
        nop
1:
        ! ============ Negative control: single install (VA 0x5000) ======
        mov.l   p_g_bad_expevt, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! any fault here -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_l_negctrl_fault, r1
        mov.l   r1, @r0

        mov.l   c_va5, r2
        mov.l   @r2, r8                 ! MISS -> walk -> PA 0x5000
        mov.l   q_sentinel_c, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #4, r9                  ! wrong data on single hit
        bra     _fail
        nop
1:
        ! ======== Test B setup: the 16 KB superpage (VA 0x8000..0xBFFF) ====
        mov.l   p_g_bad_expevt, r0
        mov     #0x0D, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_l_setup_fault, r1
        mov.l   r1, @r0

        mov.l   c_va8, r2
        mov.l   @r2, r8                 ! MISS -> walk -> superpage, PA 0x10000
        mov.l   q_sentinel_e, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #9, r9                  ! superpage not installed as described
        bra     _fail
        nop
1:
        ! ---- The superpage must COVER VA 0xA000: this lookup must hit it
        ! ---- (no walk) and return PA 0x12000's data. Without this the
        ! ---- eviction test below would be testing nothing -- an entry that
        ! ---- never covered 0xA000 cannot overlap the 4 KB install.
        mov.l   p_walkcnt, r4
        mov.l   c_vaa, r2
        mov.l   @r4, r13
        shlr16  r13
        mov.l   @r2, r8
        mov.l   @r4, r3
        shlr16  r3
        sub     r13, r3
        tst     r3, r3
        bt      1f
        mov     #0x0C, r9               ! walked -> the superpage does not cover it
        bra     _fail
        nop
1:      mov.l   q_sentinel_f, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #0x0C, r9               ! covered, but not via PA 0x12000
        bra     _fail
        nop
1:
        ! ---- ASID B: the superpage is ASID-A non-global, so VA 0xA000 misses
        ! ---- and the walk installs the GLOBAL 4 KB PA 0xA000 mapping. Its
        ! ---- masked overlap compare (mask intersection = the superpage's,
        ! ---- ignoring VPN[1:0]) sees VPN 0x8 vs 0xA as overlapping and must
        ! ---- evict the superpage in place.
        SET_ASID p_asid_b

        mov.l   c_vaa, r2
        mov.l   @r2, r8                 ! MISS -> walk -> 4 KB PA 0xA000, GLOBAL
        mov.l   q_sentinel_d, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #7, r9
        bra     _fail
        nop
1:
        ! ======== Test B: INSTALL-TIME OVERLAP EVICTION (VA 0xA000) =======
        ! Under ASID A the superpage (if it survived) and the new global 4 KB
        ! entry BOTH match -> S-I5 multi-hit -> General Illegal -> result 5.
        SET_ASID p_asid_a

        mov.l   p_g_bad_expevt, r0
        mov     #5, r1
        mov.l   r1, @r0                 ! any fault -> EXPEVT-mismatch -> result 5
        mov.l   p_g_resume, r0
        mov.l   p_l_multihit_fault, r1
        mov.l   r1, @r0

        mov.l   c_vaa, r2
        mov.l   @r2, r8                 ! must NOT fault
        mov.l   q_sentinel_d, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #7, r9                  ! surviving mapping's data wrong
        bra     _fail
        nop
1:
        ! ---- POSITIVE witness that the superpage was EVICTED, not merely
        ! ---- shadowed: VA 0x8000 must now MISS and walk again. (That walk
        ! ---- reinstalls the superpage and, by the same overlap rule, evicts
        ! ---- the 4 KB entry -- which is fine, the test ends here.)
        mov.l   p_g_bad_expevt, r0
        mov     #0x0D, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_l_setup_fault, r1
        mov.l   r1, @r0

        mov.l   p_walkcnt, r4
        mov.l   c_va8, r2
        mov.l   @r4, r13
        shlr16  r13
        mov.l   @r2, r8
        mov.l   @r4, r3
        shlr16  r3
        sub     r13, r3
        mov     #1, r1
        cmp/eq  r1, r3
        bt      1f
        mov     #0x0A, r9               ! no walk -> the superpage still resident
        bra     _fail
        nop
1:
        ! ---- Disable AT before handing the result to the harness. ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #0, r9
        bra     _done
        nop

        ! ---- Fail landing pads for loads that must not fault. ----
ENTRY(l_dedup_fault)
        mov     #1, r9
        bra     _fail
        nop
ENTRY(l_negctrl_fault)
        mov     #3, r9
        bra     _fail
        nop
ENTRY(l_multihit_fault)
        mov     #5, r9
        bra     _fail
        nop
ENTRY(l_setup_fault)
        mov     #0x0D, r9
        bra     _fail
        nop

        ! ---- Literal pool 2: everything the test body needs. ----
        .align 2
p_mmucr:                  .long 0xFF000010
p_walkcnt:                .long 0xFF000054  ! [31:16]=cnt_walks [15:0]=cnt_hits
p_asid_a:                 .long 0x00000011
p_asid_b:                 .long 0x00000022
q_sentinel_a:             .long 0xA51DA51D        ! at PA 0x4000
q_sentinel_b:             .long 0xB33FB33F        ! at PA 0x9000 (dedup: newest wins)
q_sentinel_c:             .long 0xC0FFEE00        ! at PA 0x5000 (negative control)
q_sentinel_d:             .long 0xD00D0000        ! at PA 0xA000 (4 KB mapping)
q_sentinel_e:             .long 0xE11CE11C        ! at PA 0x10000 (superpage, VA 0x8000)
q_sentinel_f:             .long 0xF00DF00D        ! at PA 0x12000 (superpage, VA 0xA000)
c_va4:                    .long 0x00004000
c_va5:                    .long 0x00005000
c_va8:                    .long 0x00008000
c_vaa:                    .long 0x0000A000
p_g_exp_expevt:           .long _g_exp_expevt
p_g_bad_expevt:           .long _g_bad_expevt
p_g_resume:               .long _g_resume
p_l_dedup_fault:          .long l_dedup_fault
p_l_negctrl_fault:        .long l_negctrl_fault
p_l_multihit_fault:       .long l_multihit_fault
p_l_setup_fault:          .long l_setup_fault

#endif  ! CONFIG_PRIV_ARCH

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

        ! ---- General Illegal handler at VBR+0x100. Disables AT, verifies
        ! EXPEVT == g_exp_expevt (distinguishing S-I5's multi-hit dispatch
        ! from any other trap), then resumes at the caller-selected _g_resume
        ! label. A load that must NOT fault points _g_resume at a fail pad. ----
        .balign 4
        .space 0x100, 0
        .balign 4
_v_gi:                                   ! = VBR + 0x100
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Hresume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_expevt:
        mov.l   Hbad_expevt, r0
        mov.l   @r0, r9                 ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hexp_expevt:    .long _g_exp_expevt
Hresume:        .long _g_resume
Hbad_expevt:    .long _g_bad_expevt

        ! ---- Handler globals. ----
        .balign 4
_g_exp_expevt:  .long 0xFFFFFFFF        ! sentinel: unset (a real sub-test always overwrites)
_g_bad_expevt:  .long 0x5A              ! loud fail-code sentinel: names an early fault
_g_resume:      .long 0

        ! ---- Backing store: PA 0x4000 .. 0x13FFF (the mapped data pages) and
        ! ---- the TSB at PA 0x14000..0x15FFF. Everything above is zero-filled
        ! ---- image, so the TSB starts out empty and the fill loop is the only
        ! ---- thing that puts entries in it. ----
_fault_pages:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
