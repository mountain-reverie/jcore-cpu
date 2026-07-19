! mmunest_slotill.S -- S-I4b guard: a NESTED Slot-Illegal (an illegal instruction
! in a delay slot) taken while SR.RB=1. Even though g_dblflt injects RESET_CPU on
! illegal_instr while RB=1, next_op's event arm only accepts it when
! delay_slot='0', so in a delay slot the decoder takes the SLOT_ILLEGAL entry
! instead -- clobbering the first exception's SPC/SSR and re-entering the handler
! with flag==3 (Result=3). The fix lets an injected RESET_CPU override even a
! delay slot (PRIV_ARCH-gated next_op arm). Reboots to `start` (-> _done) once
! fixed. Modeled on mmudblflt.S; the nested fault is `bra; .word 0x0000`.
!
! (original mmudblflt header) -- S-I4 guard: a non-TLB exception taken while SR.RB=1 (the
! exception context -- SPC/SSR -- is already live from a prior, un-restored
! exception) must be a DEFINED, non-recoverable reset, NOT a silent
! SPC/SSR re-save that clobbers the first exception's context.
!
! See core/cpu.vhd's event_i_gated / g_dblflt generate: while dp_sr.rb='1', a
! nested General-Illegal-Instruction fault (or a real external Interrupt/Error
! event_i) is redirected to the SAME "Reset CPU" register-model-free entry
! real hardware cold-boot uses (decode_core's DEC_CORE_RESET op.code = Reset
! CPU, d8=0) -- PC <- mem[0] (= `start`), R15 <- mem[4], NO SPC/SSR/EXPEVT
! write. Reusing the proven cold-boot path is deliberate: every guard in this
! suite already exercises it correctly at time 0, so the double-fault path
! rides thoroughly-validated microcode instead of an untested one.
!
! Flow (single shared General-Illegal handler at VBR+0x100, dispatched by a
! memory-resident stage flag so it survives the eventual reboot):
!   stage 0 (flag=_flag==0, first boot): install VBR, set flag=1, take an
!     ILLEGAL INSTRUCTION at RB=0 -- the NEGATIVE CONTROL (single, non-nested
!     fault must enter the handler normally).
!   handler, flag==1: sanity-check SR.RB read back 1 (register-model entry
!     ran), mark neg_ctrl_pass=1, set flag=2, redirect SPC to `trigger_nested`
!     and RTE (back to RB=0 user code).
!   trigger_nested: take a SECOND illegal instruction (still a plain,
!     non-nested fault at RB=0 -- this is the OUTER fault of the nested pair).
!   handler, flag==2: we are now genuinely inside a handler (RB=1, just
!     entered by trigger_nested's fault). Set flag=3 (the reboot marker) and,
!     WITHOUT RTE-ing first, execute a THIRD illegal instruction directly --
!     this is the NESTED fault, taken while RB is already 1.
!     - FIXED core: S-I4 redirects this to Reset CPU -> full reboot -> PC
!       lands back at `start` with flag==3.
!     - BROKEN core (no fix): General Illegal re-dispatches normally,
!       clobbering SPC/SSR, and re-enters this SAME handler with flag still
!       ==3 (no reboot happened) -> falls into the explicit "flag==3 inside
!       the handler" arm, which is unreachable on a fixed core and writes a
!       deterministic FAIL.
!   start, flag==3 (reached only via the Reset-CPU reboot): confirm
!     neg_ctrl_pass==1 (single-fault path was unaffected) and write PASS.
!
! Non-vacuity: verified by temporarily inverting core/cpu.vhd's g_dblflt gate
! (forcing the nested fault down the normal, unprotected General-Illegal path)
! and confirming this guard then prints a deterministic "Test failed.
! Result=N" instead of hanging or silently passing -- see task-3 report.

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

        ! ---- Ensure RB=0 (bank 0) on every entry, including post-reboot. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _h_general_illegal - 0x100 (so VBR+0x100 = the shared
        ! handler). Re-set on every entry -- cheap and makes the reboot path
        ! not depend on VBR surviving reset (it doesn't: VBR is a plain
        ! register, cleared by the Reset-CPU op like everything else). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Dispatch on the memory-resident stage flag. ----
        mov.l   p_flag, r0
        mov.l   @r0, r1
        mov     #3, r2
        cmp/eq  r2, r1
        bt      _post_reboot

        mov     #0, r2
        cmp/eq  r2, r1
        bt      _stage0

        ! Any other flag value on entry to `start` is unexpected (we should
        ! only ever re-enter `start` via the flag==3 reboot).
        bra     _fail_marked
        nop

_stage0:
        ! ---- Negative control: a SINGLE, non-nested illegal instruction at
        ! RB=0 must enter the handler normally (single-fault path intact). ----
        mov.l   p_flag, r0
        mov     #1, r1
        mov.l   r1, @r0
        .word   0x0000                  ! illegal #1 (RB=0) -> handler_general_illegal
        bra     _fail_marked            ! must never fall through
        nop

ENTRY(trigger_nested)
        ! Outer fault of the nested pair: a plain fault at RB=0. Its handler
        ! entry (flag==2) is the one that, WITHOUT RTE-ing, takes the nested
        ! (RB=1) fault below.
        .word   0x0000                  ! illegal #2 (RB=0 here) -> handler_general_illegal
        bra     _fail_marked            ! must never fall through
        nop

_post_reboot:
        ! Reached only via the Reset-CPU reboot (PC <- mem[0] = start) fired
        ! by the nested (RB=1) fault. Confirm the negative control passed.
        mov.l   p_neg_ctrl, r0
        mov.l   @r0, r1
        mov     #1, r2
        cmp/eq  r2, r1
        bf      _fail_marked
        bra     _done
        nop

_fail_marked:
        mov.l   p_test_result, r0
        mov     #2, r9
        mov.l   r9, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _h_general_illegal - 0x100
p_flag:         .long _flag
p_neg_ctrl:     .long _neg_ctrl

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

        ! ---- Shared GENERAL_ILLEGAL handler at VBR+0x100. ----
        .balign 4
        .space 0x600, 0
        .balign 4
_h_general_illegal:                     ! = VBR + 0x100
        mov.l   Hp_flag, r0
        mov.l   @r0, r1

        mov     #1, r2
        cmp/eq  r2, r1
        bt      _h_flag1

        mov     #2, r2
        cmp/eq  r2, r1
        bt      _h_flag2

        ! flag==3 (or anything else) here means the handler was RE-ENTERED
        ! instead of the core rebooting -- i.e. the nested (RB=1) fault was
        ! NOT redirected to Reset CPU, so this is the S-I4 defect: SPC/SSR
        ! were silently clobbered by a second register-model save. FAIL.
        mov.l   Hp_test_result, r0
        mov     #3, r9
        mov.l   r9, @r0
        bra     _fail
        nop

_h_flag1:
        ! Negative control: this must be a normal, single-fault entry
        ! (RB 0->1 register-model transition). Sanity-check SR.RB==1.
        stc     sr, r3
        mov.l   Hp_rbbit, r4
        and     r4, r3
        tst     r3, r3
        bt      _h_ctrl_fail             ! RB read 0 -- register model didn't engage

        mov.l   Hp_neg_ctrl, r0
        mov     #1, r1
        mov.l   r1, @r0                  ! neg_ctrl_pass = 1

        mov.l   Hp_flag, r0
        mov     #2, r1
        mov.l   r1, @r0                  ! flag = 2

        mov.l   Hp_trigger_nested, r0
        .word   0x404E                   ! LDC r0, SPC  (resume at trigger_nested)
        rte
        nop

_h_ctrl_fail:
        mov.l   Hp_test_result, r0
        mov     #4, r9
        mov.l   r9, @r0
        bra     _fail
        nop

_h_flag2:
        ! Outer fault of the nested pair: we are genuinely inside a handler
        ! now (RB=1, just entered). Mark the reboot flag BEFORE taking the
        ! nested fault, then take it WITHOUT RTE-ing first.
        mov.l   Hp_flag, r0
        mov     #3, r1
        mov.l   r1, @r0                  ! flag = 3 (reboot marker)
        bra     _slotill_land             ! delayed branch at RB=1 ...
        .word   0x0000                    ! ... ILLEGAL in its DELAY SLOT -> nested SLOT_ILLEGAL at RB=1
_slotill_land:
        ! Only reached if the nested fault did NOT redirect to Reset CPU AND
        ! did NOT re-enter this handler either (shouldn't happen either way).
        mov.l   Hp_test_result, r0
        mov     #5, r9
        mov.l   r9, @r0
        bra     _fail
        nop

        .align 2
Hp_flag:            .long _flag
Hp_neg_ctrl:        .long _neg_ctrl
Hp_rbbit:           .long 0x20000000
Hp_trigger_nested:  .long trigger_nested
Hp_test_result:     .long TEST_RESULT_ADDRESS

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! Cross-reboot state lives here as ordinary writable .text-resident
        ! storage (not .data -- avoided so the guard doesn't depend on an
        ! idata-copy startup routine this minimal harness doesn't run).
        .align 2
_flag:      .long 0
_neg_ctrl:  .long 0
