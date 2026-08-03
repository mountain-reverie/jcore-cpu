! mmupcprobe.S -- INDEPENDENT probe of the D-side TLB-fault restart PC.
!
! STATUS: GREEN, and WIRED INTO sim/mmu_sim.sh's default suite (run explicitly
! with: sim/mmu_sim.sh mmupcprobe "" 200us). It was RED at Result=0x020201
! before the restart PC was corrected to derive from the live ex_if_pc; it now
! reaches its exact q_expect of 0x00010101.
!
! WHY IT MUST STAY IN THE SUITE: it is the only guard that pins the normal
! (plain-load) restart arm to EXACTNESS rather than to "not broken". Other
! guards do fault on plain loads through the same restart path (mmufault.S:158,
! mmustale.S:89, mmuxlate.S:54) -- but only coarsely, i.e. they check that
! control flow survived and the value arrived, not WHERE the restart landed.
! (mmurestartpc.S and mmudrain.S fault on @Rn+ loads, so they do not exercise
! the plain-load shape at all.) While this probe was unwired, an off-by-N
! regression in the normal arm would have left the whole suite green. sim/tests/mmudspcprobe.S is its delay-slot analogue.
!
! It measured Defect 3 (D-side TLB-fault restart PC lands early). Unlike
! mmurestartpc.S, which can only report "too early", this probe reports HOW
! early -- and the answer is FOUR bytes, not two: BOTH instructions preceding
! the faulting access re-execute. mmurestartpc.S cannot see this because the
! slot at load_PC-4 in that test is a nop.
!
! Corroborated by VCD: on the fault, tlb_exc_pc latched the faulting PC while
! the RTL applied a +2 bias (so the shadowed ma_if_pc = faulting_PC - 2), and
! after the handler ex_if_pc resumed straight at SPC = tlb_exc_pc - 4 -- i.e.
! the resume does NOT "re-enter one slot ahead", as core/datapath.vhm used to
! claim. That mistaken belief was one of the two compounding -2 terms; the
! other was ma_if_pc's addressing-mode-dependent lag. Both are fixed by
! deriving the D-side restart from the live ex_if_pc (tlb_exc_pc = ex_if_pc+4).
!
! Deliberately does NOT reuse mmurestartpc.S's shape. Two differences that
! matter for attributing the effect:
!
!   1. The faulting access is a PLAIN `mov.l @r2, r12` -- NOT a post-increment
!      load. That removes the @Rn+ base-restore machinery from the experiment
!      entirely, so any duplicated side effect cannot be blamed on it.
!   2. THREE tripwires bracket the faulting access, so the probe reads out the
!      restart offset directly instead of only answering yes/no:
!         r6 -> two instructions before the load
!         r7 -> one instruction before the load
!         r8 -> one instruction after  the load
!
!   Result = (r6 << 16) | (r7 << 8) | r8.
!
!   0x010101  restart lands exactly on the load          (correct -- MEASURED)
!   0x010201  restart lands on load_PC-2 (one too early) (Defect 3 as claimed)
!   0x020201  restart lands on load_PC-4 (two too early)
!   r12 wrong -> the load itself did not land; fails early with 0x0BAD.
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

	! ---- stage everything the window needs ----
	mov.l	p_d0, r2		! base = unmapped data page
	mov.l	p_v0, r5		! expected loaded value
	mov.l	p_fc, r0		! non-vacuity baseline: fault count before
	mov.l	@r0, r11		! the window (delta checked in _verify)
	nop
	nop
	nop

	! ================= THE WINDOW ========================================
	! No memory traffic besides the single faulting load.
	mov	#0, r6
	mov	#0, r7
	mov	#0, r8
	nop
	nop
	add	#1, r6			! tripwire: two before the load
	add	#1, r7			! tripwire: one before the load
	mov.l	@r2, r12		! DMISS_R -- THE FAULT (no post-inc)
	add	#1, r8			! tripwire: one after the load
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
p_fc:		.long _fault_count

! ---------------------------------------------------------------------------
ENTRY(_verify)
	! The load must actually have landed.
	cmp/eq	r5, r12
	bt	1f
	mov.l	q_bad, r9
	bra	_fail
	nop
1:
	! Result = (r6 << 16) | (r7 << 8) | r8
	mov	r6, r9
	shll16	r9
	mov	r7, r0
	shll8	r0
	or	r0, r9
	or	r8, r9
	mov.l	q_expect, r0
	cmp/eq	r0, r9
	bt	7f
	bra	_fail			! r9 = composite, reported verbatim
	nop
7:
	! ---- NON-VACUITY: exactly ONE fault must have been taken. ----
	! _fault_count was wired but never read: if _dpage_0 were accidentally
	! mapped, no fault occurs, the composite still matches and the guard
	! PASSES VACUOUSLY.  Checked after the composite so the composite's
	! evidence distinguishes vacuity from a real restart-PC defect.
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
q_expect:	.long 0x00010101
q_mmucr:	.long 0xFF000010
q_bad:		.long 0x00000BAD
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
