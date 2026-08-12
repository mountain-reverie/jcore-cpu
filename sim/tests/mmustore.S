! mmustore.S -- minimal RED guard for the store-side TLB-miss protection hole.
!
! Proven defect (.superpowers/sdd): a D-side STORE that misses the TLB raises
! NO exception -- the store silently completes to the bus, bypassing
! W^X/CoW/dirty-bit/page-fault-on-write. The IDENTICAL access as a LOAD faults
! correctly (covered by mmurte.S). This test isolates the STORE case.
!
! Flow:
!   - map page 0 identity (W|X|U|C), enable AT
!   - STORE to VA 0x1000 (page 1, unmapped) -> must raise DMISS_W (EXPEVT 0x080),
!     vector VBR+0x400
!   - handler (the ONLY pass path): check the arming flag and EXPEVT, then
!     disable AT, write "Test Passed", spin
!   - if the store silently completes (the defect): main path spins WITHOUT
!     writing any result -> run times out -> RED.
!
! VBR = _v_store - 0x400 so the DMISS_W vector (VBR+0x400) hits _v_store.

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

        ! ---- VBR = _v_store - 0x400 (so VBR+0x400 = _v_store). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB: base 0x00004000, TSB_SIZE_LOG=6 (64 sets x
        ! ---- 32 bytes = 0x4000..0x47FF), HASH_SHIFT=6, HASH_MODE=1. The image
        ! ---- is zero-filled, so the TSB starts empty and the fill below is the
        ! ---- only thing that populates it. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Map page 0 (VA 0x0000-0x0FFF) identity, W|X|C|G|V, U=0 (SMEP).
        ! ---- This used to be an LDTLB; it is now a TSB entry the walker
        ! ---- installs on demand -- I-side on the first fetch after AT goes
        ! ---- on, D-side on the first literal load. GLOBAL, so no ASID change
        ! ---- can perturb it. The set address is asked of the P4 slot helper
        ! ---- (0xFF000048); nothing here hand-computes the hash. ----
        mov.l   p_tsbslot_reg, r12
        mov     #0, r6                  ! VA 0x00000000
        mov     #0, r7                  ! ASID 0
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_page0, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        mov.l   r8, @(8, r10)           ! way 0 data = PTEL
        mov.l   r7, @(4, r10)           ! way 0 tag_lo = ASID_TAG
        mov.l   r6, @(0, r10)           ! way 0 tag_hi = VPN (commit point)

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- ARM the handler. The handler is the ONLY pass path, so any
        ! ---- fault taken BEFORE the access under test would report a spurious
        ! ---- pass. That is not hypothetical here: the code page is now
        ! ---- installed by the walker, so a broken code-page TSB entry faults
        ! ---- on the very first fetch under AT and lands in the handler --
        ! ---- MEASURED to false-pass without this flag. The flag is set with AT
        ! ---- already on, from the code page, immediately before the store. ----
        mov.l   c_armed_p, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Take a DMISS_W: STORE to VA 0x1000 (page 1, unmapped). ----
        mov.l   c_page1_va, r2
        mov     #0x55, r3
        mov.l   r3, @r2                 ! FAULTS -> _v_store (VBR+0x400), DMISS_W

        ! If the store silently completes (the defect), we reach here. Spin
        ! WITHOUT writing any result so RED = run times out (no "Test Passed").
_silent_spin:
        bra     _silent_spin
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_store - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000CD        ! identity PPN 0 | W|X|C|G|V, U=0
c_page1_va:     .long 0x00001000
c_armed_p:      .long _g_armed
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00004006        ! base=0x00004000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)

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

        ! ---- DMISS_W handler at VBR+0x400 ----
        ! Pad so _v_store lands at >= 0x440.
        .balign 4
        .space 0x640, 0
        .balign 4
_v_store:                               ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)

        ! ---- Was this the armed access? An unarmed fault is a setup error
        ! ---- (typically the code page failing to walk in) -> result 4.
        mov.l   Harmed, r0
        mov.l   @r0, r0
        tst     r0, r0
        bf      1f
        mov     #4, r9
        bra     _fail
        nop
1:
        ! ---- Right fault kind? DMISS_W is EXPEVT 0x080. A load-side or
        ! ---- protection fault here would not be the hole under test. ----
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hdmiss_w, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #3, r9
        bra     _fail
        nop
1:
        ! The store faulted as required: write PASS (result 0) directly. AT is
        ! now off so this P-region store is reliable. This is the ONLY path that
        ! writes a result -> reaching it == GREEN.
        mov.l   Hresult, r0
        mov.l   Hresult_pass, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Harmed:         .long _g_armed
Hdmiss_w:       .long 0x00000080        ! EXPEVT for DMISS_W
Hresult:        .long TEST_RESULT_ADDRESS
Hresult_pass:        .long   TEST_PASS_MAGIC

        ! ---- Backing store: the fault page at VA 0x1000 and the TSB at
        ! ---- PA 0x4000..0x47FF. Zero-filled. ----
        .balign 4
_g_armed:       .long 0

_fault_pages:
        .space 0x5000, 0

#endif  ! CONFIG_PRIV_ARCH
