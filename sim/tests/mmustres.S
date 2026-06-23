! mmustres.S -- minimal store-resume guard: does a STORE re-execute & WRITE after
! a DMISS_W fault is resolved by LDTLB.R?
!
! mmuldtlbr.S proves a resumed LOAD works. This isolates the resumed STORE.
!
! Flow:
!   - map the code page identity (W|X|U|C), enable AT
!   - CONTROL: store to an ALREADY-mapped page (the code page) -- must write,
!     no fault (rules out a generic AT-store bug). Verified by load-back; on
!     mismatch -> fail code 3.
!   - store 0x5B5B0002 to an UNMAPPED identity page -> DMISS_W (vector 0x440).
!     Handler installs the identity PTE and does LDTLB.R (0x0068) to resume,
!     so the store RE-EXECUTES against the fresh TLB entry.
!   - load the page back; compare to 0x5B5B0002.
!       match           -> PASS (result 0)
!       read seed 0      -> fail code 2 (resumed store DID NOT WRITE)
!       read other       -> fail code 4 (wrote wrong)
!
! VBR = _v_store - 0x440 so the DMISS_W vector (VBR+0x440) hits _v_store.

#include "sim_instr.h"
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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_store - 0x440. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map the code page (identity, W+X+U+C = 0xE8). ----
        mov.l   p_pteh_code, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_code, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

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
        bf      _fail                    ! control store failed -> generic AT-store bug

        ! ---- Take a DMISS_W: STORE SVAL to unmapped identity page 1. ----
        mov.l   c_fault_va, r2
        mov.l   c_sval, r3
        mov.l   r3, @r2                  ! FAULTS -> _v_store; on re-exec must WRITE SVAL

        ! ---- Returned by LDTLB.R, AT still on. Read back & classify. ----
        mov.l   c_fault_va, r2
        mov.l   @r2, r6
        mov.l   c_sval, r3
        cmp/eq  r3, r6
        bt      _pass                    ! wrote correctly
        mov     #0, r7
        cmp/eq  r6, r7
        mov     #2, r9
        bt      _fail                    ! read seed 0 -> store did not write
        mov     #4, r9
        bra     _fail                    ! wrote wrong
        nop

ENTRY(_pass)
        mov.l   pr_test_result, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _pass
        nop
        .align 2
pr_test_result: .long TEST_RESULT_ADDRESS

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_store - 0x440
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000E8
c_ctrl_va:      .long _ctrl_word
c_ctrl_val:     .long 0xC0DEC0DE
c_fault_va:     .long _fault_word
c_sval:         .long SVAL

#endif

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

        ! ---- a writable scratch word in the (mapped) code page for the control ----
        .align 2
_ctrl_word:     .long 0

        ! ---- DMISS_W handler at VBR+0x440 ----
        .balign 4
        .space 0x440, 0
        .balign 4
_v_store:                               ! = VBR + 0x440
        mov.l   Hpteh, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   Hptel, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0068                  ! LDTLB.R -- install + return atomically
        nop                             ! delay slot
_h_fail_spin:
        bra     _h_fail_spin
        nop

        .align 2
Hpteh:          .long _fault_page
Hptel:          .long _fault_page + 0x000000E8

        ! ---- Fault page: holds _fault_word (seed 0). ----
        .balign 0x1000
_fault_page:
_fault_word:    .long 0
        .space 0x1000 - 4, 0

#endif
