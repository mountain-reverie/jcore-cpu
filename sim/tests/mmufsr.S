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
!   pages 8/9 (multi-hit, sub-test G): master's 7f9b51f made LDTLB install-time
!     dedup range-overlap-aware (not just exact-VPN), so mmumultihit.S's old
!     large-page/small-page two-install construction no longer multi-hits --
!     the second LDTLB's install-time overlap scan now evicts the first
!     mapping in place (see sim/tests/mmumultihit.S header). To still reach a
!     genuine multi-hit (independent multi-entry overlap, which install-time
!     dedup cannot reach because it only evicts the FIRST matching resident
!     entry it finds -- core/tlb.vhd's LDTLB scan), sub-test G installs THREE
!     entries: VPN 0x8 (4KB, PA 0x8000), VPN 0x9 (4KB, PA 0x9000, does not
!     overlap VPN 0x8's page), then VPN 0x8 again with pageMask=1 (16KB,
!     covers VPN 0x8..0xB, PA 0x8000). The third install's overlap scan finds
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
!   LDC r0,ASIDR=0x407E  LDTLB=0x0038
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

        ! ---- Map the guard's own code page: identity, W+X+C = 0xC8 (U=0). ----
        ! VPN is computed at RUNTIME from &start rather than hardcoded to 0,
        ! since this test image links start at VA 0x1000, not 0x0000 (the
        ! .vect header occupies the page before it) -- see mmufault.S history.
        mov.l   p_start_addr, r0
        mov.l   p_pagemask, r1
        and     r1, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN = start's page, ASID=0)
        mov.l   p_start_addr, r0
        and     r1, r0
        mov.l   p_ptel_page0, r2
        or      r2, r0
        .word   0x406E                  ! LDC r0, PTEL = (start & pagemask) | W|X|C
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map page 2 (VA 0x2000): read-only, X|U|C = 0x68 (W=0). ----
        mov.l   c_page2_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=2, ASID=0)
        mov.l   p_ptel_ro, r0
        .word   0x406E                  ! LDC r0, PTEL = 0x68
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map page 4 (VA 0x4000): supervisor-only, W|X|C = 0xC8 (U=0). ----
        mov.l   c_page4_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=4, ASID=0)
        mov.l   p_ptel_super, r0
        .word   0x406E                  ! LDC r0, PTEL = 0xC8
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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
        mov.l   p_tramp_b_addr, r0
        mov.l   p_pagemask, r1
        and     r1, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN = tramp_b's page)
        mov.l   p_tramp_b_addr, r0
        and     r1, r0
        mov.l   p_ptel_tramp, r2
        or      r2, r0
        .word   0x406E                  ! LDC r0, PTEL = (tramp_b & mask) | W|X|U|C
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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
        mov.l   c_page3_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=3, ASID=0)
        mov.l   p_ptel_nx, r0
        .word   0x406E                  ! LDC r0, PTEL = 0xA8
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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
        mov.l   p_tramp_f_addr, r0
        mov.l   p_pagemask, r1
        and     r1, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN = tramp_f's page)
        mov.l   p_tramp_f_addr, r0
        and     r1, r0
        mov.l   p_ptel_tramp, r2
        or      r2, r0
        .word   0x406E                  ! LDC r0, PTEL = (tramp_f & mask) | W|X|U|C
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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

        mov.l   p_pteh_p8, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=0x8, ASID=0)
        mov.l   p_ptel_p8_small, r0     ! PA 0x8000 | pageMask=0 (4KB) | W|C
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        mov.l   p_pteh_p9, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=0x9, ASID=0)
        mov.l   p_ptel_p9_small, r0     ! PA 0x9000 | pageMask=0 (4KB) | W|C
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        mov.l   p_pteh_p8, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=0x8, ASID=0)
        mov.l   p_ptel_p8_big, r0       ! PA 0x8000 | pageMask=1 (16KB, covers
        .word   0x406E                  ! LDC r0, PTEL              ! VPN 8..B) | W|C -- evicts
        mov     #0, r0                                              ! VPN 0x8's slot in place,
        .word   0x407E                  ! LDC r0, ASIDR             ! VPN 0x9's slot survives
        .word   0x0038                  ! LDTLB

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT

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
p_vbr_val:          .long _v_tlb - 0x400
p_vbr_gi_val:       .long _v_gi - 0x100
p_start_addr:       .long start
p_ptel_page0:       .long 0x000000C8   ! W|X|C, kernel-only own page (U=0: with AT
                                        ! enabled the guard keeps executing from
                                        ! this page in supervisor mode, so U=1
                                        ! here would SMEP-fault immediately --
                                        ! see mmusmep.S/mmufault.S history)
p_ptel_ro:          .long 0x00000068   ! X|U|C  (W=0 -> DPROT_W)
p_ptel_nx:          .long 0x000000A8   ! W|U|C  (X=0 -> IPROT)
p_ptel_super:       .long 0x000000C8   ! W|X|C  (U=0 -> DPROT_R)
p_mmucr:            .long 0xFF000010
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
p_ptel_p8_small:     .long 0x000080C8   ! PA 0x8000 | pageMask=0 (4KB) | W|C
p_ptel_p8_big:       .long 0x000081C8   ! PA 0x8000 | pageMask=1 (16KB, covers VPN 8..B) | W|C
p_pteh_p9:           .long 0x00009000   ! VPN 0x9, ASID 0
p_ptel_p9_small:     .long 0x000090C8   ! PA 0x9000 | pageMask=0 (4KB) | W|C -- disjoint from VPN 0x8
c_va_p9:             .long 0x00009000   ! load target: VPN 0x9, inside the VPN 0x8 superpage's range
! Trampoline-page literals for sub-tests B/F (see comments at each site).
p_pagemask:          .long 0xFFFFF000
p_tramp_b_addr:      .long _user_tramp_b
p_tramp_f_addr:      .long _user_tramp_f
p_ptel_tramp:        .long 0x000000E8   ! W|X|U|C, trampoline pages

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
        .space 0xC000, 0

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
