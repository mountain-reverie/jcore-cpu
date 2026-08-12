! mmuwalkiside.S -- an instruction-fetch miss walks on the DATA bus.
!
! The I-side stalls on inst_i.ack (cpu.vhd: `inst_i.ack and not walk_supp_i`)
! while the walker uses db_o, so there is no bus contention -- but that is a
! claim, not a fact, until something jumps to a page absent from the TLB and
! comes back. This guard branches into a page present in the TSB but absent
! from the TLB and asserts execution continues there with no exception.
!
! The target lives in its own `.tlbtext` output section, linked by
! sim/tests/sh32_tlbtext.x at 0x00008000 -- the first page above the stack
! region, and one the identity code-page mapping installed at startup does NOT
! cover. VMA == LMA (identity), so the PTEL below carries PPN 0x00008000; the
! I-side walk is what makes the page reachable at all. (Relocating VA/=PA is
! mmureloc/mmurelocif's job, not this guard's -- keeping it identity removes a
! whole class of "target never executed" misreadings.)
!
! Slot arithmetic, using mmutsb.S's documented hash:
!   VA 0x00008000 -> vpn 0x08, hash 0x08^(0x08>>6)=0x08, idx 0x08 -> 0x00010100
!
! The PTEL clears U (bit 5): a kernel fetch of a U=1 page is an SMEP violation
! (tlb.vhd I-lookup), which would present as a protection fault rather than a
! walk. X (bit 6) is set so the fetch itself is permitted.
!
! Result codes:
!   1  target never executed -- the fetch was lost (or the guard fell through)
!   2  SPC moved -- an exception was taken instead of a walk
!   3  the walk counter did not advance -- the walker never ran
!
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

        ! ---- VBR = _v_fault - 0x400 ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the slot the I-side walk will probe for VA 0x00008000. ----
        mov.l   p_tsb_slot, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_x, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Seed the SPC sentinel, then enable AT. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC

        ! ---- Code page: the identity mapping that LDTLB used to install is
        ! ---- now a GLOBAL TSB entry that the walker installs on the first
        ! ---- instruction fetch after AT goes on. GLOBAL so no ASID change can
        ! ---- perturb it; U=0 (SMEP). The set address is asked of the P4 slot
        ! ---- helper (0xFF000048 -- the single tsb_ptr() implementation the
        ! ---- walker and TSBPTR also use), never hand-computed. WAY 1, so it
        ! ---- cannot displace the entries this guard places in way 0. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6         ! VA = PA = start (4 KB-aligned)
        mov     #0, r7
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill_way r10, 16, r6, r7, r8

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Jump into the unmapped page: I-fetch miss, walker resolves. ----
        mov.l   p_target, r0
        jmp     @r0
        nop

        mov     #1, r9                  ! fell through -> target never executed
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD ! identity: PPN=start, U cleared (SMEP)
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsb_slot:     .long 0x00010100        ! hash(0x00008000) -- see header
p_vpn:          .long 0x00008000
p_asid:         .long 0x00000000
p_ptel_x:       .long 0x000080C9        ! PA 0x00008000 | W|X|C|V, U=0 (SMEP)
p_sent_spc:     .long 0xDEADBE00
p_target:       .long _target

#else
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! MISS-vector stub at VBR+0x400. Reaching it means an exception was
        ! taken where the walker should have resolved the fetch -- code 2.
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #2, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

! ======================================================================
! Translated-only code. Linked at VA 0x00008000 by sh32_tlbtext.x, absent
! from the TLB, reachable only if the walker installs the TSB entry above.
! Reaching _target AT ALL is the guard's central positive observation.
!
! _done/_fail are ~28 KB away, well outside bra's +/-4 KB displacement, so
! the exits use mov.l + jmp.
! ======================================================================
        .section .tlbtext, "ax"
        .balign 4
_target:
        ! ---- 2: SPC untouched -> no exception was entered on the way here.
        .word   0x0042                  ! STC SPC, r0
        mov.l   t_sent_spc, r1
        cmp/eq  r0, r1
        bt      1f
        mov     #2, r9
        bra     _t_exit_fail
        nop
1:
        ! ---- 3: did the walker actually run?
        mov.l   t_walkcnt, r0
        mov.l   @r0, r1
        tst     r1, r1
        bf      2f
        mov     #3, r9
        bra     _t_exit_fail
        nop
2:
        mov.l   t_mmucr, r0             ! AT off (identity below, so execution
        mov     #0, r1                  ! continues at PA == VA unchanged)
        mov.l   r1, @r0
        mov.l   t_done, r0
        jmp     @r0
        nop

_t_exit_fail:
        mov.l   t_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   t_fail, r0
        jmp     @r0
        nop

        .align 2
t_sent_spc:     .long 0xDEADBE00
t_walkcnt:      .long 0xFF000054
t_mmucr:        .long 0xFF000010
t_done:         .long _done
t_fail:         .long _fail

#endif  ! CONFIG_PRIV_ARCH
