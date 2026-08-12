! mmuidslot.S -- I-side TLB fault (IMISS) in a branch delay slot: does the
! restart land on the BRANCH or elsewhere? (J4 + PRIV_ARCH). Companion to
! mmudslot.S (the data-side case). A POSITIVE guard: it asserts the restart lands
! on the branch and the delay slot re-executes. It has passed since BEFORE
! deferred I-fetch fault delivery landed -- this simple, non-interleaved case
! happened to read delay_slot='1' at fault time, so the header text below was
! stale. The m8_idslot_* sweeps are the ones that were actually RED.
!
! HISTORY. Measured 2026-07-06, this guard documented a BUG: the delay-slot fetch
! at VA 0x1000 IMISSed and the handler read SPC = 0x100A = (branch target
! 0x100C) - 2, i.e. SPC = live PC-2 where the live fetch PC had ALREADY been
! redirected to the branch TARGET by the time the delay-slot fetch missed, so the
! restart landed PAST the branch. Root cause (2026-08-06): the delay-slot fetch
! faults BEFORE its branch decodes, so NO delay-slot indicator is valid at fault
! time. Fixed by deferred / fault-on-use delivery -- the fault rides with the
! fetched instruction and is raised, with its restart PC derived from that
! instruction's own if_pc, at its dispatch boundary, where delay_slot IS
! meaningful. See if_fault in core/components_pkg.vhd. Correct behaviour, now
! asserted: restart at the branch (0x0FFE), like SLOT_ILLEGAL.
!
! HARNESS REQUIREMENTS (learned the hard way):
!  * MUST run with the J4 overlay decoder active (via sim/mmu_sim.sh, or a manual
!    `make -C decode generate-j4`). A base-decoder run makes LDTLB/PTEH no-ops ->
!    AT never enables -> no fault.
!  * MUST keep SR.RB=0: the I-side TLB fault path is gated on dp_sr.rb='0'
!    (core/cpu.vhd). With RB=1 (reset default) I-fetches bypass the TLB.
!  * Branch DIRECTLY to the page-end branch (no nop sled): a sled lets the
!    icache/prefetcher pull page-1 lines in early and mask the miss.
!  * Progress markers are written to the PIO/LED port 0xABCD0000 (P2, prints
!    "LED: WRITE 0xNN"): 0x11=AT on, 0x33=handler entered, then SPC[7:0],SPC[15:8],
!    0x4C=idl_target (correct), 0x5D=fell through (bug).
!
! Layout (absolute VAs via .org in the VMA-0 image, like mmuicolor.S):
!   Page 0 (0x0000-0x0FFF): identity-mapped code/handler/literals.
!   Page 1 (0x1000-0x1FFF): UNMAPPED; the delay-slot fetch at 0x1000 -> IMISS.
!   The delayed branch sits at VA 0x0FFE (last halfword of page 0); its delay
!   slot is fetched at 0x1000. The handler installs page 1 and RTEs to SPC.
!
! J4 overlay opcodes:
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E

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

        ! Stay in .vect (linker VMA 0) so .org below places code at ABSOLUTE VAs.
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0. REQUIRED: the I-side TLB fault path is gated on
        !      SR.RB='0' (core/cpu.vhd i_at_translated consumer). With RB=1 (reset
        !      default) I-fetches bypass the TLB and never IMISS. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_imiss - 0x400 (so VBR+0x400 = _v_imiss). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB: base 0x00004000, TSB_SIZE_LOG=6 (64 sets x
        ! ---- 32 bytes = 0x4000..0x47FF), HASH_SHIFT=6, HASH_MODE=1. Clear of
        ! ---- page 0 and the fault page at 0x1000. Zero-filled image, so the
        ! ---- fill below is the only thing that populates it. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Map page 0 (VA 0x0000-0x0FFF) identity, W|X|C|G|V, U=0 (SMEP).
        ! ---- Was an LDTLB; now a TSB row the walker pulls in on demand,
        ! ---- I-side on the first fetch after AT goes on and D-side on the
        ! ---- first literal load. GLOBAL. Set address from the P4 slot helper
        ! ---- (0xFF000048); nothing hand-computes the hash. ----
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
        tsb_fill r10, r6, r7, r8

        ! ---- Page 1 (VA 0x1000-0x1FFF) is left UNMAPPED: the delay-slot fetch
        !      at 0x1000 misses -> IMISS. (X=0 no-execute does NOT fault in
        !      supervisor mode in this design, so IPROT is not usable here.) The
        !      handler installs page 1 and RTEs. ----

        ! ---- r14 = PIO/LED base (0xABCD0000, P2 fixed-translate) for progress
        !      markers; each 'mov.b r13,@r14' prints "LED: WRITE 0xNN". ----
        mov.l   p_pio, r14

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov     #0x11, r13              ! marker A: AT enabled
        mov.b   r13, @r14

        mov     #1, r9                  ! sentinel: no-exception = result 1
        mov     #0xAA, r3               ! sentinel: delay slot must overwrite r3 with 0x55
        ! Branch DIRECTLY to the page-end branch (no nop sled) so page 1 stays
        ! cold and the delay-slot fetch at 0x1000 genuinely misses -> IMISS.
        bra     critical
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_imiss - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000CD        ! identity PPN 0 | W|X|C|G|V, U=0
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00004006        ! base=0x00004000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_pteh_page1:   .long 0x00001000        ! VPN = 1
p_ptel_nx:      .long 0x000000A8        ! W|U|C  (X=0 -> IPROT on fetch)
p_pio:          .long 0xABCD0000        ! PIO/LED marker port
p_critical:     .long critical

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
p_test_result:  .long TEST_RESULT_ADDRESS
p_test_result_pass:  .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ================================================================
        ! IMISS handler at VBR+0x400 = _v_imiss (on page 0). Installs a
        ! full-access mapping for page 1 and RTEs to the hardware SPC.
        ! ================================================================
        .balign 4
_v_imiss:                               ! = VBR + 0x400
        mov     #0x33, r13              ! marker B: I-side fault handler entered
        mov.b   r13, @r14
        .word   0x0042                  ! STC SPC, r0  (r0 = restart PC)
        mov     r0, r13
        mov.b   r13, @r14               ! emit SPC[7:0]: branch=0xFE, dslot=0x00
        .word   0x4019                  ! shlr8 r0
        mov     r0, r13
        mov.b   r13, @r14               ! emit SPC[15:8]: 0x10 => 0x10xx, 0x0F => 0x0Fxx
        ! The handler no longer ends in an LDTLB. It writes page 1's TSB ROW;
        ! the restarted FETCH re-walks, hits that row, and the walker installs
        ! it into the ITLB (by side -- this is an I-side miss). The fault train
        ! is unchanged: one fault for page 1's first touch. AT is still ON in
        ! here, so the TSB write goes through the P1 alias (0x8xxxxxxx), which
        ! bypasses the MMU; a P0 store would itself fault on the unmapped TSB.
        mov.l   Hpteh1, r1              ! r1 = VA 0x00001000 (page 1 base)
        mov.l   Hslot, r2
        mov.l   r1, @r2                 ! ask the P4 helper for this VA's set
        mov.l   @r2, r2
        mov.l   Hp1, r0
        or      r0, r2                  ! P1 alias -- untranslated
        mov.l   Hptel1, r3
        mov     #0, r0                  ! ASID_TAG = 0
        tsb_fill r2, r1, r0, r3
        rte                             ! PC <- SPC (hardware value)
        nop

        .balign 4
Hpteh1:         .long 0x00001000        ! VPN = 1
Hptel1:         .long 0x000010C9        ! PA 0x1000 (identity) | W|X|C|V (kernel-fetched delay slot, SMEP)
Hslot:          .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
Hp1:            .long 0x80000000        ! P1 alias -- TSB writes bypass the MMU

        ! CORRECT landing: the branch target, on PAGE 0 (always mapped). Reached
        ! only if the branch is (re-)taken after the delay-slot fault is serviced.
        .balign 4
idl_target:
        mov     #0x4C, r13              ! marker C: branch taken (CORRECT)
        mov.b   r13, @r14
        ! Verify the delay slot actually executed: r3 must be 0x55 (set by the
        ! delay slot), not the 0xAA sentinel. If r3==0xAA the delay slot was
        ! SKIPPED on restart even though the branch was taken -> result 4.
        mov     #0x55, r0
        cmp/eq  r0, r3
        bf      _idslot_skipped
        mov     #0, r9
        bra     _done
        nop
_idslot_skipped:
        mov     #4, r9
        bra     _fail
        nop

        ! ================================================================
        ! Critical page-straddling region. The branch lands at VA 0x0FFE so
        ! its delay slot is fetched at VA 0x1000 (page 1, unmapped -> IMISS).
        ! ================================================================
        ! Nop sled on page 0: entered by branch, then falls through to the
        ! page-end branch at 0x0FFE.
        .org 0x0400
sled:
        mov     #0x5E, r13              ! marker E: reached sled (low page-0 addr)
        mov.b   r13, @r14
        .rept (0x0FFE-0x0404)/2
        nop
        .endr
critical:                               ! = VA 0x0FFE (last halfword of page 0)
        bra     idl_target              ! target on PAGE 0 (mapped); only the
                                        ! delay slot below (0x1000) faults.
        ! ---- VA 0x1000 (page 1, UNMAPPED): the delay slot instruction. Its
        !      fetch IMISSes. Only this fetch faults (target is on page 0). ----
        mov     #0x55, r3               ! delay slot (harmless)
        ! ---- VA 0x1002: fall-through (BUGGY landing: branch was skipped) ----
        mov     #0x5D, r13              ! marker D: fell through branch (BUG)
        mov.b   r13, @r14
        mov     #2, r9
        bra     _fail
        nop

        ! Ensure the image extends well past page 1 so the bus backs the
        ! page-1 fetches before the TLB exception fires.
        .org 0x1800

#endif  ! CONFIG_PRIV_ARCH
