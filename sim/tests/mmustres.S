! mmustres.S -- minimal store-resume guard: does a STORE re-execute & WRITE after
! a DMISS_W fault is resolved?
!
! mmuldtlbr.S proves a resumed LOAD works. This isolates the resumed STORE.
!
! Flow:
!   - map the code page identity (W|X|U|C), enable AT
!   - CONTROL: store to an ALREADY-mapped page (the code page) -- must write,
!     no fault (rules out a generic AT-store bug). Verified by load-back; on
!     mismatch -> fail code 3.
!   - store 0x5B5B0002 to an UNMAPPED identity page -> DMISS_W (vector 0x440).
!     Handler publishes the identity PTE as a TSB row and RTEs, so the store
!     RE-EXECUTES, misses again, and the walker installs the entry.
!   - load the page back; compare to 0x5B5B0002.
!       match           -> PASS (result 0)
!       read seed 0      -> fail code 2 (resumed store DID NOT WRITE)
!       read other       -> fail code 4 (wrote wrong)
!
! VBR = _v_store - 0x400 so the DMISS_W vector (VBR+0x400) hits _v_store.

!
! ---- walker-install version (retire-LDTLB) --------------------------------
! Both LDTLB sites are gone and the guard's property is UNCHANGED: after a
! DMISS_W is resolved, does the faulting STORE re-execute and actually write?
!
! What replaced what:
!   * the code page is installed by the WALKER, from a TSB row, on the first
!     fetch after AT comes on. No fault, no handler.
!   * the FAULT page deliberately has NO TSB row at reset, so the store still
!     takes a real DMISS_W (EXPEVT 0x080) exactly as before. The handler no
!     longer installs a TLB entry and resumes atomically with LDTLB.RN -- it
!     WRITES THE TSB ROW and does a plain `rte`. The store then re-executes,
!     misses again, and this time the walker finds the row and installs it, so
!     the store completes. The resume-and-write path under test is the same
!     one, reached the only way it can now be reached.
!
! The handler writes the TSB row THROUGH THE P1 ALIAS: AT is still on inside
! the handler and the TSB itself is unmapped, so a P0 store to it would fault
! recursively. The set address comes from the P4 helper at 0xFF000048 (P4 is
! untranslated), never from a hand-computed hash.
!
! Strength: STRONGER, by two additions.
!   * result 5 pins the fault kind to DMISS_W (EXPEVT 0x080). The LDTLB version
!     accepted any exception that reached the vector.
!   * result 6 requires the handler to have RUN AT ALL. Without it a stray or
!     mis-hashed TSB row that happened to cover the fault page would let the
!     walker resolve the access silently, the data check would pass, and the
!     entire resume-after-fault property this guard exists for would be gone
!     with nothing to notice. That is the exact vacuity this migration risks.
!
! Setup requirements walker-only install adds:
!   * RB is already cleared here (this guard always did), which matters more
!     now: core/cpu.vhd's walk_req is gated on dp_sr.rb = '0'.
!   * The image is padded past the END of the TSB -- the walker reads the TSB
!     BY PHYSICAL ADDRESS and the cosim backs SRAM only within the loaded
!     image, so a TSB beyond it reads as nothing and every walk silently
!     misses with no fault and no data.
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

#define SVAL 0x5B5B0002

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

        ! ---- Configure the TSB and install the CODE page row only. The fault
        ! ---- page is deliberately absent so the store still takes DMISS_W.
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
        mov.l   p_pteh_code, r6         ! code page VA
        mov.l   p_vpnmask, r0
        and     r0, r6                  ! tag_hi is VA & PAGE_MASK; `start` is
                                        ! not page-aligned, and the walker's
                                        ! tag compare is EXACT
        mov     #0, r7                  ! ASID 0
        ! Build the code-page PTEL properly. The LDTLB version wrote
        ! `start + 0xC8` as a literal, which is NOT the flags it names: start
        ! is 0x118, so the sum is 0x1E0 -- U set, C clear. That was latent and
        ! harmless under LDTLB; the walker also needs V, so build it here.
        mov.l   p_pteh_code, r0
        mov.l   p_ppnmask, r1
        and     r1, r0                  ! PPN = start & 0xFFFFFC00
        or      #0xC9, r0               ! W|X|C|V, U=0 (SMEP)
        mov     r0, r8
        mov.l   r6, @r12
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        ! ---- Clear the "handler ran" flag. ----
        mov.l   p_ranflag, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- CONTROL: store to an ALREADY-mapped page (no fault). ----
        mov.l   c_ctrl_va, r2
        mov.l   c_ctrl_val, r3
        mov.l   r3, @r2                  ! must write (TLB hit, AT on)
        mov.l   @r2, r5                  ! read back
        cmp/eq  r3, r5
        mov     #3, r9
        bf      _failj                    ! control store failed -> generic AT-store bug

        ! ---- Take a DMISS_W: STORE SVAL to unmapped identity page 1. ----
        mov.l   c_fault_va, r2
        mov.l   c_sval, r3
        mov.l   r3, @r2                  ! FAULTS -> _v_store; on re-exec must WRITE SVAL

        ! ---- Handler RTE'd and the walker installed it, AT still on.
        ! ---- Read back & classify. ----
        mov.l   c_fault_va, r2
        mov.l   @r2, r6
        mov.l   c_sval, r3
        cmp/eq  r3, r6
        bt      _check_ran               ! wrote correctly
        mov     #0, r7
        cmp/eq  r6, r7
        mov     #2, r9
        bt      _failj                    ! read seed 0 -> store did not write
        mov     #4, r9
        bra     _failj                    ! wrote wrong
        nop

        ! ---- _fail is now far below (past the handler, the fault page and the
        ! ---- TSB padding), out of bf/bra range. Trampoline to it.
ENTRY(_failj)
        mov.l   t_failaddr, r0
        jmp     @r0
        nop
        .align 2
t_failaddr:     .long _fail
        ! The flag MUST live inside the identity-mapped code page: the handler
        ! writes it with AT on, and any other page is unmapped -- a store there
        ! would fault recursively inside the handler.
_g_handler_ran: .long 0

ENTRY(_check_ran)
        ! ---- The handler MUST have run. If a stray TSB row had let the
        ! ---- walker resolve the store silently, every data check above would
        ! ---- still pass and the resume-after-fault property would be gone.
        mov.l   pr_ranflag, r0
        mov.l   @r0, r0
        tst     r0, r0
        bf      1f
        mov     #6, r9
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
pr_ranflag:     .long _g_handler_ran
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
p_ranflag:      .long _g_handler_ran
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000C9        ! +V: the walker rejects V=0        ! U cleared: kernel code, SMEP
c_ctrl_va:      .long _ctrl_word
c_ctrl_val:     .long 0xC0DEC0DE
c_fault_va:     .long _fault_word
c_sval:         .long SVAL

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

        ! ---- a writable scratch word in the (mapped) code page for the control ----
        .align 2
_ctrl_word:     .long 0

        ! ---- DMISS_W handler at VBR+0x400 ----
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
        mov     #5, r9
        mov.l   Hfailaddr, r0
        jmp     @r0
        nop
1:
        ! ---- Record that the fault path really was taken. ----
        mov.l   Hranflag, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Resolve the miss by writing the TSB row, then plain RTE. The
        ! ---- store re-executes, misses again, and the WALKER installs it.
        mov.l   Htsbslot, r0
        ! ---- row for _fault_page ----
        mov.l   Hfault_va, r1
        mov.l   r1, @r0                 ! VA -> P4 helper
        mov.l   @r0, r2                 ! r2 = PA of the 32-byte set
        mov.l   Hp1, r3
        or      r3, r2                  ! P1 alias: AT is on, the TSB is unmapped
        mov.l   Hfault_ptel, r4
        mov.l   r4, @(8, r2)            ! data
        mov     #0, r4
        mov.l   r4, @(4, r2)            ! tag_lo = ASID 0
        mov.l   Hfault_va, r4
        mov.l   r4, @(0, r2)            ! tag_hi LAST -- the commit point
        rte
        nop
_h_fail_spin:
        bra     _h_fail_spin
        nop

        .align 2
Hfailaddr:      .long _fail
Hdmiss_w:       .long 0x00000080        ! EXPEVT for DMISS_W
Hranflag:       .long _g_handler_ran
Htsbslot:       .long 0xFF000048
Hp1:            .long 0x80000000
Hfault_va:      .long _fault_page
Hfault_ptel:    .long _fault_page + 0x000000E9

        ! ---- Fault page: holds _fault_word (seed 0). ----
        .balign 0x1000
_fault_page:
_fault_word:    .long 0
        .space 0x1000 - 4, 0

        ! Pad the image past the END of the TSB at PA 0x00060000; the walker
        ! reads the TSB by PHYSICAL address and the cosim backs SRAM only
        ! within the loaded image.
        .org 0x62000
#endif
