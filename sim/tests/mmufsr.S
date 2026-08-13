! mmufsr.S -- MMUFSR (MMU Fault Status Register, MMIO 0xFF00002C) guard.
!
! THE POINT OF THIS GUARD: EXPEVT alone cannot distinguish every fault cause
! (DPROT_R and DPROT_W both raise EXPEVT=0x0C0 via the single merged vector
! VBR+0x400). MMUFSR carries the fault kind (and direction/USER/ITLB detail)
! that EXPEVT discards. This guard covers all SEVEN fault kinds:
!   A DPROT_W  B DPROT_R  C DMISS_R  D DMISS_W  E IMISS  F IPROT  G MULTI_HIT
!
! Scaffolding mirrors sim/tests/mmufault.S: same .vect header, same single
! _v_tlb handler at VBR+0x400 for the six TLB-vectored kinds (A-F), same
! _done/_fail epilogue. MULTI_HIT (G) does not dispatch through VBR+0x400 --
! see its own comment block below -- so it uses a second handler at
! VBR+0x100, installed by reloading VBR just before sub-test G.
!
! PTEL flag bit layout (core/tlb.vhd lines 120-126):
!   bit7=W  bit6=X  bit5=U  bit4=D  bit3=C
!   page 0 full-access : W|X|U|C = 0xE8
!   page 2 read-only   : X|U|C   = 0x68  (W=0 -> DPROT_W on store)
!   page 3 no-execute  : W|U|C   = 0xA8  (X=0 -> IPROT  on fetch)
!   page 4 super-only  : W|X|C   = 0xC8  (U=0 -> DPROT_R on user load)
!   page 1 left UNMAPPED (in bus range via _fault_pages, not in TLB) for the
!     C/D/E miss sub-tests.
!   pages 8/9 (multi-hit, sub-test G): master's 7f9b51f made install-time dedup
!     range-overlap-aware (not just exact-VPN), so mmumultihit.S's old
!     large-page/small-page two-install construction no longer multi-hits --
!     the second install's overlap scan evicts the first mapping in place (see
!     sim/tests/mmumultihit.S header). The scan sits on the SHARED install
!     port (core/tlb.vhd, on tlb_wr), so it applies to walker installs exactly
!     as it applied to LDTLB's. To still reach a genuine multi-hit (independent
!     multi-entry overlap, which install-time dedup cannot reach because it
!     only evicts the FIRST matching resident entry it finds), sub-test G
!     brings in THREE entries: VPN 0x8 (4KB, PA 0x8000), VPN 0x9 (4KB, PA
!     0x9000, does not overlap VPN 0x8's page), then VPN 0x8 again with
!     pageMask=1 (16KB, covers VPN 0x8..0xB, PA 0x8000). Each is installed by
!     the walker from a TSB row when the page is touched; the exact touch
!     order and ASID trick are documented at the setup site below. The third
!     install's overlap scan finds
!     VPN 0x8's slot first and evicts it, but VPN 0x9's slot -- which also
!     overlaps the new 16KB page's range -- is never reached, so it survives.
!     A load from VPN 0x9 then genuinely matches both the surviving VPN 0x9
!     entry and the new VPN 0x8 superpage -- real MULTI_HIT.
!
! MMUFSR layout (docs/mmu/hardware-spec.md):
!   [12] VALID  [11:8] KIND  [7:5] rsvd(0)
!   [4] USER  [3] PROT  [2] ITLB  [1] INITIAL(0)  [0] WRITE
!   KIND: 1=IMISS 2=DMISS_R 3=DMISS_W 4=IPROT 5=DPROT_R 6=DPROT_W 7=MULTI_HIT
!
! Every sub-test compares the FULL 32-bit MMUFSR word, not a masked subset.
! This is deliberate: it enforces that bits [31:13] and [7:5] read as zero,
! which linux@jcore's entry.S depends on (it derives error_code with a bare
! extu.b). Do not relax these to masked compares.
!
! Sub-test A: supervisor STORE to page 2 (read-only, W=0) -> DPROT_W, KIND=6
!   expect MMUFSR = 0x1000 | 0x600 | 0x08(PROT) | 0x01(WRITE) = 0x1609
!   USER=0 (supervisor). Also assert EXPEVT == 0x0C0.
! Sub-test B: user-mode LOAD from page 4 (supervisor-only, U=0) -> DPROT_R,
!   KIND=5. expect MMUFSR = 0x1000 | 0x500 | 0x10(USER) | 0x08(PROT) = 0x1518
!   (WRITE=0). Also assert EXPEVT == 0x0C0.
! Sub-test C: supervisor LOAD from page 1 (unmapped) -> DMISS_R, KIND=2.
!   expect MMUFSR = 0x1000 | 0x200 = 0x1200. EXPEVT == 0x060.
! Sub-test D: supervisor STORE to page 1 (unmapped) -> DMISS_W, KIND=3.
!   expect MMUFSR = 0x1000 | 0x300 | 0x01(WRITE) = 0x1301. EXPEVT == 0x080.
! Sub-test E: supervisor JUMP to page 1 (unmapped) -> IMISS, KIND=1.
!   expect MMUFSR = 0x1000 | 0x100 | 0x04(ITLB) = 0x1104. EXPEVT == 0x040.
! Sub-test F: user-mode JUMP to page 3 (X=0) -> IPROT, KIND=4.
!   expect MMUFSR = 0x1000 | 0x400 | 0x10(USER) | 0x08(PROT) | 0x04(ITLB)
!                 = 0x141C. The only case with three low-byte bits set at
!   once. EXPEVT == 0x0A0.
! Sub-test G: MULTI_HIT, KIND=7. Two TLB entries genuinely match one lookup
!   (VPN 0x9, 4KB, PA 0x9000 survives independently of a later-installed VPN
!   0x8 superpage, mask=1, covering VPN 0x8..0xB, PA 0x8000 -- install-time
!   overlap dedup only evicts the FIRST matching resident entry it scans, so
!   VPN 0x9's slot survives even though it overlaps the superpage's range;
!   see the header construction note above). MULTI_HIT does NOT vector to VBR+0x400;
!   it dispatches via the existing General Illegal register-model exception
!   to VBR+0x100, EXPEVT=0x180 (core/cpu.vhd, decode/decode_core.vhm --
!   decoder system-plane immediate field was already full). expect MMUFSR =
!   0x1000 | 0x700 = 0x1700, entire low byte zero including USER.
! Also assert MMUFSR reads 0 before any fault occurs (VALID=0, KIND=0).
!
! Result codes:
!   0  all pass
!   1  A: no exception       2  A: MMUFSR != 0x1609    3  A: EXPEVT != 0x0C0
!   4  B: no exception       5  B: MMUFSR != 0x1518     6  B: EXPEVT != 0x0C0
!   7  MMUFSR != 0 before any fault
!   8  C: no exception       9  C: MMUFSR != 0x1200    10  C: EXPEVT != 0x060
!  11  D: no exception      12  D: MMUFSR != 0x1301    13  D: EXPEVT != 0x080
!  14  E: no exception      15  E: MMUFSR != 0x1104    16  E: EXPEVT != 0x040
!  17  F: no exception      18  F: MMUFSR != 0x141C    19  F: EXPEVT != 0x0A0
!  20  G: no exception      21  G: MMUFSR != 0x1700 (or wrong EXPEVT, i.e.
!                               not routed through General Illegal 0x180)
!
! J4 overlay opcodes:
!   LDC r0,VBR=0x402E  LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E
!   LDC r0,ASIDR=0x407E
!   STC EXPEVT,r0=0x0052
!   STC SSR,r1=0x0132  LDC r1,SSR=0x413E  LDC r0,SPC=0x404E

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

        ! ---- VBR = _v_tlb - 0x400 (so VBR+0x400=_v_tlb). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB: base 0x00018000, TSB_SIZE_LOG=8 (256 sets x
        ! ---- 32 bytes = 0x18000..0x19FFF), HASH_SHIFT=6, HASH_MODE=1. Clear of
        ! ---- every page this guard maps (0x1000..0xBFFF) and inside the image,
        ! ---- so it is zero-filled and the fill loop is all that is in it. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Every mapping this guard used to LDTLB is now a TSB ROW that the
        ! ---- hardware walker pulls in on demand, at the moment of the access
        ! ---- that needs it. That ordering change is invisible to sub-tests A-F:
        ! ---- a permission fault still needs the entry resident, so the walker
        ! ---- installs it from the row and the permission check then fires on
        ! ---- the replay, with the same EXPEVT and the same MMUFSR. The rows for
        ! ---- pages 3, tramp_b and tramp_f are hoisted here from the sub-tests
        ! ---- that used to LDTLB them individually; a row is inert until touched,
        ! ---- so hoisting cannot make a sub-test fire early.
        ! ----
        ! ---- The rows whose VA is a link-time label (the code page and the two
        ! ---- user trampolines) are patched at RUNTIME below, because their VPN
        ! ---- is only known at link time -- the same reason the LDTLB version
        ! ---- computed PTEH from &start.
        ! ----
        ! ---- Set addresses come from the P4 slot helper (0xFF000048) under each
        ! ---- row's own ASID; nothing hand-computes the hash. ----
        mov.l   p_pagemask, r1

        mov.l   p_tab_code, r2          ! code page row: VA and PPN from &start
        mov.l   p_start_addr, r0
        and     r1, r0
        mov.l   r0, @r2                 ! row VA
        mov.l   p_ptel_page0, r3
        or      r3, r0
        mov.l   r0, @(8, r2)            ! row PTEL = (start & mask) | W|X|C|G|V

        mov.l   p_tab_trampb, r2        ! tramp_b row
        mov.l   p_tramp_b_addr, r0
        and     r1, r0
        mov.l   r0, @r2
        mov.l   p_ptel_tramp, r3
        or      r3, r0
        mov.l   r0, @(8, r2)

        mov.l   p_tab_trampf, r2        ! tramp_f row
        mov.l   p_tramp_f_addr, r0
        and     r1, r0
        mov.l   r0, @r2
        mov.l   p_ptel_tramp, r3
        or      r3, r0
        mov.l   r0, @(8, r2)

        ! ---- Fill loop. AT is off, so these are plain P0 stores. ----
        mov.l   p_tsbslot, r12
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

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR (back to ASID 0)
        nop
        nop

        ! ==============================================================
        ! Assert MMUFSR reads 0 before any fault has occurred. Done here,
        ! BEFORE enabling AT: MMUFSR is P4 MMIO and doesn't depend on AT,
        ! and keeping this check out of the post-AT-enable instruction
        ! stream avoids widening the window between "AT.write" and the
        ! first genuine fault -- once I-fetch translation catches up to a
        ! U=1 page-0 fetch in supervisor mode, SMEP (mmusmep, cpu.vhd/
        ! tlb.vhd: "kernel fetch of user page") legitimately faults, and a
        ! few extra instructions here was enough to cross that window
        ! ahead of sub-test A's intended DPROT_W access.
        ! ==============================================================
        mov.l   p_fsr_addr, r0
        mov.l   @r0, r1
        mov     #0, r2
        cmp/eq  r1, r2
        bt      mmufsr_zero_ok
        mov     #7, r9
        bra     _fail
        nop
mmufsr_zero_ok:

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ==============================================================
        ! Sub-test A: DPROT_W -- supervisor STORE to page 2 (W=0).
        ! ==============================================================
        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_dprot_w, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1609
        mov.l   p_g_exp_expevt, r0
        mov.l   c_expevt_dprot, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x0C0
        mov.l   p_g_bad_fsr, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 2
        mov.l   p_g_bad_expevt, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_after_a, r1
        mov.l   r1, @r0                 ! resume -> after_a

        mov     #1, r9                  ! sentinel: no exception = result 1
        mov     #0x66, r3
        mov.l   c_page2_va, r2
        mov.l   r3, @r2                 ! FAULTS -> _v_tlb (VBR+0x400), DPROT_W

        bra     _fail
        nop

ENTRY(after_a)
        ! ==============================================================
        ! Sub-test B: DPROT_R -- USER-mode LOAD from page 4 (U=0).
        ! ==============================================================
        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_dprot_r, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1518
        mov.l   p_g_exp_expevt, r0
        mov.l   c_expevt_dprot, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x0C0
        mov.l   p_g_bad_fsr, r0
        mov     #5, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 5
        mov.l   p_g_bad_expevt, r0
        mov     #6, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 6
        mov.l   p_g_resume, r0
        mov.l   p_after_b, r1
        mov.l   r1, @r0                 ! resume -> after_b

        ! Re-enable AT: handler disabled MMUCR on entry to sub-test A.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! Own page (page 0) is now U=0/kernel-only (see p_ptel_page0 note),
        ! so user-mode code cannot execute from it -- a raw ldc-sr MD-clear
        ! followed by continued fetch from page 0 would immediately fault
        ! (core/tlb.vhd: entry.u=0 and md=0, the pre-existing user-fetch-of-
        ! supervisor-page rule) before the intended DPROT_R access ever runs.
        ! Fix: install a separate U=1 trampoline page and drop to user mode
        ! via RTE (SPC/SSR atomic transition), matching the technique
        ! validated in mmufault.S/mmusmep.S. The trampoline's own PTEH is
        ! computed at RUNTIME from its own link address (masked to a page
        ! boundary) rather than hardcoded.
        ! (tramp_b's mapping is a TSB row filled in setup; the walker installs
        ! it on the first fetch after the RTE below drops to user mode.)

        mov.l   p_tramp_b_addr, r0
        .word   0x404E                  ! LDC r0, SPC (target = &_user_tramp_b)
        stc     sr, r1
        mov.l   p_mdclear, r4
        and     r4, r1                  ! r1 = SR with MD cleared
        .word   0x413E                  ! LDC r1, SSR (opcode 0x413E hardcodes
                                         ! Rm=r1 -- see header comment line 80)
        rte                             ! PC:=SPC, SR:=SSR together
        nop

ENTRY(after_b)
        ! ==============================================================
        ! Sub-test C: DMISS_R -- supervisor LOAD from page 1 (unmapped).
        ! Fault sequence copied verbatim from mmufault.S sub-test A.
        ! ==============================================================
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT (handler disabled it)

        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_dmiss_r, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1200
        mov.l   p_g_exp_expevt, r0
        mov.l   c_expevt_dmiss_r, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x060
        mov.l   p_g_bad_fsr, r0
        mov     #9, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 9
        mov.l   p_g_bad_expevt, r0
        mov     #10, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 10
        mov.l   p_g_resume, r0
        mov.l   p_after_c, r1
        mov.l   r1, @r0                 ! resume -> after_c

        mov     #8, r9                  ! sentinel: no exception = result 8
        mov.l   c_page1_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_tlb (VBR+0x400), DMISS_R

        bra     _fail
        nop

ENTRY(after_c)
        ! ==============================================================
        ! Sub-test D: DMISS_W -- supervisor STORE to page 1 (unmapped).
        ! Fault sequence copied verbatim from mmufault.S sub-test B.
        ! ==============================================================
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT

        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_dmiss_w, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1301
        mov.l   p_g_exp_expevt, r0
        mov.l   c_expevt_dmiss_w, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x080
        mov.l   p_g_bad_fsr, r0
        mov     #12, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 12
        mov.l   p_g_bad_expevt, r0
        mov     #13, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 13
        mov.l   p_g_resume, r0
        mov.l   p_after_d, r1
        mov.l   r1, @r0                 ! resume -> after_d

        mov     #11, r9                 ! sentinel: no exception = result 11
        mov     #0x55, r3
        mov.l   c_page1_va, r2
        mov.l   r3, @r2                 ! FAULTS -> _v_tlb (VBR+0x400), DMISS_W

        bra     _fail
        nop

ENTRY(after_d)
        ! ==============================================================
        ! Sub-test E: IMISS -- supervisor JUMP to page 1 (unmapped).
        ! Fault sequence copied verbatim from mmufault.S sub-test C.
        ! ==============================================================
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT

        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_imiss, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1104
        mov.l   p_g_exp_expevt, r0
        mov.l   c_expevt_imiss, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x040
        mov.l   p_g_bad_fsr, r0
        mov     #15, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 15
        mov.l   p_g_bad_expevt, r0
        mov     #16, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 16
        mov.l   p_g_resume, r0
        mov.l   p_after_e, r1
        mov.l   r1, @r0                 ! resume -> after_e

        mov     #14, r9                 ! sentinel: no exception = result 14
        mov.l   c_page1_va, r0
        jmp     @r0                     ! FAULTS -> _v_tlb (VBR+0x400), IMISS
        nop

        bra     _fail
        nop

ENTRY(after_e)
        ! ==============================================================
        ! Sub-test F: IPROT -- user-mode JUMP to page 3 (X=0, PTEL 0xA8).
        ! Fault sequence copied verbatim from mmufault.S sub-test E.
        ! ==============================================================
        ! (page 3's no-execute mapping is a TSB row filled in setup; the walker
        ! installs it on the faulting fetch, and IPROT then fires on the replay.)

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT

        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_iprot, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x141C
        mov.l   p_g_exp_expevt, r0
        mov.l   c_expevt_iprot, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x0A0
        mov.l   p_g_bad_fsr, r0
        mov     #18, r1
        mov.l   r1, @r0                 ! MMUFSR wrong -> result 18
        mov.l   p_g_bad_expevt, r0
        mov     #19, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 19
        mov.l   p_g_resume, r0
        mov.l   p_after_f, r1
        mov.l   r1, @r0                 ! resume -> after_f

        ! Own page (page 0) is now U=0/kernel-only; see p_ptel_page0 note.
        ! Install a separate U=1 trampoline page and drop to user mode via
        ! RTE (see the sub-test B comment above and mmufault.S/mmusmep.S).
        ! (tramp_f's mapping is a TSB row filled in setup.)

        mov.l   p_tramp_f_addr, r0
        .word   0x404E                  ! LDC r0, SPC (target = &_user_tramp_f)
        stc     sr, r1
        mov.l   p_mdclear, r4
        and     r4, r1                  ! r1 = SR with MD cleared
        .word   0x413E                  ! LDC r1, SSR (opcode 0x413E hardcodes
                                         ! Rm=r1 -- see header comment line 80)
        rte                             ! PC:=SPC, SR:=SSR together
        nop

ENTRY(after_f)
        ! ==============================================================
        ! Sub-test G: MULTI_HIT -- two TLB entries genuinely match one
        ! lookup. Independent multi-entry overlap (see header construction
        ! note): install VPN 0x8 (4KB), then VPN 0x9 (4KB, disjoint), then
        ! VPN 0x8 again as a 16KB superpage (mask=1, covers VPN 0x8..0xB).
        ! The third install's overlap scan evicts VPN 0x8's slot (first
        ! match found) but never reaches VPN 0x9's slot, which also overlaps
        ! the new superpage's range and so survives. ORDERING DEPENDENCY:
        ! "first match" is the lowest slot index (core/tlb.vhd's scan runs
        ! k = 0..31 and latches `dedup` on the first hit), so this relies on
        ! NRU giving VPN 0x8 a lower slot than VPN 0x9 -- true because they
        ! are installed in that order with no MMUCR.TI flush between them.
        ! Do not insert a flush between the first two installs. If this ever
        ! breaks, the sub-test fails cleanly with result 20/21 (no exception,
        ! or wrong FSR/EXPEVT) rather than passing for the wrong reason.
        ! A load from VPN 0x9
        ! then genuinely matches both the surviving VPN 0x9 entry and the
        ! new VPN 0x8 superpage. MULTI_HIT dispatches via General Illegal to
        ! VBR+0x100, NOT through _v_tlb -- reload VBR so VBR+0x100 lands on
        ! this file's own _v_gi handler. This is the LAST sub-test, so there
        ! is no need to restore the VBR+0x400 mapping afterward.
        ! ==============================================================
        mov.l   p_vbr_gi_val, r0
        .word   0x402E                  ! LDC r0, VBR (so VBR+0x100 = _v_gi)

        ! ---- The three installs are now three WALKER installs. The walker only
        ! ---- installs on a MISS, so the third one -- re-installing VPN 0x8 as a
        ! ---- superpage while it is already resident -- cannot be provoked by
        ! ---- touching VA 0x8000 again: that would HIT. ASID is what makes it
        ! ---- miss, exactly as in the migrated mmumultihit.S:
        ! ----
        ! ----   1. under ASID A, touch VA 0x8000 -> walker installs the 4 KB
        ! ----      NON-GLOBAL entry from the row hashed for (0x8000, A);
        ! ----   2. under ASID A, touch VA 0x9000 -> installs the 4 KB entry for
        ! ----      VPN 0x9, which does not overlap VPN 0x8's page;
        ! ----   3. switch to ASID B and touch VA 0x8000. The resident VPN 0x8
        ! ----      entry is non-global with asid_tag=A, so this MISSES, and the
        ! ----      walker reads the row hashed for (0x8000, B) -- a GLOBAL 16 KB
        ! ----      entry covering VPN 0x8..0xB. Its install runs the same
        ! ----      overlap-dedup scan as LDTLB did (the scan is on the shared
        ! ----      install port, core/tlb.vhd): ptel(2)='1' makes the
        ! ----      global-or-ASID predicate true for every resident entry, so it
        ! ----      evicts the FIRST overlapping slot it scans -- VPN 0x8's --
        ! ----      and never reaches VPN 0x9's, which also overlaps and survives;
        ! ----   4. switch back to ASID A and load VA 0x9000. The surviving VPN
        ! ----      0x9 entry matches on asid_tag=A, and the global superpage
        ! ----      matches because it is global. Two entries, one lookup: a
        ! ----      genuine MULTI_HIT.
        ! ----
        ! ---- The ORDERING DEPENDENCY is unchanged and still documented: "first
        ! ---- match" is the lowest slot index, so this relies on NRU giving VPN
        ! ---- 0x8 a lower slot than VPN 0x9. They are installed in that order
        ! ---- with no MMUCR.TI flush between them. Do not insert one. If it ever
        ! ---- breaks, the sub-test fails cleanly with 20/21 rather than passing
        ! ---- for the wrong reason.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on -- the touches below must translate

        mov.l   c_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR (= A)
        nop
        nop
        mov.l   p_pteh_p8, r2
        mov.l   @r2, r3                 ! step 1: install VPN 0x8, 4 KB, ASID A
        mov.l   p_pteh_p9, r2
        mov.l   @r2, r3                 ! step 2: install VPN 0x9, 4 KB, ASID A

        mov.l   c_asid_b, r0
        .word   0x407E                  ! LDC r0, ASIDR (= B)
        nop
        nop
        mov.l   p_pteh_p8, r2
        mov.l   @r2, r3                 ! step 3: MISS -> install the GLOBAL 16 KB
                                        ! superpage; dedup evicts VPN 0x8's slot
                                        ! only, VPN 0x9's survives

        mov.l   c_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR (back to A)
        nop
        nop

        mov.l   p_g_exp_fsr, r0
        mov.l   c_fsr_multihit, r1
        mov.l   r1, @r0                 ! g_exp_fsr = 0x1700
        mov.l   p_g_bad_fsr, r0
        mov     #21, r1
        mov.l   r1, @r0                 ! FSR wrong (or wrong EXPEVT) -> result 21
        mov.l   p_g_resume, r0
        mov.l   p_after_g, r1
        mov.l   r1, @r0                 ! resume -> after_g

        mov     #20, r9                 ! sentinel: no exception = result 20
        mov.l   c_va_p9, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_gi (VBR+0x100), MULTI_HIT

        bra     _fail
        nop

ENTRY(after_g)
        bra     _done
        nop

        ! ============================================================
        ! Pointer literals used by main body.
        ! ============================================================
        .align 2
p_rbclear:          .long 0xDFFFFFFF
p_mdclear:          .long 0xBFFFFFFF   ! clear SR.MD (bit 30)
p_vbr_val:          .long _vbase
p_vbr_gi_val:       .long _v_gi - 0x100
p_start_addr:       .long start
p_ptel_page0:       .long 0x000000CD   ! W|X|C|G|V, kernel-only own page. GLOBAL:
                                        ! sub-test G switches ASIDR, and a
                                        ! non-global code page would stop
                                        ! matching the moment it did. V because
                                        ! the walker rejects a V=0 row as "no
                                        ! entry". (U=0: with AT
                                        ! enabled the guard keeps executing from
                                        ! this page in supervisor mode, so U=1
                                        ! here would SMEP-fault immediately --
                                        ! see mmusmep.S/mmufault.S history)
p_ptel_ro:          .long 0x00000069   ! X|U|C|V  (W=0 -> DPROT_W)
p_ptel_nx:          .long 0x000000A9   ! W|U|C|V  (X=0 -> IPROT)
p_ptel_super:       .long 0x000000C9   ! W|X|C|V  (U=0 -> DPROT_R)
p_mmucr:            .long 0xFF000010
p_tsbbr_addr:       .long 0xFF000014
p_tsbbr_val:        .long 0x00018008   ! base=0x00018000, TSB_SIZE_LOG=8
p_tsbcfg_addr:      .long 0xFF000018
p_tsbcfg_val:       .long 0x00000061   ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:          .long 0xFF000048   ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:              .long _tsb_tab
p_tab_end:          .long _tsb_tab_end
p_tab_code:         .long _tsb_row_code
p_tab_trampb:       .long _tsb_row_trampb
p_tab_trampf:       .long _tsb_row_trampf
c_asid_a:           .long 0x00000001
c_asid_b:           .long 0x00000002
p_fsr_addr:         .long 0xFF00002C
p_g_exp_fsr:        .long _g_exp_fsr
p_g_exp_expevt:     .long _g_exp_expevt
p_g_bad_fsr:        .long _g_bad_fsr
p_g_bad_expevt:     .long _g_bad_expevt
p_g_resume:         .long _g_resume
p_after_a:          .long after_a
p_after_b:          .long after_b
p_after_c:          .long after_c
p_after_d:          .long after_d
p_after_e:          .long after_e
p_after_f:          .long after_f
p_after_g:          .long after_g
! page1-4 VAs shifted to 0x2000-0x5000 (not 0x1000-0x4000): the guard's own
! code page now covers VA 0x1000-0x1FFF (start links there, see p_start_addr
! above), so a page1 target of 0x1000 would alias the own page and never
! actually be unmapped -- see mmufault.S history for this exact bug.
c_page1_va:         .long 0x00002000
c_page2_va:         .long 0x00003000
c_page3_va:         .long 0x00004000
c_page4_va:         .long 0x00005000
        ! ---- TSB rows: (VA, ASID_TAG, PTEL), one 12-byte row each. The three
        ! ---- rows whose VA depends on a link-time label are patched at runtime
        ! ---- in the setup above; their placeholders here are 0.
        ! ---- Sub-test G's three rows are what make a genuine MULTI_HIT
        ! ---- constructible under walker-only install -- see the sub-test G
        ! ---- comment block for why ASID, not page size, is the lever.
        .balign 4
_tsb_tab:
_tsb_row_code:
        .long 0x00000000, 0x00000000, 0x00000000  ! code page (patched: VA|PTEL)
        .long 0x00003000, 0x00000000, 0x00003069  ! page 2 read-only  -> DPROT_W
        .long 0x00004000, 0x00000000, 0x000040A9  ! page 3 no-execute -> IPROT
        .long 0x00005000, 0x00000000, 0x000050C9  ! page 4 super-only -> DPROT_R
_tsb_row_trampb:
        .long 0x00000000, 0x00000000, 0x00000000  ! tramp_b (patched)
_tsb_row_trampf:
        .long 0x00000000, 0x00000000, 0x00000000  ! tramp_f (patched)
        .long 0x00008000, 0x00000001, 0x000080C9  ! G step 1: VPN 8, 4K, ASID A
        .long 0x00009000, 0x00000001, 0x000090C9  ! G step 2: VPN 9, 4K, ASID A
        .long 0x00008000, 0x00000002, 0x000081CD  ! G step 3: VPN 8, 16K, GLOBAL,
                                                  ! hashed under ASID B so that
                                                  ! step 3's miss finds it
_tsb_tab_end:

c_page2_pteh:       .long 0x00003000
c_page3_pteh:       .long 0x00004000
c_page4_pteh:       .long 0x00005000
c_fsr_dprot_w:       .long 0x00001609
c_fsr_dprot_r:       .long 0x00001518
c_fsr_dmiss_r:       .long 0x00001200
c_fsr_dmiss_w:       .long 0x00001301
c_fsr_imiss:         .long 0x00001104
c_fsr_iprot:         .long 0x0000141C
c_fsr_multihit:      .long 0x00001700
c_expevt_dprot:      .long 0x000000C0
c_expevt_dmiss_r:    .long 0x00000060
c_expevt_dmiss_w:    .long 0x00000080
c_expevt_imiss:      .long 0x00000040
c_expevt_iprot:      .long 0x000000A0
! multi-hit (sub-test G) TLB install literals: independent multi-entry
! overlap (see the construction note in this file's header and at the
! sub-test G site) -- install-time dedup only evicts the FIRST matching
! resident entry, so a superpage installed AFTER two disjoint 4KB pages
! evicts only one of them, leaving a genuine overlap for lookup to hit.
p_pteh_p8:           .long 0x00008000   ! VPN 0x8, ASID 0
p_ptel_p8_small:     .long 0x000080C9   ! PA 0x8000 | pageMask=0 (4KB) | W|C|V
p_ptel_p8_big:       .long 0x000081CD   ! PA 0x8000 | pageMask=1 (16KB, covers VPN 8..B) | W|C|G|V
                                        ! GLOBAL so its install's dedup predicate is true
                                        ! against the resident ASID-A entries
p_pteh_p9:           .long 0x00009000   ! VPN 0x9, ASID 0
p_ptel_p9_small:     .long 0x000090C9   ! PA 0x9000 | pageMask=0 (4KB) | W|C|V -- disjoint from VPN 0x8
c_va_p9:             .long 0x00009000   ! load target: VPN 0x9, inside the VPN 0x8 superpage's range
! Trampoline-page literals for sub-tests B/F (see comments at each site).
p_pagemask:          .long 0xFFFFF000
p_tramp_b_addr:      .long _user_tramp_b
p_tramp_f_addr:      .long _user_tramp_f
p_ptel_tramp:       .long 0x000000E9   ! W|X|U|C|V (user trampoline page)

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

        ! ================================================================
        ! Single handler at exactly VBR+0x400 (all six TLB-vectored faults,
        ! sub-tests A-F, land here). EXPEVT is checked against a per-sub-test
        ! global (g_exp_expevt) rather than a fixed constant, since A-F each
        ! expect a different EXPEVT code.
        ! ================================================================
        .balign 4
! ---- Vector page (VBR = _vbase) ----
! Since TLB protection faults were split off the miss vector to VBR+0x100
! (matching SH-4: misses H'400, protection H'100), a guard that only places
! code at +0x400 sends every IPROT/DPROT_R/DPROT_W into whatever happens to
! sit 0x300 bytes before its handler. The old `VBR = _v_tlb - 0x400` idiom had
! no valid +0x100 at all. Both vectors now land on the same EXPEVT-driven
! handler, so every assertion below is unchanged; only the arrival path is.
        .balign 4
_vbase:
        .org    _vbase + 0x100
_v_prot:                                ! VBR+0x100: IPROT / DPROT_R / DPROT_W
        bra     _v_tlb
        nop
        .org    _vbase + 0x400
_v_tlb:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0              ! load MMUCR addr
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1                 ! r1 = expected EXPEVT
        cmp/eq  r0, r1                  ! T if EXPEVT == expected
        bf      _h_bad_expevt
        mov.l   Hfsr_addr, r0
        mov.l   @r0, r2                 ! r2 = MMUFSR
        mov.l   Hexp_fsr, r1
        mov.l   @r1, r1                 ! r1 = expected MMUFSR
        cmp/eq  r1, r2
        bf      _h_bad_fsr
        bra     _h_resume
        nop

        .balign 4
Hmmucr:         .long 0xFF000010
Hfsr_addr:      .long 0xFF00002C
Hexp_fsr:       .long _g_exp_fsr
Hexp_expevt:    .long _g_exp_expevt

_h_resume:
        mov.l   Ph_resume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        ! Force return to supervisor (SSR.MD=1): sub-test B/F fault in user
        ! mode; without this the RTE resumes in user mode and the next
        ! sub-test's privileged access traps. MD bit = 0x40000000.
        .word   0x0132                  ! STC SSR, r1
        mov.l   Pmd_bit, r2
        or      r2, r1
        .word   0x413E                  ! LDC r1, SSR
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_fsr:
        mov.l   Ph_bad_fsr, r0
        mov.l   @r0, r9                 ! r9 = fail code (MMUFSR mismatch)
        bra     _fail
        nop

_h_bad_expevt:
        mov.l   Ph_bad_expevt, r0
        mov.l   @r0, r9                 ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

        .balign 4
Ph_resume:      .long _g_resume
Ph_bad_fsr:     .long _g_bad_fsr
Ph_bad_expevt:  .long _g_bad_expevt
Pmd_bit:        .long 0x40000000       ! SR.MD bit, set on SSR before RTE

        ! ================================================================
        ! Shared handler globals.
        ! ================================================================
        .balign 4
_g_exp_fsr:     .long 0xFFFFFFFF        ! sentinel: unset (a real sub-test always overwrites)
_g_exp_expevt:  .long 0xFFFFFFFF
_g_resume:      .long 0
_g_bad_fsr:     .long 0x5A              ! loud fail-code sentinels: distinguish an early
_g_bad_expevt:  .long 0x5B              ! fault (before any sub-test runs) from result=0

        ! ================================================================
        ! Second handler at exactly VBR+0x100 (General Illegal), used only
        ! by sub-test G after VBR is reloaded to p_vbr_gi_val. MULTI_HIT
        ! writes its own EXPEVT=0x180 via microcode (core/cpu.vhd,
        ! decode/decode_core.vhm) rather than going through the TLB-fault
        ! EXPEVT path that _v_tlb above checks, so this needs a distinct
        ! vector and a distinct (fixed, since only G uses it) EXPEVT check.
        ! A wrong EXPEVT here is folded into the same "result 21" fail code
        ! as an MMUFSR mismatch: either way, the fault that landed here
        ! was not the expected MULTI_HIT.
        ! ================================================================
        .balign 4
        .space 0x100, 0
        .balign 4
_v_gi:                                  ! = p_vbr_gi_val + 0x100
        mov.l   Gimmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Giexp_expevt, r1
        mov.l   @r1, r1                 ! r1 = 0x180 (General Illegal)
        cmp/eq  r0, r1
        bf      _gi_bad
        mov.l   Gifsr_addr, r0
        mov.l   @r0, r2                 ! r2 = MMUFSR
        mov.l   Giexp_fsr, r1
        mov.l   @r1, r1                 ! r1 = expected MMUFSR (0x1700)
        cmp/eq  r1, r2
        bf      _gi_bad
        mov.l   Giresume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_gi_bad:
        mov.l   Gibad_fsr, r0
        mov.l   @r0, r9                 ! r9 = fail code 21
        ! _fail is out of bra's +-4KB range from here (padding between
        ! _v_tlb's fault-page space and this second, VBR+0x100 handler),
        ! so jump indirectly through a literal instead.
        mov.l   Gifail_addr, r0
        jmp     @r0
        nop

        .balign 4
Gimmucr:        .long 0xFF000010
Gifsr_addr:     .long 0xFF00002C
Giexp_fsr:      .long _g_exp_fsr
Giexp_expevt:   .long c_gi_expevt
Giresume:       .long _g_resume
Gibad_fsr:      .long _g_bad_fsr
Gifail_addr:    .long _fail
        .balign 4
c_gi_expevt:    .long 0x00000180

        ! ================================================================
        ! Fault-page padding: covers pages 1-4 (unmapped DMISS/DPROT/IPROT
        ! sub-tests) and pages 8-B (sub-test G's VPN 0x8/0x9 installs and the
        ! VPN 0x8..0xB superpage), so the bus doesn't fault before the TLB exception
        ! fires and any (never-taken, since G faults) backing access stays
        ! in range. Placed AFTER _v_gi's handler and literal pool (not
        ! before, as an earlier draft had it) so _v_gi's own link address
        ! stays inside page 0's mapped range (VA 0x0000-0x0FFF) instead of
        ! being pushed out past 0xC000 where nothing maps it -- mirrors
        ! sim/tests/mmumultihit.S, where _v_gi (VA 0x3a0) is likewise well
        ! inside page 0.
        ! ================================================================
_fault_pages:
        ! Backing for the mapped pages (0x2000..0xBFFF) AND for the TSB at
        ! PA 0x18000..0x19FFF. Zero-filled, so the TSB starts empty.
        !
        ! THIS PADDING IS LOAD-BEARING, NOT COSMETIC. The cosim only backs SRAM
        ! within the loaded image extent: a PA past the end of the image is
        ! backed by nothing, and an access to it neither faults nor stores --
        ! it simply goes nowhere ("SRAM: invalid write addr" in the cosim log).
        ! The hardware walker reads the TSB by physical address, so a TSB placed
        ! past the image end reads as garbage-that-is-never-there and every walk
        ! silently misses. Any guard whose TSB (or whose P0/P2 alias readback)
        ! sits above the image must extend the image to cover it.
        .space 0x1A000, 0

        ! ================================================================
        ! User-mode trampoline pages for sub-tests B and F. Own page (page 0)
        ! is U=0/kernel-only (p_ptel_page0), so user-mode code cannot execute
        ! from it; each trampoline installs its own U=1 page (VPN computed at
        ! runtime from its own link address) and is entered via RTE from the
        ! sub-test body. Same technique as mmufault.S/mmusmep.S.
        ! ================================================================
        .balign 4096
_user_tramp_b:
        mov     #4, r9                  ! sentinel: no exception = result 4
        mov.l   tb_page4_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_tlb (VBR+0x400), DPROT_R
        mov.l   tb_fail_addr, r0        ! RED path only (fault didn't fire)
        jmp     @r0
        nop
        .balign 4
tb_page4_va:  .long 0x00005000
tb_fail_addr: .long _fail

        .balign 4096
_user_tramp_f:
        mov     #17, r9                 ! sentinel: no exception = result 17
        mov.l   tf_page3_va, r0
        jmp     @r0                     ! FAULTS -> _v_tlb (VBR+0x400), IPROT
        nop
        mov.l   tf_fail_addr, r0        ! RED path only (fault didn't fire)
        jmp     @r0
        nop
        .balign 4
tf_page3_va:  .long 0x00004000
tf_fail_addr: .long _fail

#endif  ! CONFIG_PRIV_ARCH
