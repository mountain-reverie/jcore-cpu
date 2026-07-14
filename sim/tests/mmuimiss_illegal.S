! mmuimiss_illegal.S -- guard: illegal instruction in a TLB-miss-mapped page
! still traps GENERAL_ILLEGAL (Task 1's I-side IMISS suppression must be
! TRANSIENT: it only covers the *faulting* fetch, not later fetches from a
! page that has since been mapped).
!
! Flow:
!   - VBR set so VBR+0x100 = general-illegal handler, VBR+0x400 = IMISS
!     handler (both hang off one VBR, 0x300 bytes apart).
!   - map page 0 (the running code) identity, enable AT.
!   - jmp to VA 0x1000 (page 1, initially UNMAPPED) -> IMISS.
!   - IMISS handler: installs the VA 0x1000 -> PA(zero_page) mapping
!     (zero_page is a whole page filled with 0x0000, i.e. an illegal
!     instruction at offset 0 = the fetch offset), sets SPC=0x1000 (re-fetch
!     the SAME faulting VA), RTE.
!   - Control returns to VA 0x1000, NOW MAPPED: fetch of 0x0000 must raise
!     GENERAL_ILLEGAL (texc_req cleared once the IMISS dispatched, so Task 1's
!     transient suppression no longer applies) -> handler at VBR+0x100.
!   - GENERAL_ILLEGAL handler: write pass (0), reach _done.
!
! If the suppression is NOT transient, or the mapping/vectoring is wrong, the
! CPU will either re-take an IMISS forever, silently execute past the illegal
! word, or hang -- none of which reach "Test Passed".

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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
p_ptel_page0:   .long 0x000000C8
c_page1_va:     .long 0x00001000

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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
        mov.l   Hres_addr, r0
        mov     #0, r9
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

        ! Install VA 0x1000 -> PA(zero_page) mapping, X+U+C perms.
        mov.l   Hpage1_va, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0x1000, ASID=0)
        mov.l   Hzero_page_pte, r0      ! r0 = PTEL for zero_page (PPN | flags)
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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
Hzero_page_pte: .long _zero_page + 0x000000C8   ! PPN(_zero_page) | flags
Hres_addr:      .long TEST_RESULT_ADDRESS

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
        .space 0x554, 0                 ! pad _zero_page_probe (0xAAC) -> 0x1000
_zero_page:
        .space 0x1000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
