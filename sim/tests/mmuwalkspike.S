! mmuwalkspike.S -- Task 1 feasibility spike ONLY. Deleted in Task 3.
!
! Proves that a three-cycle bus takeover during a D-side TLB miss does not
! corrupt the faulting access or the exception that follows. The spike is
! transparent by construction: it holds the bus, reads a dummy address, and
! releases. If ack-withholding or the db_o mux is wrong, the faulting load
! either never re-issues (timeout) or returns the dummy address's data.
!
! Flow:
!   - seed PA 0x00000FF0 with 0xA5A5A5A5 (AT off)
!   - map page 0 identity, enable AT
!   - LOAD from VA 0x00004FF0 -- UNMAPPED -> D-side TLB miss. The spike fires
!     here: it withholds ack for three cycles and drives the external db_o at
!     0x10000000 while it does.
!   - the TLB-miss handler (VBR+0x400) maps VPN 0x4000 -> PA 0x0000 and returns
!     via LDTLB.RN; the resumed load must read 0xA5A5A5A5 through the new
!     mapping.
!
! Result codes:
!   1  exception never arrived (access lost / hung)
!   2  handler ran but the resumed load returned wrong data
!
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
        ! Macro definitions only -- emits no code. The literal pool the PASS /
        ! FAIL macros reference is placed by `mmuwalk_pool` after their last use.
#include "mmuwalk_common.inc"

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

        ! ---- Seed the backing word at PA 0x00000FF0 (AT still off). ----
        mov.l   c_seed_pa, r0
        mov.l   c_seed_val, r1
        mov.l   r1, @r0

        ! ---- "handler ran" marker (r8 is NOT banked, so the handler can set
        !      it while running with RB=1). ----
        mov     #0, r8

        ! ---- VBR = _v_tlb - 0x400 (so VBR+0x400 = _v_tlb). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- ASIDR = 0. ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Map page 0 (VA 0x0000-0x0FFF) identity: kernel code+data. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- The faulting load: VA 0x4FF0 is UNMAPPED -> D-side TLB miss. ----
        mov.l   c_fault_va, r2
        mov.l   @r2, r3                 ! faults; resumes here after LDTLB.RN

        ! ---- Disable AT before touching the sim result register. ----
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Verify. ----
        tst     r8, r8
        bf      3f
        FAIL    1                       ! exception never arrived
3:
        mov.l   c_seed_val, r1
        cmp/eq  r1, r3
        bt      4f
        FAIL    2                       ! resumed load returned wrong data
4:
        PASS

        mmuwalk_pool
        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_tlb - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000D9        ! PA 0x0000 | W|X|D|C|V; U=0 (kernel code, SMEP)
c_seed_pa:      .long 0x00000FF0
c_seed_val:     .long 0xA5A5A5A5
c_fault_va:     .long 0x00004FF0

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

        ! ---- TLB-miss handler at VBR+0x400. PTEH already holds the faulting
        !      VPN (0x4000); install PA 0x0000 for it and return. ----
        .balign 4
        .space 0x620, 0
        .balign 4
_v_tlb:                                 ! = VBR + 0x400
        mov     #1, r8                  ! mark: the exception arrived
        mov.l   Hptel, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0078                  ! LDTLB.RN (install + return)

        .align 2
Hptel:          .long 0x000000D9        ! VPN 0x4000 -> PA 0x0000, W|X|D|C|V, U=0

        ! ---- Back page 0 out past PA 0xFF0 so the seed word is inside the
        !      loaded image (the sim RAM model reports X for unloaded words). ----
_page0_backing:
        .space 0x820, 0

#endif  ! CONFIG_PRIV_ARCH
