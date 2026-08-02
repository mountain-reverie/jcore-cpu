! mmurestartpc.S -- the D-side TLB-fault restart PC is ONE INSTRUCTION EARLY.
!
! DEFECT 3 (PRE-EXISTING and INDEPENDENT of Defects 1 and 2 -- this guard fails
! IDENTICALLY with and without the Defect 2 fix; see the A/B below).
!
! On a D-side TLB fault the datapath latches the restart PC as
!     tlb_exc_pc := ma_if_pc + 2            (core/datapath.vhm, normal load)
! and the D-side exception entries compute
!     SPC := TLBPC - 4                      (spec/sh4/exceptions.toml, alu_y=4 SUB)
! so  SPC = ma_if_pc - 2 = faulting_instruction_PC - 2.
! Execution resumes AT SPC, so the instruction IMMEDIATELY PRECEDING the
! faulting access is re-executed after every D-side TLB fault.  This contradicts
! the stated intent in exceptions.toml ("SPC<-TLBPC-4 (faulting PC)").
!
! MEASURED (mmushadowld, load0 @ 0x104C, load1 @ 0x104E, VCD):
!   fault 1  tlb_exc_pc = 0x104E -> SPC = 0x104A  = the nop before load0
!   fault 2  tlb_exc_pc = 0x1050 -> SPC = 0x104C  = LOAD0 itself
! Fault 1 is harmless because a nop precedes the load.  Fault 2 re-executes
! load0, a post-increment load, which bumps its base a second time.
!
! WHY THE WHOLE EXISTING SUITE MISSES IT: every other guard happens to have a
! harmless (nop / idempotent) instruction in front of the faulting access, so
! re-executing it is invisible.  It only bites when the preceding instruction
! has an architectural side effect -- which is exactly the case in a TRAIN of
! post-increment loads (mmudrain.S Result=6, mmushadowld.S Result=0x21).
!
! THIS GUARD makes the side effect explicit and minimal: a single faulting @Rn+
! load preceded by `add #1, r7`.  r7 is the tripwire.
!   Result = (r7 << 8) | (r2 - page0),  expected 0x0104 (r7==1, base bumped once)
!   MEASURED 0x0204 -> r7 == 2, i.e. `add #1, r7` ran TWICE.
!   The base itself (0x04) is CORRECT, which rules out the Defect 1/2 machinery
!   and isolates the fault to the restart PC alone.
!
! A/B PROVING IT IS PRE-EXISTING (sim/mmu_sim.sh -n mmurestartpc "" 200us):
!   with    the Defect 2 fix : Test failed. Result=516  (0x204)
!   without the Defect 2 fix : Test failed. Result=516  (0x204)
! Identical, so Defect 2's fix neither causes nor masks this.
!
! NOTE: fixing this is NOT a one-liner to be done blind -- tlb_exc_pc is shared
! with the I-side (IMISS/IPROT use SEL_TLBPC with alu_y=0/ADD) and the
! delay-slot restart model was tuned by the exhaustive m8 sweeps.  The minimal
! candidate is the D-side-only pair of tlb_exc_pc assignments in datapath.vhm
! (normal +2 -> +4, delay-slot +0 -> +2), validated against m8_dside /
! m8_ifetch_* / m8_idslot_*.  Deliberately left UNFIXED here: this branch's
! scope was Defects 1 and 2.
!
#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define PAGE_SZ  0x1000

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

        ! start must be page-aligned: the map loop below walks it in PAGE_SZ
        ! steps (and see trap 1 in the header -- the range must not reach VA 0).
        .balign PAGE_SZ

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

        ! ---- VBR = _v_rpc - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Identity-map every code page: start .. _code_end. ----
        ! The body spans more than one page, so all of it (preamble, handler,
        ! verifier, literal pools) must be mapped BEFORE AT goes on -- otherwise
        ! the first fault's own handler fetch IMISSes and double-faults.
        mov.l   p_code_start, r2
        mov.l   p_code_end, r3
1:      mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov     r2, r0
        mov.l   p_code_flags, r1
        or      r1, r0                  ! PTEL = page | 0xC8 (kernel code, U clear)
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        mov.l   p_page_sz, r0
        add     r0, r2
        cmp/hs  r3, r2
        bf      1b

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- snapshot the fault count ----
        mov.l   p_fc, r0
        mov.l   @r0, r11

        ! ---- stage EVERYTHING the window needs (see the hazard note above) ----
        mov.l   p_d0, r2                ! base 0 = unmapped data page 0
        mov.l   p_d1, r3                ! base 1 = unmapped data page 1 (adjacent)
        mov.l   p_d0, r4                ! expected r2 afterwards = page0 + 4
        add     #4, r4
        mov.l   p_d1, r5                ! expected r3 afterwards = page1 + 4
        add     #4, r5
        nop
        nop
        nop

        ! ================= THE WINDOW ========================================
        ! ONE faulting load, immediately PRECEDED by an observable,
        ! NON-IDEMPOTENT instruction.  If the D-side restart PC is one
        ! instruction too early, `add #1, r7` is re-executed by the restart and
        ! r7 ends at 2 instead of 1.  No memory traffic in the window.
        mov     #0, r7
        nop
        nop
        add     #1, r7                  ! the tripwire: must run EXACTLY ONCE
        mov.l   @r2+, r12               ! DMISS_R on page0 -- the FAULT
        ! ====================================================================
        nop
        nop
        nop
        nop
        nop
        nop
        bra     _verify_R
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_rpc - 0x400
p_mmucr:        .long 0xFF000010
p_code_start:   .long start
p_code_end:     .long _code_end
p_code_flags:   .long 0x000000C8
p_page_sz:      .long PAGE_SZ
p_fc:           .long _fault_count
p_d0:           .long _dpage_R0
p_d1:           .long _dpage_R1

! ---------------------------------------------------------------------------
! Verification -- everything is deferred to here, on the far side of the window.
! ---------------------------------------------------------------------------
ENTRY(_verify_R)
        ! DIAG/ORACLE: r7 must be 1 (tripwire ran once) and r2 == page0+4.
        ! Result = (r7 << 8) | (r2 - page0).   Expected 0x0104.
        mov.l   q_d0, r0
        sub     r0, r2
        mov     r7, r9
        shll8   r9
        or      r2, r9
        mov.l   q_expect, r0
        cmp/eq  r0, r9
        bt      7f
        bra     _fail                   ! r9 = the composite, reported verbatim
        nop
7:
        ! ---- Disable AT before handing the result to the harness. ----
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov     #0, r9
        bra     _done
        nop

        .align 2
q_fc:           .long _fault_count
q_expect:       .long 0x00000104
q_mmucr:        .long 0xFF000010
q_d0:           .long _dpage_R0
q_d1:           .long _dpage_R1
q_v0:           .long 0xD0000000
q_v1:           .long 0xD1111111

#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: keep the fail code loud
        bf      1f                      ! (PASS now requires TEST_PASS_MAGIC, so 0
        mov     #0x7F, r9               !  reports as Result=0, not as PASS.)
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- VA-driven handler at VBR+0x400 (all six TLB fault kinds) ----
        ! Runs with SR.RB=1, so its bank-1 scratch does not touch the leg's
        ! bank-0 registers.
        .balign 4
        .space 0x400, 0
        .balign 4
_v_rpc:
        .word   0x0153                  ! STC PTEH, r1 -- HW-captured faulting VPN
        mov.l   Hpagemask, r0
        and     r0, r1                  ! r1 = page base
        ! Layout contract: anything below the data pool is code/stub and must be
        ! installed with U=0 -- 0xE8 (U=1) there makes a kernel fetch fault
        ! forever under SMEP.
        mov.l   Hdbase, r0
        cmp/hs  r0, r1                  ! T = (page >= data pool)
        bt      1f
        mov.l   Hcflags, r0             ! code/stub page: 0xC8 (U clear)
        bra     2f
        nop
1:      mov.l   Hflags, r0              ! data page: 0xE8
2:      or      r1, r0                  ! PTEL = page | flags
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        mov.l   Hcount, r0              ! non-vacuity: count this fault
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        .word   0x0078                  ! LDTLB.RN -- install + return atomically
_h_fail_spin:
        bra     _h_fail_spin
        nop
        .align 2
Hpagemask:      .long 0xFFFFF000
Hflags:         .long 0x000000E8
Hcflags:        .long 0x000000C8
Hdbase:         .long _dpage_R0
Hcount:         .long _fault_count

        .balign 4
ENTRY(_fault_count)
        .long 0

        .balign 4
ENTRY(_code_end)                        ! everything above is identity-mapped code

! ======================= unmapped region starts here =======================
        .balign PAGE_SZ
_dpage_R0:  .long 0xD0000000
            .space PAGE_SZ - 4, 0

        .balign PAGE_SZ
_dpage_R1:  .long 0xD1111111
            .space PAGE_SZ - 4, 0

#endif
