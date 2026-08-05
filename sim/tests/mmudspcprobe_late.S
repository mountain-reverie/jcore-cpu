! mmudspcprobe_late.S -- Defect 7 reproducer: DELAY-SLOT D-side TLB-fault
! restart PC for a LATE-ACCESS instruction (access launches in slot 1, not
! slot 0).  Byte-for-byte the same harness as mmudspcprobe.S -- same
! tripwires, same composite encoding, same non-vacuity check -- with exactly
! one change: the delay-slot instruction is `mov.l @r2+,r12` (MOV.L @Rm+,Rn)
! instead of the slot-0 `mov.l @r2,r12`.  Per decode/gen-go/spec/mov.toml,
! MOV.L @Rm+,Rn is two slots: slot 0 computes/writes back Rm+4 (no memory
! access), slot 1 is the READ that can fault.  mmudspcprobe.S's slot-0 load
! PASSES; this guard's slot-1 load is expected to FAIL.  The only variable
! between the two files is which slot carries the access -- that pairing IS
! the evidence for Defect 7.
!
! DEFECT 7 (open, unfixed).  On a D-side TLB fault taken in a branch delay
! slot, the restart lands on the delay-slot instruction itself instead of
! backing up to the branch -- but ONLY when the faulting access launches in
! a slot AFTER slot 0.  Hypothesis (strongly supported, not yet proven at
! the RTL): ma_dslot is shadowed at the ACCESS-LAUNCH point, so an
! instruction whose access launches after slot 0 sees delay_slot already
! deasserted and takes the "normal" restart arm (tlb_exc_pc := ex_if_pc + 4,
! landing on the faulting instruction) instead of the delay-slot arm
! (tlb_exc_pc := ex_if_pc + 2, landing on the branch).  See
! decode/gen-go/internal/faultgen/emit.go's lateAccess() and the m8_dsdslot_0
! Defect 7 writeup in sim/mmu_sim.sh for the exhaustive 26-case classification
! (MOV.{B,W,L} @Rm+,Rn, CAS.L Rm,Rn,@R0, and MAC.{L,W} @Rm+,@Rn+ are the five
! affected forms; all 22 slot-0-access forms are unaffected).
!
! THIS GUARD IS EXPECTED RED.  It is NOT wired into sim/mmu_sim.sh's active
! run list -- see the park comment there for the exact one-command
! reproduction.  Do not "fix" this file to make it pass; it exists to
! reproduce Defect 7 until the RTL is fixed, at which point it moves into
! the run list.
!
! WHAT IT MEASURES (identical scheme to mmudspcprobe.S):
!
!   r7  `add #1, r7` at branch_PC-4   -- expect 1; 2 => restart was 4 too early
!   r6  `add #1, r6` at branch_PC-2   -- expect 1; 2 => restart was 2 too early
!   r13 `add #1, r13` at branch_PC+4  -- POISON, immediately after the delay
!                                        slot.  The branch is unconditional, so
!                                        this can only run if the restart landed
!                                        ON THE DELAY SLOT (2 too late), which
!                                        re-executes the load and then falls
!                                        through.  Expect 0.
!   r8  `add #1, r8` at the branch target -- expect 1 (control flow arrived).
!
!   Result = (r7 << 16) | (r6 << 8) | r13
!     0x00010100  restart lands exactly on the BRANCH            (correct)
!     0x00010200  restart lands on branch_PC-2  (2 too early)
!     0x00020200  restart lands on branch_PC-4  (4 too early)
!     0x00010101  restart lands on the DELAY SLOT (2 too late) -- DEFECT 7
!   r12 wrong          -> fails early with 0x0BAD  (the load never landed)
!   r8 != 1            -> fails early with 0x0BAD8 (control flow went astray)
!
! HAZARD (same one mmupcprobe.S and mmudspcprobe.S document): any
! intervening memory access -- INCLUDING a PC-relative literal load --
! between the faulting access and the instruction under test rewrites the
! shadow registers and hides exactly these defects.  So everything the
! window needs is staged into registers BEFORE the window, the window itself
! contains no memory traffic besides the single faulting post-increment
! load, and all assertions are deferred to _verify well past it.
!
#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define PAGE_SZ 0x1000

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
_sim_instr_end:	.long 0

	.text
	.balign PAGE_SZ

ENTRY(start)
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

	! ---- Ensure RB=0 (bank 0). ----
	stc	sr, r0
	mov.l	p_rbclear, r1
	and	r1, r0
	ldc	r0, sr
	nop
	nop
	nop

	! ---- VBR = _v_pc - 0x400. ----
	mov.l	p_vbr_val, r0
	.word	0x402E			! LDC r0, VBR

	! ---- Identity-map the code region BEFORE enabling AT. ----
	mov.l	p_code_start, r2
	mov.l	p_code_end, r3
1:	mov	r2, r0
	.word	0x405E			! LDC r0, PTEH
	mov	r2, r0
	mov.l	p_code_flags, r1
	or	r1, r0
	.word	0x406E			! LDC r0, PTEL
	mov	#0, r0
	.word	0x407E			! LDC r0, ASIDR
	.word	0x0038			! LDTLB
	mov.l	p_page_sz, r0
	add	r0, r2
	cmp/hs	r3, r2
	bf	1b

	! ---- Enable AT. ----
	mov.l	p_mmucr, r0
	mov	#1, r1
	mov.l	r1, @r0

	! ---- stage everything the window needs (no memory traffic inside) ----
	mov.l	p_d0, r2		! base = unmapped data page
	mov.l	p_v0, r5		! expected loaded value
	mov.l	p_fc, r0		! non-vacuity baseline: fault count before
	mov.l	@r0, r11		! the window (delta checked in _verify)
	nop
	nop
	nop

	! ================= THE WINDOW ========================================
	! No memory traffic besides the single faulting delay-slot load, and no
	! PC-relative literal loads -- see the hazard note in the header.
	mov	#0, r6
	mov	#0, r7
	mov	#0, r8
	mov	#0, r13
	nop
	nop
	add	#1, r7			! tripwire: branch_PC - 4
	add	#1, r6			! tripwire: branch_PC - 2
	bra	_dsl_target		! THE BRANCH -- the restart target
	mov.l	@r2+, r12		! DELAY SLOT: MOV.L @Rm+,Rn -- access is
					! SLOT 1 (Defect 7 late-access form) --
					! DMISS_R -- THE FAULT
	add	#1, r13			! POISON at branch_PC + 4 (unreachable)
	nop
	nop
_dsl_target:
	add	#1, r8			! branch target reached exactly once
	! ====================================================================
	nop
	nop
	nop
	nop
	nop
	nop
	bra	_verify
	nop

	.align 2
p_rbclear:	.long 0xDFFFFFFF
p_vbr_val:	.long _v_pc - 0x400
p_fc:		.long _fault_count
p_mmucr:	.long 0xFF000010
p_code_start:	.long start
p_code_end:	.long _code_end
p_code_flags:	.long 0x000000C8
p_page_sz:	.long PAGE_SZ
p_d0:		.long _dpage_0
p_v0:		.long 0xD0000000

! ---------------------------------------------------------------------------
ENTRY(_verify)
	! The delay-slot load must actually have landed.
	cmp/eq	r5, r12
	bt	1f
	mov.l	q_bad, r9
	bra	_fail
	nop
1:
	! Control flow must have reached the branch target exactly once.
	mov	#1, r0
	cmp/eq	r0, r8
	bt	2f
	mov.l	q_bad8, r9
	bra	_fail
	nop
2:
	! Result = (r7 << 16) | (r6 << 8) | r13
	mov	r7, r9
	shll16	r9
	mov	r6, r0
	shll8	r0
	or	r0, r9
	or	r13, r9
	mov.l	q_expect, r0
	cmp/eq	r0, r9
	bt	7f
	bra	_fail			! r9 = composite, reported verbatim
	nop
7:
	! ---- NON-VACUITY: exactly ONE fault must have been taken. ----
	! _fault_count was wired but never read: with _dpage_0 accidentally
	! mapped no fault occurs, the composite still matches, and the guard
	! PASSES VACUOUSLY.  This is the check the header's coverage claim rests
	! on (a correct loaded value proves nothing about faulting).
	mov.l	q_fc, r0
	mov.l	@r0, r1
	sub	r11, r1
	mov	#1, r0
	cmp/eq	r0, r1
	bt	8f
	mov	#0x40, r9		! distinct code: vacuity / wrong fault count
	bra	_fail
	nop
8:
	! ---- Disable AT before handing the result to the harness. ----
	mov.l	q_mmucr, r0
	mov	#0, r1
	mov.l	r1, @r0

	mov	#0, r9
	bra	_done
	nop

	.align 2
q_expect:	.long 0x00010100
q_mmucr:	.long 0xFF000010
q_bad:		.long 0x00000BAD
q_bad8:		.long 0x0000BAD8
q_fc:		.long _fault_count

#endif

ENTRY(_done)
	mov.l	p_test_result, r0
	mov.l   p_test_result_pass, r9
	mov.l	r9, @r0
	bra	_done
	nop
ENTRY(_fail)
	mov.l	p_test_result, r0
	tst	r9, r9
	bf	1f
	mov	#0x7F, r9
1:
	mov.l	r9, @r0
	bra	_fail
	nop
	.align 2
p_test_result:	.long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

	! ---- VA-driven TLB-fault handler at VBR+0x400 ----
	.balign 4
	.space 0x400, 0
	.balign 4
_v_pc:
	.word	0x0153			! STC PTEH, r1
	mov.l	Hpagemask, r0
	and	r0, r1			! r1 = page base
	mov.l	Hdbase, r0
	cmp/hs	r0, r1
	bt	1f
	mov.l	Hcflags, r0		! code page: 0xC8 (U clear)
	bra	2f
	nop
1:	mov.l	Hflags, r0		! data page: 0xE8
2:	or	r1, r0
	.word	0x406E			! LDC r0, PTEL
	mov	#0, r0
	.word	0x407E			! LDC r0, ASIDR
	mov.l	Hcount, r0		! non-vacuity: count the fault
	mov.l	@r0, r1
	add	#1, r1
	mov.l	r1, @r0
	.word	0x0078			! LDTLB.RN -- install + return
_h_fail_spin:
	bra	_h_fail_spin
	nop
	.align 2
Hpagemask:	.long 0xFFFFF000
Hflags:		.long 0x000000E8
Hcflags:	.long 0x000000C8
Hdbase:		.long _dpage_0
Hcount:		.long _fault_count

	.balign 4
ENTRY(_fault_count)
	.long 0

	.balign 4
ENTRY(_code_end)

	! ======================= unmapped region =======================
	.balign PAGE_SZ
_dpage_0:	.long 0xD0000000
	.space PAGE_SZ - 4, 0

#endif
