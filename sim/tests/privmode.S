! PM0 privileged-instruction-trap test.
!
! A privileged control-register instruction (LDC Rm,VBR) must:
!   - execute normally in supervisor mode (SR.MD=1, the reset state), and
!   - trap as GENERAL_ILLEGAL in user mode (SR.MD=0).
!
! Requires the DUT built with the PRIV_ARCH generic = true (see cpu_tb.vhd).
!
! Exception scaffolding (vbr_base / exception_entry / exception_trampoline) is
! modelled on rte.S. PM0 note: exception entry does NOT switch to MD=1 yet (that
! is PM2), so the handler runs in user mode -- it uses only non-privileged
! instructions and never executes RTE (which is itself privileged). Reaching the
! handler already proves the trap fired, so it branches straight to _done.

#include "sim_instr.h"

#define ENTRY(name) .globl name; .balign 4; name:

        .section .vect
        .long start            ! 0: power-on PC
        .long 0x00007000       ! 1: power-on SP (safe address inside RAM 0..0x7b00)
        .long start            ! 2: manual reset PC
        .long 0x00007000       ! 3: manual reset SP
        ! Filler so the simulator's magic block lands at its fixed 64-word offset.
        .rept 60
        .long 0
        .endr
        .long SIM_INSTR_MAGIC
        .long _sim_instr_end
        .long _done            ! PC the simulator reports as success
        .long _fail_loop       ! PC the simulator reports as failure
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .section .text
ENTRY(start)
        ! point VBR at our exception vector base
        mov.l   p_vbr_base, r0
        ldc     r0, vbr        ! privileged, but MD=1 here -> must NOT trap

        ! drop to user mode: clear MD (SR bit 30)
        stc     sr, r1
        mov.l   p_mdmask, r2   ! 0xBFFFFFFF
        and     r2, r1
        ldc     r1, sr         ! issued while still privileged; afterwards MD=0
        ! let the new SR (MD=0) commit before the privileged instruction is
        ! fetched and privilege-checked (LDC SR has pipeline latency)
        nop
        nop
        nop
        nop

        ! user mode: execute a privileged instruction.
        ldc     r0, vbr
        ! Fall-through = the instruction did NOT trap.
#if CONFIG_PRIV_ARCH
        ! J4: a GENERAL_ILLEGAL trap was required; not trapping is a failure.
        bra     _fail_loop
#else
        ! J2/J1: no privilege model, so LDC VBR must execute normally (no trap).
        ! Reaching here is the correct, expected result.
        bra     _done
#endif
        nop

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0        ! 0 = pass
        bra     _done
        nop

ENTRY(_fail_loop)
        mov.l   p_test_result, r0
        mov     #1, r9
        mov.l   r9, @r0        ! non-zero = fail
        bra     _fail_loop
        nop

        ! Minimal exception handler. Reached via the trampoline below; runs in
        ! user mode (PM0), so uses only the non-privileged BRA.
ENTRY(exception_handler)
#if CONFIG_PRIV_ARCH
        ! J4: the trap firing is exactly what we wanted -> success.
        bra     _done
#else
        ! J2/J1: no privileged-instruction trap must ever fire. Reaching the
        ! handler means PM0 leaked into a non-PRIV_ARCH build -> failure.
        bra     _fail_loop
#endif
        nop

        .align 2
p_vbr_base:    .long vbr_base
p_mdmask:      .long 0xBFFFFFFF
p_test_result: .long TEST_RESULT_ADDRESS

        ! Per-vector entry stubs (from rte.S): vector N enters at +N*6, pushes
        ! the vector number, and branches to the common trampoline.
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
