! mmuidorder.S -- MEASUREMENT guard: an OLDER D-side TLB fault held in
! texc_req, and a YOUNGER deferred I-fetch fault (if_fault), pending at the
! SAME dispatch boundary. Is the older access dropped?
!
! ---- Why this file exists ----
!
! A 2026-08-08 review of `decode/decode_core.vhm` observed that `texc_ack` is
! asserted purely from `slot`, `texc_req`, `id_stall` and `instr_seq_zero`:
!
!     texc_ack <= '1' when PRIV_ARCH and slot = '1' and texc_req = '1'
!                          and this'register.id_stall = '0'
!                          and this'register.instr_seq_zero = '1'
!
! It does NOT check which arm of `next_op` actually won. In `next_op`'s priority
! list the deferred I-side arms sit ABOVE the held D-side arms:
!
!     system_op(TLB_IMISS)   when PRIV_ARCH and if_fault = '1' and if_fault_prot = '0'
!     system_op(TLB_DMISS_R) when PRIV_ARCH and texc_req = '1' and texc_kind_held = DMISS_R
!
! so when both are live at one boundary the I-side fault is dispatched while
! `texc_ack` clears the held D-side request anyway. The review's claim was that
! the D-side page fault is thereby DROPPED: the faulting load is never
! restarted and its destination register keeps stale data, i.e. user code
! silently reads wrong memory instead of taking a page fault.
!
! ---- How the construction was found (do not "simplify" it) ----
!
! A temporary RTL probe
!     assert not (texc_ack = '1' and texc_req = '1' and if_fault = '1')
! was added to decode_core and EVERY guard image in sim/tests was run against
! it. It fired in exactly one existing test, `m8_dsdslot_0` (twice), and
! nowhere else -- notably NOT in `mmufaultage.S`, whose DMISS_R-then-IMISS
! shape looks like it should hit but whose two faults do not land on the same
! boundary.
!
! The FIRST version of this guard was also probe-silent: putting the older load
! in the delay slot of a branch whose target page is unmapped does NOT produce
! the coincidence. That version passed while measuring nothing, which is
! exactly the vacuous-guard failure this branch keeps running into. The shape
! that does hit was read off `m8_dsdslot_0`'s instruction trace at the moment
! the probe fired:
!
!     IF 0x100FFE  JMP @R11          <- branch at the LAST halfword of a page
!     IF 0x101000  MOV #imm, R0      <- its DELAY SLOT, on the NEXT page
!     PROBE2 fires
!
! The delay slot lands on a different page from the branch. So this guard puts
!
!     0x0FFC   mov.l  @r13, r12      ! data page 3 UNMAPPED -> DMISS_R  (OLDER)
!     0x0FFE   jmp    @r1            ! branch, last halfword of page 0
!     0x1000   nop                   ! DELAY SLOT, page 1 UNMAPPED -> IMISS (YOUNGER)
!
! The load's D-side fault is held in texc_req across the branch; the delay
! slot's fetch fault is deferred and reaches its dispatch boundary while the
! held request is still live. That is the coincidence.
!
! REQUIRED whenever this file changes: re-add the probe above and confirm it
! still fires here. A green run of this guard means nothing if the coincidence
! it exists to create has stopped happening.
!
! The load's base (r13) and destination (r12) are DISJOINT on purpose -- the
! opposite of `mmufaultage.S`'s deliberately non-idempotent choice. Here the
! question is not "did a wrong commit destroy the operand" but the simpler "did
! the load ever run at all": r12 is preloaded with a sentinel, so if the older
! load is dropped and never restarted it keeps that sentinel, and if it is
! restarted after its fault is serviced it holds the seeded word.
!
! ---- Handlers ----
!
! One stub at VBR+0x400: on this core ALL SIX TLB fault kinds vector there and
! differ only by EXPEVT (see `mmufaultage.S`). It logs the faulting page (TEA
! masked to its VPN) and installs an identity mapping for it.
!
! The log records TEA, NOT EXPEVT. `mmufaultage.S` records that `STC EXPEVT`
! was measured returning 0 in this .org-based VMA-0 layout for reasons that
! were never understood; TEA is read successfully by that same handler, and
! here it discriminates the two faults perfectly anyway -- 0x1000 is the I-side
! fetch fault, 0x3000 is the D-side load fault. Nothing needs EXPEVT.
!
! ---- Result codes ----
!   0  pass
!   1  NO fault at all -- the race never happened. ANTI-VACUITY.
!   2  no log entry for page 3 -- the OLDER D-side fault was never delivered.
!      This is the review's predicted signature.
!   3  no log entry for page 1 -- the YOUNGER I-side fault never fired, so the
!      coincidence under test did not occur and check 4 proves nothing.
!   4  r12 != the seeded data word. INSTRUCTION LOST: the older load was
!      dropped and never restarted. The primary check.
!   8  fault log full -- the run is not converging (a handler is re-faulting
!      forever). Surfaces a livelock as a result code, not a stop-time timeout.
!
! 2 and 4 are deliberately distinct: "the fault was never delivered" and "the
! access never produced its value" are different observations, and a fix for
! one is not automatically a fix for the other.
!
! ---- What this guard LOCKS, and what is still OPEN ----
!
! LOCKED (checks 1-3). Against the pristine tree this guard reports
! **Result=2**: the older D-side fault is NEVER DELIVERED. `texc_ack` clears the
! held request at a boundary whose exception was not the D-side one, and the
! page fault simply vanishes.
!
! The mechanism is NOT the one the review predicted, and the difference was
! measured, not argued. The review blamed the younger I-side arm of `next_op`
! winning above the held D-side arms. A/B says otherwise: with the I-side arm
! change REVERTED but the `event_wins` qualification kept, this guard is GREEN.
! What actually drops the fault here is an ASYNCHRONOUS EVENT arm winning the
! boundary while `texc_ack` fires regardless. So the fix that this guard locks
! is the `event_wins` qualification of `texc_ack` / `texc_defer_cap_o`.
!
! The `and texc_req = '0'` on the two if_fault arms is kept as well, but it is
! a SEPARATE, defensive change that NO guard currently exercises: a probe
! confirmed the I-side-arm coincidence is reachable (it fires in
! m8_dsdslot_0), so the hazard the review described is real, but nothing yet
! turns red without that term. Treat it as unguarded until something does.
! Do not cite this file as evidence for it.
!
! NOTHING IS LOST. With the fix, check 4 passes: the older load is restarted
! after its fault is serviced and lands its value in r12. Delivery ordering was
! the whole defect.
!
! ---- A retracted "residual defect", and the reason it is worth recording ----
!
! An earlier revision of this file reported a SECOND, open defect: that even
! after the fix the older load re-executed but never landed its value
! (Result=4). That was WRONG, and it was wrong because of a bug in THIS FILE,
! not in the RTL. The race instruction is hand-assembled, and it was written
!
!     .word 0x6DD2      ! "MOV.L @R13, R12"
!
! 0x6DD2 is `MOV.L @R13, R13` -- MOV.L @Rm,Rn is 0110 nnnn mmmm 0010, so
! n=12,m=13 is 0x6CD2. The load was writing r13, r12 kept its sentinel, and the
! guard dutifully reported the older access as lost. Two RTL probes were spent
! chasing it (the w-port squash and the base-restore arm, both innocent, both
! now known-good) before the encoding was checked.
!
! The lesson is specific and worth keeping: a hand-assembled `.word` is an
! UNCHECKED assertion about the hardware. The assembler validates nothing here.
! When a guard reports a defect that the RTL cannot explain, re-derive every
! hand-written opcode from its encoding table BEFORE probing the RTL.
!
! ---- Non-vacuity (MEASURED 2026-08-08, not reasoned) ----
! Against the PRISTINE tree (decode_core without the event_wins qualification)
! this guard reports **Result=2**. Each of the three live checks was then also
! mutated independently against the FIXED tree, and each reported its OWN code:
!
!   | mutation                                   | result |
!   | pre-map page 3 (the load cannot fault)     |   2    |
!   | pre-map page 1 (the delay slot cannot fault)|  3    |
!   | seed page 3 with a different value         |   4    |
!
! The last one is what proves check 4 reads the load's actual result rather
! than a constant -- and, given the encoding bug above, that it reads the right
! REGISTER. Re-run all three after any change to the construction.
!
! Both mutation rounds must be run WITHOUT `mmu_sim.sh -n`. `-n` reuses the
! existing build and silently skips RTL recompilation; a first attempt at these
! three ran against a stale pristine build and produced 2/3/2, which looks
! plausible and is meaningless.
!
! Layout (absolute VAs via .org in the VMA-0 image, like mmufaultage.S):
!   Page 0 (0x0000-0x0FFF): identity-mapped code, handler, literals, log.
!   Page 1 (0x1000-0x1FFF): UNMAPPED -- the delay slot and the branch target.
!   Page 3 (0x3000-0x3FFF): UNMAPPED -- the load's data page, holds the seed.
!
! PTEL flag bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G
! bit1=STALE bit0=V. Kernel code/data: W|X|C = 0xC8 (matching mmufaultage.S).
!
! The handler is entered with SR.RB=1 and uses only r0-r7 (bank 1); r9 and
! r11-r14 are non-banked and carry state across faults untouched.
!
! J4 overlay opcodes (the assembler does not know these forms):
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS, and _fail clamps r9==0 to
! 0x7F so an un-set fail code is never mistaken for PASS.
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

        ! Stay in .vect (linker VMA 0) so .org below places code at ABSOLUTE VAs.

        .org 0x0200
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0. REQUIRED: the I-side TLB fault path is gated on
        !      SR.RB='0' (core/cpu.vhd). With RB=1 (reset default) I-fetches
        !      bypass the TLB and page 1 never IMISSes. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _vbase. All six TLB fault kinds vector to VBR+0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Fault log: empty (plain P0 stores, AT still off). ----
        mov.l   p_log_ptr, r0
        mov.l   p_log_base, r1
        mov.l   r1, @r0

        ! ---- Map page 0 identity, W|X|C (no U: kernel fetch, SMEP). ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. Pages 1 and 3 are deliberately NOT mapped. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Operands for the race. r13 = the unmapped data page, r12 = the
        !      sentinel that survives iff the load is never restarted, r14 =
        !      where page 1 bounces back to, r1 = the branch target. All are
        !      non-banked, so the handler (bank 1, r0-r7) cannot disturb them.
        !      Loaded BEFORE entering page 0's tail: no memory access may sit
        !      between them and the race. ----
        mov.l   c_data_va, r13          ! 0x00003000, unmapped -> DMISS_R
        mov     #0x55, r12              ! sentinel
        mov.l   p_check, r14            ! where page 1 jumps back to
        mov.l   c_target_va, r1         ! 0x00001004, on unmapped page 1

        ! ---- Enter the race at 0x0FFC via jmp, so 0x0FFC is a branch TARGET
        !      (not a delay slot) and the sequence runs 0x0FFC, 0x0FFE, 0x1000.
        !      Use r2 for the entry target: r1 must already hold the race's own
        !      branch target when 0x0FFE executes. ----
        mov.l   c_race_va, r2
        jmp     @r2
        nop

        ! Unreachable unless nothing faulted at all.
        mov     #7, r9
        mov.l   p_fail, r0
        jmp     @r0
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _vbase
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C8        ! PA 0x0000 | W|X|C
c_data_va:      .long 0x00003000        ! page 3, unmapped -> DMISS_R (OLDER)
c_target_va:    .long 0x00001004        ! branch target, on unmapped page 1
c_race_va:      .long 0x00000FFC        ! the load, 3rd-from-last halfword of page 0
p_check:        .long _check
p_log_ptr:      .long _log_ptr
p_log_base:     .long _log
p_fail:         .long _fail

        ! ================= verification, back on page 0 =================
        .balign 4
_check:
        ! ---- AT off; everything below is P0 identity. ----
        mov.l   k_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! (1) ANTI-VACUITY: at least one fault was taken.
        mov.l   k_log_ptr, r0
        mov.l   @r0, r1
        mov.l   k_log_base, r2
        cmp/eq  r1, r2
        bf      1f
        mov     #1, r9
        bra     _bail
        nop
1:
        ! (2) the OLDER D-side fault must have been delivered at all.
        mov.l   k_page3, r4
        bsr     _log_find               ! r0 = 1 if r4 present in the log
        nop
        tst     r0, r0
        bf      2f
        mov     #2, r9
        bra     _bail
        nop
2:
        ! (3) the YOUNGER I-side fault must have fired, or the coincidence
        !     under test never happened and (4) proves nothing.
        mov.l   k_page1, r4
        bsr     _log_find
        nop
        tst     r0, r0
        bf      3f
        mov     #3, r9
        bra     _bail
        nop
3:
        ! (4) NOT ASSERTED -- SEE THE HEADER. The older load STILL does not
        !     land its value here (measured r12 = 0x55, the sentinel). That is
        !     a SECOND, separate defect from the delivery-ordering one this
        !     guard locks, and it is OPEN. Re-enable by deleting the `bra 4f`
        !     below; expect Result=4 until the write-back path is fixed.
        mov.l   k_dataword, r4
        cmp/eq  r4, r12
        bt      4f
        mov     #4, r9
        bra     _bail
        nop
4:
        mov     #0, r9
        mov.l   k_done, r0
        jmp     @r0
        nop

_bail:
        mov.l   k_fail, r0
        jmp     @r0
        nop

        ! ---- _log_find: r4 = value to find. Returns r0 = 1 if present.
        !      Clobbers r0/r2/r3/r5. Lives in page 0, so it cannot fault. ----
        .balign 4
_log_find:
        mov.l   k_log_ptr, r0
        mov.l   @r0, r5                 ! r5 = write pointer (end)
        mov.l   k_log_base, r2          ! r2 = cursor
        mov     #0, r0
1:      cmp/hs  r5, r2                  ! cursor >= end -> done
        bt      2f
        mov.l   @r2, r3
        cmp/eq  r3, r4
        bf      3f
        mov     #1, r0                  ! found
        bra     2f
        nop
3:      add     #4, r2
        bra     1b
        nop
2:      rts
        nop

        .align 2
k_mmucr:        .long 0xFF000010
k_fail:         .long _fail
k_done:         .long _done
k_log_ptr:      .long _log_ptr
k_log_base:     .long _log
k_page1:        .long 0x00001000
k_page3:        .long 0x00003000
k_dataword:     .long 0x5A5AC3C3

        ! ---- Report epilogue. MUST live in PAGE 0. ----
ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

        ! ===================== Exception vectors =====================
        .org 0x0600
_vbase:
        .space 0x400, 0

        .org 0x0A00
_v_tlbmiss:                             ! _vbase + 0x400 -- ALL TLB fault kinds
        bra     _h_tlb
        nop

        ! ---- Common handler. Entered with SR.RB=1, so r0-r7 here are BANK 1
        !      and the interrupted code's r11-r14 (bank 0) are untouched.
        !      Logs the faulting page and installs an identity mapping for it,
        !      which serves both the I-side (page 1) and D-side (page 3)
        !      faults. Does NOT touch ASIDR beyond the 0 it installs with. ----
        .org 0x0A60
_h_tlb:
        mov.l   Htea_addr, r0
        mov.l   @r0, r2                 ! r2 = TEA
        mov.l   Hvpn_mask, r3
        and     r3, r2                  ! r2 = VPN base -- the faulting page

        mov.l   Hlog_ptr, r1
        mov.l   @r1, r5
        mov.l   Hlog_end, r3
        cmp/hs  r3, r5                  ! log full -> the run is not converging
        bf      1f
        mov     #8, r9
        mov.l   Hfail, r0
        jmp     @r0
        nop
1:
        mov.l   r2, @r5                 ! log the faulting page
        add     #4, r5
        mov.l   r5, @r1

        mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   Hptel_flags, r3
        mov     r2, r0
        or      r3, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        rte                             ! PC <- SPC (hardware restart PC)
        nop

        .align 2
Htea_addr:      .long 0xFF00000C
Hvpn_mask:      .long 0xFFFFF000
Hptel_flags:    .long 0x000000C8
Hlog_ptr:       .long _log_ptr
Hlog_end:       .long _log_end
Hfail:          .long _fail

        ! ---- Fault log, in page 0 (mapped, writable). ----
        .org 0x0E80
_log_ptr:       .long 0
_log:           .rept 16
                .long 0
                .endr
_log_end:

        ! ================= THE RACE, at the tail of page 0 =================
        ! 0x0FFC  the OLDER load: its data page (3) is unmapped -> DMISS_R,
        !         held in texc_req across the branch below.
        ! 0x0FFE  the branch, in the LAST halfword of page 0, so its delay
        !         slot falls on page 1.
        ! 0x1000  the delay slot, on unmapped page 1 -> deferred IMISS. Its
        !         dispatch boundary is where the held D-side request is still
        !         live -- the coincidence under test.
        .org 0x0FFC
        .word   0x6CD2                  ! MOV.L @R13, R12   (r13 = 0x3000)
                                        ! 0110 nnnn mmmm 0010, n=12 m=13.
                                        ! NOT 0x6DD2 -- that is @R13,R13, which
                                        ! silently made an earlier revision of
                                        ! this guard report a bogus Result=4.
        .word   0x412B                  ! JMP @R1           (r1  = 0x1004)

        ! ---- Page 1 (UNMAPPED). 0x1000 is the delay slot; 0x1004 is the
        !      branch target, which bounces back to _check on page 0. ----
        .org 0x1000
        nop                             ! delay slot
        nop
        jmp     @r14                    ! r14 = _check
        nop

        ! ---- Page 3 (UNMAPPED): the load's data. ----
        .org 0x3000
        .long   0x5A5AC3C3              ! r12 must end up holding this

        .org 0x3100

#endif  ! CONFIG_PRIV_ARCH
