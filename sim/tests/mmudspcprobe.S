! mmudspcprobe.S -- exactness probe for the DELAY-SLOT D-side TLB-fault
! restart PC.  The delay-slot analogue of mmupcprobe.S.
!
! WHY THIS EXISTS.  The D-side restart PC is derived from the live ex_if_pc
! with two arms (core/datapath.vhm):
!     normal      tlb_exc_pc := ex_if_pc + 4   -> SPC = faulting PC
!     delay slot  tlb_exc_pc := ex_if_pc + 2   -> SPC = branch PC
! mmupcprobe.S pins the NORMAL arm to exactness (it reads out the restart
! offset in units of instructions).  Nothing pinned the DELAY-SLOT arm: the
! existing delay-slot guards (mmudslot, mmuidslot, m8_ifetch_*) only confirm
! that control flow is not BROKEN, and every one of them has an idempotent
! instruction (nop / constant-pool load) ahead of the branch, so a restart that
! lands one or two instructions early is INVISIBLE to all of them.  On this
! core the original delay-slot defect was found only by exhaustive sweeps and
! missed by single-case tests, and the exhaustive I-side delay-slot sweep
! (m8_idslot_0-2) is rotted and runs nothing -- so this arm had no safety net
! at all.  This guard is that net.
!
! WHAT IT MEASURES.  A plain (NOT post-increment) faulting load placed in a
! `bra` delay slot, bracketed by NON-IDEMPOTENT tripwires so that a wrong
! restart is arithmetically visible instead of harmless:
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
!     0x00010101  restart lands on the DELAY SLOT (2 too late)
!   r12 wrong          -> fails early with 0x0BAD  (the load never landed)
!   r8 != 1            -> fails early with 0x0BAD8 (control flow went astray)
!
! HAZARD OBSERVED WHILE WRITING THIS (same one mmupcprobe.S documents): any
! intervening memory access -- INCLUDING a PC-relative literal load -- between
! the faulting access and the instruction under test rewrites the shadow
! registers and hides exactly these defects.  So everything the window needs is
! staged into registers BEFORE the window, the window itself contains no memory
! traffic besides the single faulting load, and all assertions are deferred to
! _verify well past it.
!
! STATUS: GREEN -- measured 0x00010100, its exact expectation.  Listed in
! sim/mmu_sim.sh's suite.
!
! NON-VACUITY, established by mutation rather than argued:
!   * The load lands (r12 == 0xD0000000 from an initially UNMAPPED page), so
!     the fault provably occurred and the handler provably ran.
!   * Injecting a -2 error into the delay-slot arm in core/datapath.vhm
!     (tlb_exc_pc := ex_if_pc instead of ex_if_pc + 2) turns this guard RED
!     with Result=0x00010200 -- it reads the injected offset out correctly --
!     while mmudslot AND mmuidslot both stay GREEN under the same mutation.
!     That is the coverage gap this guard exists to close, demonstrated.
!
! FINDING: this guard also PASSES on the PRE-fix RTL (the ma_if_pc-derived
! restart).  The delay-slot arm was therefore ALREADY correct; Defect 3 (the
! four-bytes-early restart) affected the NORMAL arm only.  The move to ex_if_pc
! is value-equivalent for the delay-slot case and changes behaviour only for
! the normal one.
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
	mov.l	@r2, r12		! DELAY SLOT: DMISS_R -- THE FAULT
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
