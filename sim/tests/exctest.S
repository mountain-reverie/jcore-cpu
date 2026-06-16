! PM2 register-model exception round-trip test (J4 only).
!
! Boots supervisor (MD=1), drops to user (MD=0), executes a privileged
! instruction (LDC Rm,VBR) which traps as GENERAL_ILLEGAL. With PM2 the
! exception entry sets MD=1, so the handler runs PRIVILEGED (the PM0 limitation
! is gone). The handler:
!   - confirms MD=1 on entry (would be 0 under the old/no-PM2 behaviour),
!   - bumps SPC past the faulting instruction (STC SPC / +2 / LDC SPC),
!   - writes a success sentinel,
!   - RTE -> SR<-SSR (restores user MD=0), PC<-SPC (the bumped address).
! Control returns to user mode just after the faulting LDC, which reaches _done.
!
! J4-only (#if CONFIG_PRIV_ARCH); on J2 there is no register exception model, so
! skip-pass. Requires the J4 decoder (make -C decode generate-j4).

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
        .long _fail_loop
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .text
ENTRY(start)
#if CONFIG_PRIV_ARCH
        ! establish RB=0 (reset leaves RB=1) before using GPRs
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! VBR (SH-4 fixed vector): VBR+0x100 == exception_handler
        mov.l   p_vbr_fixed, r0
        ldc     r0, vbr

        ! sentinel = 0
        mov.l   p_sentinel, r1
        mov     #0, r2
        mov.l   r2, @r1

        ! drop to user mode (clear MD, bit 30)
        stc     sr, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr
        nop
        nop
        nop

        ! user mode: privileged instruction -> GENERAL_ILLEGAL -> handler (MD=1)
        ldc     r0, vbr
        ! RTE returns here (SPC was bumped past the LDC):
        mov.l   p_sentinel, r1
        mov.l   @r1, r2
        mov     #1, r5
        cmp/eq  r5, r2
        bf      _fail_loop
        bra     _done
        nop

        ! handler: runs in MD=1 (PM2). Verify MD, bump SPC, set sentinel, RTE.
ENTRY(exception_handler)
        stc     sr, r4
        mov.l   p_mdbit, r5         ! 0x40000000
        and     r5, r4
        tst     r4, r4
        bt      _fail_loop          ! MD not set on entry -> PM2 entry broken
        ! bump SPC by 2 (skip the faulting LDC) so RTE doesn't re-trap
        .word   0x0042              ! STC SPC, R0   (0000 0000 0100 0010)
        add     #2, r0
        .word   0x404E              ! LDC R0, SPC   (0100 0000 0100 1110)
        ! sentinel = 1
        mov.l   p_sentinel, r1
        mov     #1, r2
        mov.l   r2, @r1
        rte
        nop

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail_loop)
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail_loop
        nop

        .align 2
p_vbr_base:    .long vbr_base
p_vbr_fixed:   .long exception_handler - 0x100   ! J4: VBR+0x100 == handler
p_mdmask:      .long 0xBFFFFFFF
p_rbclear:     .long 0xDFFFFFFF
p_mdbit:       .long 0x40000000
p_sentinel:    .long 0x00007800
p_test_result: .long TEST_RESULT_ADDRESS

        ! exception entry stubs + trampoline (from rte.S / privmode.S)
ENTRY(exception_entry)
no = 0
        .rept 256
        nop
        mov.l   r1,@-sp
        bra     exception_trampoline
        mov     #no,r1
no = no + 1
        .endr
exception_trampoline:
        mov.l   r0,@-sp
        mov.l   $exception_handler,r0
        extu.b  r1,r1
        jmp     @r0
        extu.w  r1,r1
        .align 2
$exception_handler:
        .long   exception_handler

        .align 2
ENTRY(vbr_base)
vector = 0
        .rept 256
        .long   exception_entry + vector * 6
vector = vector + 1
        .endr
#else
        ! J2/J1: no register exception model -> nothing to test, pass by skipping.
        bra     _done
        nop
ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail_loop)
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail_loop
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
#endif
