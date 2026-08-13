! mmustr2.S -- back-to-back store-fault repro (M6 6th defect).
!
! mmustres.S proves a SINGLE resumed store writes. This isolates the case the
! task describes: a resumed store (DMISS_W, then resume) whose VERY NEXT access is
! ITSELF a DMISS_W. The first store's write must NOT be collateral-damaged by
! the second access's fault.
!
! Flow (AT on, identity maps; code page pre-mapped):
!   - store SVAL1 to unmapped identity page 1 -> DMISS_W.
!     Handler publishes an identity TSB row for the faulting VA and RTEs.
!     The resumed store re-executes, misses, the walker installs the entry
!     and the store WRITES SVAL1; the immediately
!     following instruction is ...
!   - store SVAL2 to unmapped identity page 2 -> a second DMISS_W (back-to-back).
!     Same handler resumes it; it writes SVAL2.
!   - read page 1 back, then page 2 back. Classify:
!       both match        -> PASS (0)
!       page1 wrong/seed   -> fail 2 (FIRST resumed store lost -- the defect)
!       page2 wrong/seed   -> fail 5 (second store lost)
!
! The handler is VA-driven: it reads the faulting VPN from PTEH (HW-captured at
! 4 KB) and installs an identity PTE = (PTEH_page | 0xE8). One handler services
! both pages, so the test does not depend on TSB/walker/flush machinery.
!
! VBR = _v_store - 0x400 so DMISS_W (VBR+0x400) lands on _v_store.

!
! ---- walker-install version (retire-LDTLB) --------------------------------
! Both LDTLB sites are gone and the guard's property is UNCHANGED: two
! BACK-TO-BACK faulting stores must each re-execute and write after their miss
! is resolved, and the FIRST must not be lost while the second is in flight.
!
! What replaced what:
!   * the code page is installed by the WALKER from a TSB row, on the first
!     fetch after AT comes on. No fault, no handler.
!   * neither fault page has a TSB row at reset, so BOTH stores still take a
!     real DMISS_W (EXPEVT 0x080) exactly as before. The handler no longer
!     installs a TLB entry and resumes atomically with LDTLB.RN -- it WRITES
!     THE TSB ROW for the faulting VA and does a plain `rte`. The store then
!     re-executes, misses again, and the walker installs it.
!
! The handler is now GENERIC: it takes the faulting VA from TEA (0xFF00000C)
! and builds an identity row from it, so it resolves whichever of the two
! pages faulted and CANNOT accidentally resolve the other one ahead of time.
! Resolving both on the first entry would silently delete the back-to-back
! property this guard exists for.
!
! It writes the row THROUGH THE P1 ALIAS: AT is still on inside the handler
! and the TSB itself is unmapped, so a P0 store to it would fault recursively.
! The set address comes from the P4 helper at 0xFF000048 (P4 is untranslated),
! never from a hand-computed hash.
!
! Strength: STRONGER, by two additions.
!   * result 6 pins the fault kind to DMISS_W (EXPEVT 0x080). The LDTLB version
!     accepted any exception that reached the vector.
!   * result 7 requires the handler to have run EXACTLY TWICE. Anything else
!     means the two stores were not two independent faults -- if a stray or
!     over-eager TSB row let the walker resolve one of them silently, both data
!     checks would still pass and the back-to-back case would be gone with
!     nothing to notice. That is the exact vacuity this migration risks.
!
! The image is padded past the END of the TSB at PA 0x00060000 -- the walker
! reads the TSB BY PHYSICAL ADDRESS and the cosim backs SRAM only within the
! loaded image, so a TSB beyond it reads as nothing and every walk silently
! misses with no fault and no data.
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

#define SVAL1 0x5B5B0011
#define SVAL2 0x5B5B0022

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

        ! ---- VBR = _v_store - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB and install the CODE page row only. NEITHER
        ! ---- fault page gets a row, so both stores still take DMISS_W.
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_tsbslot, r12
        mov.l   p_pteh_code, r6
        mov.l   p_vpnmask, r0
        and     r0, r6                  ! tag_hi is VA & PAGE_MASK, and the
                                        ! walker's tag compare is EXACT
        mov     #0, r7                  ! ASID 0
        ! Build the code-page PTEL properly. The LDTLB version wrote
        ! `start + 0xC8` as a literal, which is NOT the flags it names -- start
        ! is not 1 KB-aligned, so the sum carries into the flag byte. That was
        ! latent and harmless under LDTLB; the walker also needs V.
        mov.l   p_pteh_code, r0
        mov.l   p_ppnmask, r1
        and     r1, r0
        or      #0xC9, r0               ! W|X|C|V, U=0 (SMEP)
        mov     r0, r8
        mov.l   r6, @r12
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        ! ---- Zero the handler-entry counter. ----
        mov.l   p_hcount, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Two back-to-back faulting stores. ----
        mov.l   c_fault1_va, r2
        mov.l   c_sval1, r3
        mov.l   c_fault2_va, r10
        mov.l   c_sval2, r11
        mov.l   r3, @r2                  ! DMISS_W #1; on resume must WRITE SVAL1
        mov.l   r11, @r10               ! immediately faults -> DMISS_W #2

        ! ---- Read both back & classify. ----
        mov.l   c_fault1_va, r2
        mov.l   @r2, r6                 ! page1 readback
        mov.l   c_fault2_va, r10
        mov.l   @r10, r12              ! page2 readback

        mov.l   c_sval1, r3
        cmp/eq  r3, r6
        mov     #2, r9
        bf      _failj                   ! page1 not SVAL1 -> FIRST resumed store lost (the defect)

        mov.l   c_sval2, r11
        cmp/eq  r11, r12
        mov     #5, r9
        bf      _failj                   ! page2 not SVAL2 -> second store lost
        bra     _check_faults
        nop

        ! ---- _fail is now far below (past the handler, the fault pages and
        ! ---- the TSB padding), out of bf/bra range. Trampoline to it.
ENTRY(_failj)
        mov.l   t_failaddr, r0
        jmp     @r0
        nop
        .align 2
t_failaddr:     .long _fail
        ! The counter MUST live inside the identity-mapped code page: the
        ! handler updates it with AT on, and any other page is unmapped -- a
        ! store there would fault recursively inside the handler.
        .balign 4
_g_handler_count: .long 0

ENTRY(_check_faults)
        ! ---- Exactly two DMISS_W faults, one per store. See the header.
        mov.l   pr_hcount, r0
        mov.l   @r0, r0
        mov     #2, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #7, r9
        bra     _failj
        nop
1:
ENTRY(_pass)
        mov.l   pr_test_result, r0
        mov.l   pr_test_result_pass, r1
        mov.l   r1, @r0
        bra     _pass
        nop
        .align 2
pr_hcount:      .long _g_handler_count
pr_test_result: .long TEST_RESULT_ADDRESS
pr_test_result_pass: .long   TEST_PASS_MAGIC

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_store - 0x400
p_mmucr:        .long 0xFF000010
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00060008        ! base=0x00060000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_vpnmask:      .long 0xFFFFF000
p_ppnmask:      .long 0xFFFFFC00
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_hcount:       .long _g_handler_count
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C8        ! U cleared: kernel code, SMEP
c_fault1_va:    .long _fault_page1
c_fault2_va:    .long _fault_page2
c_sval1:        .long SVAL1
c_sval2:        .long SVAL2

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

        ! ---- VA-driven DMISS_W handler at VBR+0x400 ----
        ! Takes the faulting VA from TEA, writes an identity TSB row for it
        ! (through the P1 alias) and RTEs; the walker installs it on the
        ! re-executed store. Bank-1 scratch; AT stays on.
        .balign 4
        .space 0x400, 0
        .balign 4
_v_store:
        ! ---- Pin the fault kind: this guard is about DMISS_W and nothing
        ! ---- else. A different EXPEVT here means a different bug.
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hdmiss_w, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #6, r9
        mov.l   Hfailaddr, r0
        jmp     @r0
        nop
1:
        ! ---- Count this entry. Exactly two are expected. ----
        mov.l   Hcount, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0

        ! ---- Resolve THIS miss and only this one: the faulting VA comes from
        ! ---- TEA, so the handler can never resolve the other page early and
        ! ---- collapse the back-to-back case into a single fault.
        mov.l   Htea, r0
        mov.l   @r0, r5                 ! r5 = faulting VA
        mov.l   Hvpnmask, r1
        mov     r5, r6
        and     r1, r6                  ! r6 = tag_hi = VA & PAGE_MASK
        mov.l   Hppnmask, r1
        mov     r5, r0
        and     r1, r0
        or      #0xE9, r0               ! identity PTEL: W|X|U|C|V (or #imm is r0-only)
        mov     r0, r7

        mov.l   Htsbslot, r0
        mov.l   r6, @r0                 ! VA -> P4 helper
        mov.l   @r0, r2                 ! r2 = PA of the 32-byte set
        mov.l   Hp1, r3
        or      r3, r2                  ! P1 alias: AT is on, the TSB is unmapped
        mov.l   r7, @(8, r2)            ! data
        mov     #0, r4
        mov.l   r4, @(4, r2)            ! tag_lo = ASID 0
        mov.l   r6, @(0, r2)            ! tag_hi LAST -- the commit point
        rte
        nop
_h_fail_spin:
        bra     _h_fail_spin
        nop

        .align 2
Hfailaddr:      .long _fail
Hdmiss_w:       .long 0x00000080        ! EXPEVT for DMISS_W
Hcount:         .long _g_handler_count
Htea:           .long 0xFF00000C        ! MMU_TEA: the faulting VA
Hvpnmask:       .long 0xFFFFF000
Hppnmask:       .long 0xFFFFFC00
Htsbslot:       .long 0xFF000048
Hp1:            .long 0x80000000

        .balign 0x1000
_fault_page1:
        .long 0
        .space 0x1000 - 4, 0
_fault_page2:
        .long 0
        .space 0x1000 - 4, 0

        ! Pad the image past the END of the TSB at PA 0x00060000; the walker
        ! reads the TSB by PHYSICAL address and the cosim backs SRAM only
        ! within the loaded image.
        .org 0x62000
#endif
