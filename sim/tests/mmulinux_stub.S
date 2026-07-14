! mmulinux_stub.S -- SP2 Task 0 bring-up: throwaway harness stub to prove the
! REAL linux@jcore handler objects (arch/sh/mm/tlb-jcore.o,
! arch/sh/kernel/cpu/jcore/{ex,entry}.o) LINK at ram@0 with sim/tests/sh32.x.
!
! This is NOT a scenario test. It exists only to satisfy the undefined
! symbols those three objects reference, so `sh2-elf-ld -T sh32.x` can
! resolve every relocation and prove there is no absolute PAGE_OFFSET-style
! addressing baked into the linked objects (the SP2 de-risking question).
!
! Undefined-symbol stub set (recorded verbatim from `sh2-elf-nm` on the three
! kbuild-produced objects, cross-object references only):
!   arch_local_irq_restore   (tlb-jcore.o)
!   arch_local_save_flags    (tlb-jcore.o)
!   exception_handler        (ex.o)
!   do_page_fault            (entry.o)
! (jcore_tlb_fault_entry and __jcore_tlb_walk are also " U " in nm output but
! resolve INTERNALLY between ex.o/entry.o/tlb-jcore.o -- not stubbed here.)

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
        mov.l   p_test_result, r0
        mov     #0, r1
        mov.l   r1, @r0
_done:
        bra     _done
        nop
_fail:
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

! ---- stubs for the linux objects' cross-object undefined symbols ----
ENTRY(do_page_fault)
        rts
        nop

ENTRY(exception_handler)
        rts
        nop

ENTRY(arch_local_irq_restore)
        rts
        nop

ENTRY(arch_local_save_flags)
        rts
        nop
