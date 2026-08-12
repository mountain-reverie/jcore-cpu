! mmustale.S -- STALE (PTE bit 1) revocation guard (J4).
!
! WALKER-INSTALL VERSION (L1 pilot of "retire LDTLB"). Read this note before
! reading the test: THE LAYER UNDER TEST HAS MOVED, deliberately, because the
! old layer stops existing when LDTLB does.
!
! ---- what the LDTLB version tested -----------------------------------------
! Security hardening (security-review H-I1): LDTLB loaded PTEL[1] (STALE) into
! the TLB entry, and the LOOKUP did not consult it, so an entry software had
! marked STALE (soft-invalidate / revoked) was still matched and its old
! translation granted -- a revoked mapping stayed live. The fix added
! `entry.stale = '0'` to core/tlb.vhd's tlb_match, and this guard installed a
! STALE=1 entry with LDTLB and required the access to MISS.
!
! ---- why that construction is unbuildable under walker-only install --------
! The hardware walker REFUSES a STALE TSB entry: core/tlb_walk.vhd's st_data
! requires `bus_d(0) = '1' and bus_d(1) = '0'` (V set, STALE clear) before it
! will move to st_install, and treats anything else as "no entry in this way".
! So with the walker as the sole installer there is NO WAY to get a STALE=1
! entry into the TLB at all -- the state the old guard constructed is
! unreachable, and core/tlb.vhd's `entry.stale = '0'` match term becomes dead
! (defence-in-depth only). This is a real consequence of retiring LDTLB and is
! recorded here rather than quietly dropped.
!
! ---- what this guard tests NOW ---------------------------------------------
! Revocation itself is still a live, load-bearing property; it has simply moved
! one level out, from the TLB entry to the TSB entry. Software revokes a
! mapping by setting STALE in the TSB, and the requirement is unchanged in
! substance: after revocation the access must NOT be granted the old
! translation, it must FAULT. So:
!
!   VA 0x4000 has a perfectly good TSB entry -- correct tag_hi, correct
!   tag_lo/ASID, correct PPN and permissions -- differing from a working entry
!   ONLY in STALE. The load must still take DMISS_R (EXPEVT 0x060). If the
!   walker ignored STALE, the entry would install and the load would complete.
!
! This is WEAKER than the LDTLB version in one specific way and must not be
! oversold: it no longer covers a STALE entry that is already resident in the
! TLB. It cannot, because that state is now unreachable. It is STRONGER in
! another: the old version could pass on any fault at all, whereas this one
! pins the fault to the STALE bit with a positive control and with the walker's
! own counters.
!
! ---- non-vacuity ----------------------------------------------------------
! "The load faulted" is a weak observation on its own: a mis-hashed TSB slot, a
! wrong tag, a missing V bit -- every setup error also produces DMISS_R. Three
! things pin the fault to STALE and nothing else:
!
!  1. POSITIVE CONTROL. VA 0x5000 carries a TSB entry built by the same fill
!     loop, in the same table, with the same ASID and permissions and the same
!     runtime-computed slot address -- differing ONLY in STALE=0. It must
!     resolve WITHOUT faulting and return its sentinel. So the fill path, the
!     hash, the tag format and the permissions are all proven good before the
!     STALE case runs.
!  2. ARMING FLAG. The handler is the only PASS path, so a fault taken anywhere
!     BEFORE the STALE load would report a spurious pass. `_g_armed` is set
!     immediately before that load and checked by the handler (result 4).
!  3. WALKER COUNTERS (0xFF000054, [31:16]=cnt_walks [15:0]=cnt_hits), sampled
!     into the UNBANKED registers r10/r11 just before the armed load and
!     checked in the handler. cnt_walks must have advanced (the walker really
!     read the TSB set -- result 5) while cnt_hits must NOT have (it read the
!     entry and refused it -- result 6). Without this pair the guard would pass
!     just as happily if the walker had never looked at the entry at all.
!
! ---- layout ---------------------------------------------------------------
! Code page: VA 0x0000..0x3FFF, GLOBAL 16 KB identity (page_mask=1), W|X|C, U=0
! (SMEP: a kernel fetch of a U=1 page is a protection fault). Global so that
! nothing re-walks code and perturbs the counters. The walker's tag compare is
! exact on the 4 KB VPN even for a superpage entry, so all four covered VPNs
! get a table row; whichever is touched first installs, the rest then hit.
!
! TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x 32 bytes), HASH_SHIFT=6,
! HASH_MODE=1. Slot addresses are asked of the P4 TSB-slot helper
! (0xFF000048 -- the single tsb_ptr() implementation the walker and TSBPTR also
! use) rather than hand-computed.
!
! PTEL bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G bit1=STALE
! bit0=V. A TSB entry MUST set V; the walker rejects V=0 as "no entry".
!
! VBR = _v_load - 0x400 so the DMISS_R vector (VBR+0x400) hits _v_load.
!
! Result codes:
!   0  pass -- the STALE TSB entry was refused and the load took DMISS_R
!   1  the STALE=1 entry was honoured: the load completed instead of faulting
!   2  positive control (VA 0x5000, identical but STALE=0) returned wrong data
!   3  the fault was taken but EXPEVT != DMISS_R (0x060) -- wrong fault kind
!   4  a fault was taken BEFORE the STALE load was armed -- a setup error
!      (missing/mis-hashed TSB entry), not the property under test
!   5  the walker never walked on the STALE access (cnt_walks did not advance)
!   6  the walker COUNTED A HIT on the STALE entry (cnt_hits advanced) -- it
!      accepted a revoked entry from the TSB and something else caused the fault
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS and clamps r9==0 to 0x7F, so
! a fail can never be mistaken for the harness PASS token.
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

        ! ---- VBR = _v_load - 0x400 (so VBR+0x400 = _v_load). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed the positive control's page via P1 (untranslated). ----
        mov.l   p_sentinel_c, r3
        mov.l   p_p1_5000, r2
        mov.l   r3, @r2

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the TSB from the (VA, ASID, PTEL) table; the set address
        ! ---- for each row comes from the P4 helper under that row's ASID, so
        ! ---- no hash is hand-computed. AT is off: plain P0 stores. ----
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

        ! ---- Literal pool 1 (setup). SH-2 `mov.l @(disp,PC)` is FORWARD-only
        ! ---- and reaches +1020 bytes, hence two pools. ----
        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x400
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:          .long _tsb_tab
p_tab_end:      .long _tsb_tab_end
p_sentinel_c:   .long 0xC0FFEE00        ! at PA 0x5000 (positive control)
p_p1_5000:      .long 0x80005000

        .balign 4
_tsb_tab:
        .long 0x00000000, 0x00000000, 0x000001CD  ! code 16K global W|X|C|V
        .long 0x00001000, 0x00000000, 0x000001CD
        .long 0x00002000, 0x00000000, 0x000001CD
        .long 0x00003000, 0x00000000, 0x000001CD
        ! The two entries under test. IDENTICAL but for bit 1 (STALE).
        .long 0x00004000, 0x00000000, 0x000040CB  ! PA 0x4000 W|C|STALE|V
        .long 0x00005000, 0x00000000, 0x000050C9  ! PA 0x5000 W|C|V  (control)
_tsb_tab_end:

ENTRY(_run)
        ! ---- ASIDR = 0, then enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- POSITIVE CONTROL: VA 0x5000, same table, same fill loop, same
        ! ---- ASID, same permissions, STALE=0. Must resolve via the walker
        ! ---- with no fault and return the seeded sentinel. Any fault here is
        ! ---- a setup error and lands in the handler UNARMED -> result 4.
        mov.l   c_va5, r2
        mov.l   @r2, r8
        mov.l   q_sentinel_c, r0
        cmp/eq  r8, r0
        bt      1f
        mov     #2, r9
        bra     _fail
        nop
1:
        ! ---- Arm the handler and snapshot the walker counters into the
        ! ---- UNBANKED registers r10/r11 (the exception entry sets SR.RB=1,
        ! ---- which would swap r0..r7 out from under the handler).
        mov.l   q_armed, r0
        mov     #1, r1
        mov.l   r1, @r0
        mov.l   q_walkcnt, r4
        mov.l   c_va4, r2
        mov.l   @r4, r10
        mov     r10, r11
        shlr16  r10                     ! r10 = cnt_walks before
        extu.w  r11, r11                ! r11 = cnt_hits before

        ! ---- THE PROPERTY: a STALE TSB entry must not be installed, so this
        ! ---- load must FAULT -> _v_load (VBR+0x400), DMISS_R.
        mov.l   @r2, r3

        ! ---- Reached only if the STALE entry was honoured. ----
        mov     #1, r9
        bra     _fail
        nop

        ! ---- Literal pool 2 (test body). ----
        .align 2
q_mmucr:        .long 0xFF000010
q_walkcnt:      .long 0xFF000054        ! [31:16]=cnt_walks [15:0]=cnt_hits
q_armed:        .long _g_armed
q_sentinel_c:   .long 0xC0FFEE00
c_va4:          .long 0x00004000
c_va5:          .long 0x00005000

#endif  ! CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: keep the fail code loud
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ---- DMISS_R handler at VBR+0x400 ----
        ! Pad so _v_load lands at >= 0x420.
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)

        ! ---- Was this the armed access? An unarmed fault is a setup error.
        mov.l   Harmed, r0
        mov.l   @r0, r0
        tst     r0, r0
        bf      1f
        mov     #4, r9
        bra     _fail
        nop
1:
        ! ---- Right fault kind? ----
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hdmiss_r, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #3, r9
        bra     _fail
        nop
1:
        ! ---- The walker must have LOOKED (cnt_walks advanced) and REFUSED
        ! ---- (cnt_hits did not). r10/r11 are unbanked, so they carry the
        ! ---- pre-access snapshot across the RB=1 exception entry.
        mov.l   Hwalkcnt, r0
        mov.l   @r0, r1
        mov     r1, r2
        shlr16  r1                      ! r1 = cnt_walks now
        extu.w  r2, r2                  ! r2 = cnt_hits now
        cmp/eq  r10, r1
        bf      1f
        mov     #5, r9                  ! no walk happened at all
        bra     _fail
        nop
1:      cmp/eq  r11, r2
        bt      1f
        mov     #6, r9                  ! the walker counted the STALE entry as a hit
        bra     _fail
        nop
1:
        ! ---- The STALE entry was refused and the access faulted as required.
        mov.l   Hresult, r0
        mov.l   Hresult_pass, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Harmed:         .long _g_armed
Hdmiss_r:       .long 0x00000060        ! EXPEVT for DMISS_R
Hwalkcnt:       .long 0xFF000054
Hresult:        .long TEST_RESULT_ADDRESS
Hresult_pass:   .long   TEST_PASS_MAGIC

        .balign 4
_g_armed:       .long 0

        ! ---- Backing store: the mapped data pages (PA 0x4000, 0x5000) and the
        ! ---- TSB at PA 0x14000..0x15FFF. Zero-filled image, so the TSB starts
        ! ---- empty and the fill loop is the only thing that populates it. ----
_fault_pages:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
