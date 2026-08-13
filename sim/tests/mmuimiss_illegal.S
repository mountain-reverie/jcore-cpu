! mmuimiss_illegal.S -- guard: illegal instruction in a TLB-miss-mapped page
! still traps GENERAL_ILLEGAL (Task 1's I-side IMISS suppression must be
! TRANSIENT: it only covers the *faulting* fetch, not later fetches from a
! page that has since been mapped).
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). SAME strength: the subject is
! the transience of the I-side IMISS suppression, and every step below is
! unchanged except HOW the handler makes VA 0x1000 appear. It now publishes a
! TSB row and lets the walker install on the retried fetch -- which, if
! anything, makes the scenario more faithful: the retried fetch of VA 0x1000 is
! a real miss that walks in, so the illegal word is fetched through a
! freshly-walked entry rather than one pre-loaded behind the fetch's back.
!
! Flow:
!   - VBR set so VBR+0x100 = general-illegal handler, VBR+0x400 = IMISS
!     handler (both hang off one VBR, 0x300 bytes apart).
!   - map page 0 (the running code) identity, enable AT.
!   - jmp to VA 0x1000 (page 1, initially UNMAPPED) -> IMISS.
!   - IMISS handler: publishes a TSB row for VA 0x1000 -> PA(zero_page)
!     (zero_page is a whole page filled with 0x0000, i.e. an illegal
!     instruction at offset 0 = the fetch offset), sets SPC=0x1000 (re-fetch
!     the SAME faulting VA), RTE.
!   - Control returns to VA 0x1000, NOW MAPPED: fetch of 0x0000 must raise
!     GENERAL_ILLEGAL (texc_req cleared once the IMISS dispatched, so Task 1's
!     transient suppression no longer applies) -> handler at VBR+0x100.
!   - GENERAL_ILLEGAL handler: pin EXPEVT == 0x180 (VBR+0x100 is ALSO the TLB
!     protection vector, so the address alone proves nothing -- fail 5 on any
!     other cause), then write pass and reach _done.
!
! Result codes:
!   0  pass -- the fetch from the freshly-walked page trapped GENERAL_ILLEGAL
!   5  VBR+0x100 was reached with EXPEVT != 0x180 (a protection fault, not the
!      illegal instruction)
!   7  execution fell through past the faulting jmp -- no fault at all
!
! If the suppression is NOT transient, or the mapping/vectoring is wrong, the
! CPU will either re-take an IMISS forever, silently execute past the illegal
! word, or hang -- none of which reach "Test Passed".

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

        ! ---- VBR = _h_general_illegal - 0x100 (so VBR+0x100 = the general
        ! illegal handler, and VBR+0x400 = _h_imiss, 0x300 bytes later). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB (base 0x00014000, TSB_SIZE_LOG=8 -> 256 sets
        ! ---- x 32 bytes; HASH_SHIFT=6, HASH_MODE=1) and publish the row for
        ! ---- page 0 (VA 0x0000-0x0FFF): identity, W|X|C|V, U CLEARED -- this
        ! ---- page is FETCHED, and a kernel fetch of a U=1 page is an SMEP
        ! ---- protection fault. AT is off, so these are plain P0 stores.
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR  (ASID 0 throughout)
        nop
        nop
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbslot, r12
        mov     #0, r6                  ! VA 0
        mov     #0, r7                  ! ASID 0
        mov.l   p_ptel_page0, r8        ! PTEL
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Take an IMISS: jump to VA 0x1000 (page 1, unmapped). ----
        mov.l   c_page1_va, r0
        jmp     @r0                     ! FAULTS -> _h_imiss (VBR+0x400), IMISS
        nop

        ! Should never reach here: the IMISS handler redirects SPC back to
        ! VA 0x1000, which now traps GENERAL_ILLEGAL instead of returning.
        mov     #7, r9
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _h_general_illegal - 0x100
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C9        ! identity page 0, W|X|C|V, U=0 (SMEP)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
c_page1_va:     .long 0x00001000

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

        ! ---- GENERAL_ILLEGAL handler at VBR+0x100 ----
        ! Pad so _h_general_illegal lands comfortably past the code above and
        ! stays inside page 0 (so its own fetch is mapped).
        .balign 4
        .space 0x600, 0
        .balign 4
_h_general_illegal:                     ! = VBR + 0x100
        ! Reached only if the mapped-page fetch of 0x0000 correctly trapped
        ! as GENERAL_ILLEGAL: write pass and stop (do NOT RTE / resume --
        ! resuming would re-execute the illegal word).
        !
        ! PIN THE FAULT KIND. VBR+0x100 is also the TLB PROTECTION vector, so
        ! arriving here is not by itself evidence of a general-illegal trap: an
        ! SMEP rejection of the fetched page, or any protection fault, lands on
        ! exactly this address. EXPEVT must read GENERAL_ILLEGAL (0x180) or the
        ! guard reports fail 5 instead of passing on the wrong exception.
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_illegal, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #5, r9
        bra     _fail
        nop
1:
        mov.l   Hres_addr, r0
        mov.l   Hres_addr_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
        .space 0x300 - (. - _h_general_illegal), 0

        ! ---- IMISS handler at VBR+0x400 = _h_general_illegal + 0x300 ----
        ! NOTE: this handler's own code lives in page 1 (the same unmapped
        ! page that just faulted) -- like mmuimiss.S's handler, entry and a
        ! couple of following instructions ride the still-resident fetch
        ! pipeline. But installing the page-1 TLB entry takes several
        ! instructions, and doing that with AT=1 risks a second, nested
        ! translation lookup (for the handler's OWN fetch) landing on the
        ! not-yet-installed entry. So, exactly like mmuimiss.S, disable AT
        ! first, do all TLB setup with translation off (no fetch is ever
        ! checked against the TLB while AT=0), then re-enable AT and RTE with
        ! only a tiny (2-instruction) window before the redirected fetch.
_h_imiss:
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR.AT = 0 (safe to reconfigure TLB)

        ! Publish the TSB row for VA 0x1000 -> PA(zero_page). AT is off here,
        ! so the set address can be stored to directly through P0.
        mov.l   Hslot, r0
        mov.l   Hpage1_va, r1
        mov.l   r1, @r0                 ! ask the P4 helper for this VA's set
        mov.l   @r0, r3                 ! r3 = 32-byte-aligned SET address
        mov.l   Hzero_page_pte, r4      ! PTEL for zero_page (PPN | flags | V)
        mov     #0, r5                  ! ASID_TAG = 0
        mov.l   r4, @(8, r3)            ! data first ...
        mov.l   r5, @(4, r3)            ! ... tag_lo second ...
        mov.l   r1, @(0, r3)            ! ... tag_hi LAST (the commit point)

        mov.l   Hmmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! MMUCR.AT = 1 (translation back on)

        ! Re-fetch the same faulting VA (now mapped) on RTE.
        mov.l   Hpage1_va, r0
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hpage1_va:      .long 0x00001000
Hslot:          .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
Hzero_page_pte: .long _zero_page + 0x000000C9   ! PPN(_zero_page) | W|X|C|V, U=0
Hexp_illegal:   .long 0x00000180        ! EXPEVT for GENERAL_ILLEGAL
Hres_addr:      .long TEST_RESULT_ADDRESS
Hres_addr_pass:      .long   TEST_PASS_MAGIC

        ! ---- Backing page for VA 0x1000: a whole zeroed physical page, so
        ! offset 0 (the fetch offset for VA 0x1000) is the illegal word
        ! 0x0000. Page-aligned so the PTEL PPN field is exact.
        !
        ! NOTE: deliberately NOT using .balign/.align here: a directive
        ! requesting an alignment bigger than the section's existing
        ! alignment bumps the *input section's* recorded alignment
        ! (sh_addralign), which makes the linker align the whole .text
        ! input section itself -- pushing "start" off to a 4K-aligned
        ! address and breaking all the VBR/handler offset arithmetic above
        ! (confirmed: this silently moved "start" from 0x118 to 0x1000 and
        ! broke the guard). Pad with a fixed literal byte count instead
        ! (computed once from the build's symbol table and hardcoded) so
        ! the section's alignment requirement never changes. ----
        .space 0x510, 0                 ! pad -> _zero_page at PA 0x1000 (see NOTE above)
_zero_page:
        .space 0x1000, 0

        ! ---- The image must reach past the END of the TSB (PA 0x14000..
        ! ---- 0x15FFF): the walker reads the TSB by PHYSICAL address and a
        ! ---- physical alias is backed by SRAM only within the loaded image.
_tsb_backing:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
