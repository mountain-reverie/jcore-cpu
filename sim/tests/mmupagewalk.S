! mmupagewalk.S -- realistic D-store TLB-miss handler installing a 16 KB page.
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). Same subject, same assertions:
! a miss handler makes a 16 KB mapping appear, the faulting store is resumed,
! and the write lands in the SUB-page it addressed (PA 0x11000) and NOT in the
! superpage base (PA 0x10000). What changes is the handler's install: instead
! of LDTLB.RN it writes a TSB ROW and returns with a plain RTE, letting the
! hardware walker install on the retried access. That is now the only install
! path a miss handler can have, so this guard is the realistic end-to-end
! shape of one.
!
! SUPERPAGE KEYING. The walker's TSB tag compare is exact on the 4 KB VPN even
! for a superpage row, so the handler keys the row on the FAULTING VPN (0x11),
! not on the superpage base (0x10) -- keying it on the base would leave VA
! 0x11000 unfound and the handler would loop forever. The INSTALLED entry still
! covers VA 0x10000-0x13FFF, because pm=1 masks VPN[13:12] in the TLB compare,
! and its PPN base is 0x10000. That is what makes fail 2 meaningful: if the
! hardware took the PA from the row's PPN base instead of splicing the 16 KB
! page offset out of the VA, the sentinel would land at PA 0x10000.
!
! Verdict: SAME strength. Both assertions are unchanged, and the resumed store
! now additionally proves the handler-writes-TSB / RTE / walker-installs
! sequence works end to end.
!
! Flow:
!   1. Clear SR.RB=0. Publish TSB rows for the identity code pages.
!      Seed PA 0x10000 = 0, PA 0x11000 = 0 via P2 alias (AT off).
!      Set VBR so VBR+0x400 = _v_store (placed after .space 0x380 pad so
!      VBR = _v_store - 0x400 is a positive address).
!   2. Enable AT (no mapping for VA 0x11000).
!      Store sentinel to VA 0x11000 -> DMISS_W -> _v_store.
!   3. Handler (bank-1 scratch, SR.BL=1):
!      Take the faulting VA from TEA (0xFF00000C) -- a real handler cannot
!      assume it. Ask the P4 slot helper (0xFF000048) for that VA's TSB set.
!      Write the row THROUGH THE P1 ALIAS: AT is on and the TSB itself is
!      unmapped, so a P0 store from the handler would fault in the handler.
!      PTEL = 0x000101E9 (PA 0x10000, pm=1 = 16 KB, W|X|U|C|V).
!      Plain RTE: the store re-executes, misses again, and THIS time the
!      walker finds the row and installs it.
!   4. Drain write buffer; disable AT.
!      P2-read PA 0x11000 (expect sentinel; fail 1).
!      P2-read PA 0x10000 (expect 0; fail 2).
!
! J4 overlay opcodes:
!   LDC r0,ASIDR = 0x407E   LDC r0,VBR = 0x402E

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
        ! ---- Ensure RB=0 (keep MD=1) so handler entry causes bank switch. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- Configure the TSB (base 0x00014000, TSB_SIZE_LOG=8 -> 256 sets
        ! ---- x 32 bytes; HASH_SHIFT=6, HASH_MODE=1) and publish the identity
        ! ---- code rows. AT is off here, so these are plain P0 stores.
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR  (ASID 0 throughout)
        nop
        nop

        mov.l   p_tsbslot, r12
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
        mov.l   @r14+, r8               ! PTEL
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- Seed PA 0x10000 = 0, PA 0x11000 = 0 via P2 alias (AT off) ----
        mov     #0, r1
        mov.l   p_p2_base, r2   ! 0xA0010000  (P2 alias of PA 0x10000)
        mov.l   r1, @r2
        mov.l   p_p2_sub,  r3   ! 0xA0011000  (P2 alias of PA 0x11000)
        mov.l   r1, @r3

        ! ---- VBR = _v_store - 0x400  (so VBR+0x400 = _v_store within page 0) ----
        mov.l   k_vbr, r0
        .word   0x402E          ! LDC r0, VBR

        ! ---- Enable AT (no mapping for VA 0x11000) ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Store sentinel to VA 0x11000 -> DMISS_W -> _v_store -> LDTLB.RN ----
        mov.l   p_sentinel, r5  ! 0x5E91A16C
        mov.l   p_va_sub, r6    ! 0x00011000
        mov.l   r5, @r6         ! fires DMISS_W; LDTLB.RN re-executes this store

        ! ---- (execution resumes here after LDTLB.RN RTE) ----
        ! Drain write buffer
        mov     #20, r0
1:      dt      r0
        bf      1b

        ! ---- Disable AT ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Verify PA 0x11000 == sentinel (store reached the physical page) ----
        mov.l   @r3, r8         ! r3 = 0xA0011000
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9          ! fail 1: sub-page not written to PA 0x11000
        bf      _fail

        ! ---- Verify PA 0x10000 == 0 (16 KB base-page not touched) ----
        mov.l   @r2, r10        ! r2 = 0xA0010000
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9          ! fail 2: PA 0x10000 wrongly written
        bf      _fail

        bra     _done
        nop

        .align 2
p_rbclear:   .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00014008  ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061  ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048  ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end
p_p2_base:   .long 0xA0010000   ! P2 alias of PA 0x10000
p_p2_sub:    .long 0xA0011000   ! P2 alias of PA 0x11000
k_vbr:       .long _v_store - 0x400
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A16C
p_va_sub:    .long 0x00011000

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        ! Identity code+handler pages, 16 KB GLOBAL, W|X|C, U CLEARED -- a
        ! kernel fetch of a U=1 page is an SMEP protection fault. The walker's
        ! tag compare is exact on the 4 KB VPN, so all four covered VPNs get a
        ! row; whichever is fetched first installs and the rest then hit.
        .long 0x00000000, 0x00000000, 0x000001CD
        .long 0x00001000, 0x00000000, 0x000001CD
        .long 0x00002000, 0x00000000, 0x000001CD
        .long 0x00003000, 0x00000000, 0x000001CD
_tsb_tab_end:
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
        ! ===================== DMISS_W handler at VBR+0x400 =====================
        ! Pad so _v_store lands past 0x440 from binary start, keeping VBR
        ! = _v_store - 0x400 as a positive address (avoiding 32-bit wrap, which
        ! is legal but mmustore.S style is simpler to reason about).
        ! _v_store must remain within page 0 (VA < 0x1000) for I-fetch to work
        ! with AT=1.  With ~0x1A0 bytes before this #if, padding 0x2C0 bytes
        ! puts _v_store near 0x460, well within page 0.
        .space 0x2C0, 0
        .balign 4

        ! On exception entry SR.RB=1: r0-r7 are bank-1 scratch, no save needed.
_v_store:
        ! Take the faulting VA from TEA -- a real handler cannot assume it.
        mov.l   Htea, r0
        mov.l   @r0, r1                 ! r1 = faulting VA (0x00011000)
        mov.l   Hvpnmask, r2
        and     r2, r1                  ! r1 = 4 KB VPN key for the row

        ! Ask the P4 helper for this VA's TSB set under the current ASIDR.
        mov.l   Hslot, r0
        mov.l   r1, @r0
        mov.l   @r0, r3                 ! r3 = 32-byte-aligned SET address (PA)

        ! Address the set THROUGH P1: AT is on and the TSB is unmapped, so a P0
        ! store from here would fault inside the handler.
        mov.l   Hp1, r0
        or      r0, r3

        ! Write the row. Data first, tag_lo second, tag_hi LAST -- tag_hi is the
        ! commit point because the walker compares it first, so a walker landing
        ! mid-sequence must never see a matching tag over a half-written row.
        mov.l   Hptel, r4               ! PA 0x10000 | pm=1 (16 KB) | W|X|U|C|V
        mov     #0, r5                  ! ASID_TAG = 0
        mov.l   r4, @(8, r3)
        mov.l   r5, @(4, r3)
        mov.l   r1, @(0, r3)

        ! Plain RTE: the store re-executes, misses again, and the walker
        ! installs the row the handler just published.
        rte
        nop

        .align 2
Htea:        .long 0xFF00000C           ! TEA: the faulting virtual address
Hvpnmask:    .long 0xFFFFF000
Hslot:       .long 0xFF000048           ! P4_TSBSLOT
Hp1:         .long 0x80000000
Hptel:       .long 0x000101E9           ! PA 0x10000 | pm=1 | W|X|U|C|V
#endif
        ! ---- The image must reach past the END of the TSB (PA 0x14000..
        ! ---- 0x15FFF): the walker reads the TSB by PHYSICAL address and a
        ! ---- physical alias is backed by SRAM only within the loaded image.
        .org 0x16000
