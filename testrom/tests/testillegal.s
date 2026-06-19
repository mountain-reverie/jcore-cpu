! testillegal.s - J1 only: dropped opcodes must trap as illegal.
!
! Installs a minimal VBR table whose general-illegal vector (slot 4, offset 0x10)
! points at a local handler. Executes two dropped opcodes:
!   1. CAS.L r8,r9,@r0 (.word 0x2983) - dropped on J1
!   2. LDS r2,cpi_com  (.word 0x4288) - coprocessor op, dropped on J1
! Each trap increments a counter. Pass requires counter == 2.
!
! Exception model: SH-2 stack frame. On entry to handler:
!   @r15     = PC of faulting instruction
!   @(4,r15) = saved SR
! Handler advances @r15 by 2 to skip the 2-byte faulting opcode, then RTE.
! (Pattern taken from sim/tests/interrupts.S _general_illegal_instr_isr.)

        .section .text
        .global _testillegal
_testillegal:
        sts.l   pr, @-r15           ! save return address

        ! save current VBR so we can restore it at end
        stc     vbr, r14

        ! install custom VBR table: general-illegal (slot 4) -> _ill_handler
        mov.l   _pvbr_tab, r0
        ldc     r0, vbr

        ! zero the trap counter in scratch RAM
        mov.l   _pcounter, r2
        mov     #0, r1
        mov.l   r1, @r2

        ! --- dropped opcode 1: CAS.L r8,r9,@r0 = 0x2983 ---
        ! This opcode is dropped on J1 and must trap as general illegal.
        .word   0x2983

        ! --- dropped opcode 2: LDS r2,cpi_com = 0x4288 ---
        ! Coprocessor LDS instruction, dropped on J1, must also trap.
        ! (opcode taken from testmov3.s: "lds r2, cpi_com (4m88)")
        .word   0x4288

        ! restore original VBR
        ldc     r14, vbr

        ! check that both traps fired (counter must be 2)
        mov.l   _pcounter, r2
        mov.l   @r2, r1
        mov     #2, r3
        cmp/eq  r3, r1
        bf      _ill_fail           ! counter != 2 -> some traps missed -> FAIL

        bra     _pass               ! both traps fired -> test passed
        nop

_ill_fail:
        mov.l   _pfail, r0
        jmp     @r0
        nop

! Constant pool for the main test body (within PC-relative reach above)
        .align 4
_pvbr_tab:  .long _vbr_tab
_pcounter:  .long 0x00007800       ! scratch RAM (matches sim exc tests convention)
_pfail:     .long _fail

! ---- General-illegal exception handler ----
! SH-2 stack frame on entry: @r15 = faulting PC, @(4,r15) = saved SR.
! Increment the trap counter, advance saved PC by 2 to skip the 2-byte
! faulting instruction, then RTE.
_ill_handler:
        mov.l   _pcounter_h, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0             ! counter++
        mov.l   @r15, r0            ! load faulting PC from exception frame
        add     #2, r0
        mov.l   r0, @r15            ! advance saved PC past 2-byte illegal opcode
        rte
        nop

! Constant pool for the handler (within PC-relative reach of handler above)
        .align 4
_pcounter_h: .long 0x00007800

! Minimal VBR table: only slot 4 matters (general illegal instruction).
! SH-2 vectors: VBR + vector_number * 4; general illegal = vector 4 -> VBR+0x10
        .align 4
_vbr_tab:
        .long 0                     ! slot 0: power-on reset PC (unused)
        .long 0                     ! slot 1: power-on reset SR (unused)
        .long 0                     ! slot 2: manual reset PC (unused)
        .long 0                     ! slot 3: manual reset SR (unused)
        .long _ill_handler          ! slot 4: general illegal instruction

! ---- Pass/fail exit (same pattern as other testrom test files) ----
_pass:
        lds.l   @r15+, pr
        mov.l   _ppass_value, r0
        mov.l   _ppass_addr, r1
        mov.l   r0, @r1
        rts
        nop
        .align 4
_ppass_addr:  .long 0xABCD0000
_ppass_value: .long 0x00000025

_fail:
        mov.l   _pfail_value, r0
        mov.l   _pfail_value, r1
        bra     _fail
        nop
        .align 4
_pfail_value: .long 0x88888888

.end
