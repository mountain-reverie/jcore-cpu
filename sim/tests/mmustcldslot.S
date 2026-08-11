! mmustcldslot.S -- Task 14: is STC.L GBR,@-Rn restart-safe when planted in a
! branch delay slot and its store faults?  Modeled directly on
! mmudspcprobe_late.S (same harness shape, same tripwires, same non-vacuity
! check), but for a STORE with pre-decrement addressing instead of a
! post-increment LOAD.
!
! MICROCODE FINDING (decode/gen-go/spec/system.toml): STC.L GBR,@-Rn is a
! SINGLE slot -- alu_y=4/arith=SUB computes Rn-4 on ZBUS, ma_op=WRITE fires in
! that same slot, xbus=Rn, ybus=GBR.  STS.L MACH/MACL/PR,@-Rn (which passes on
! the m8 axis) have the IDENTICAL slot shape: same alu_y/arith/ma_addy/ma_data/
! ma_op/ma_size fields, only the ybus source differs (MACH/MACL/PR vs GBR).
! So STC.L GBR carries no extra microop or slot relative to the STS.L forms
! that are known to restart correctly -- there is no structural reason for it
! to differ. This guard measures whether that holds in the RTL rather than
! assuming it from the spec.
!
! WHAT IT MEASURES:
!   Rn (r2) is pre-loaded with (_dpage_0 + 4). The delay-slot instruction is
!   `stc.l gbr, @-r2`, so the store targets _dpage_0 (cold, unmapped -> DMISS_W)
!   and, if the auto-decrement applies exactly once, r2 ends at _dpage_0
!   (initial - 4).
!     initial - r2 == 4  -> correct (decrement applied exactly once)
!     initial - r2 == 8  -> DEFECT: decrement applied TWICE (re-executed slot
!                            re-applied over an already-decremented restore)
!     initial - r2 == 0  -> DEFECT: decrement LOST (restore overwrote Rn with
!                            the pre-fault value and it was never reapplied)
!     anything else      -> some other corruption
!   The stored word at _dpage_0 must equal the GBR sentinel loaded before the
!   window -- proves the STORE itself (not just the address arithmetic)
!   completed correctly after restart.
!
!   Same r6/r7/r8/r13 tripwire scheme as mmudspcprobe_late.S:
!     r7  branch_PC-4 tripwire -- expect 1
!     r6  branch_PC-2 tripwire -- expect 1
!     r13 POISON at branch_PC+4 -- expect 0 (nonzero => restart landed 2 too
!         late, ON the delay slot, re-executing it and falling through)
!     r8  branch target reached -- expect 1
!   Result = (r7<<16)|(r6<<8)|r13; correct = 0x00010100 (same encoding as
!   mmudspcprobe_late.S).
!
! HAZARD (same as mmudspcprobe_late.S): no memory traffic inside the window
! besides the single faulting store -- an intervening access (including a
! PC-relative literal load) rewrites the shadow restore registers and hides
! exactly the defect this guard is built to catch.
!
! NON-VACUITY: baseline _fault_count is read before the window and the delta
! is checked to be exactly 1 in _verify, exactly as mmudspcprobe_late.S does.
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
#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

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
	mov.l	p_d0end, r2		! Rn = _dpage_0 + 4 (store targets _dpage_0)
	mov.l	p_sentinel, r0
	ldc	r0, gbr			! GBR = sentinel value
	mov.l	p_fc, r0		! non-vacuity baseline: fault count before
	mov.l	@r0, r11		! the window (delta checked in _verify)
	mov.l	p_r2init, r4		! stash initial Rn for _verify (survives
					! the fault; r4 is untouched by the window)
	nop
	nop

	! ================= THE WINDOW ========================================
	! No memory traffic besides the single faulting delay-slot store, and no
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
	stc.l	gbr, @-r2		! DELAY SLOT: the form under test.
					! Store to (Rn-4) = _dpage_0, cold ->
					! DMISS_W -- THE FAULT
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
p_d0end:	.long _dpage_0 + 4
p_r2init:	.long _dpage_0 + 4
p_sentinel:	.long 0xABCD1234

! ---------------------------------------------------------------------------
ENTRY(_verify)
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
	! ---- The heart of the guard: Rn must have advanced by EXACTLY one
	! auto-decrement (initial - r2 == 4). ----
	mov.l	l_r2init, r0
	bra	7f			! PC-relative loads on SH2 are FORWARD-only,
	nop				! so the pool must trail its use, not lead it
	.align 2
l_r2init:	.long _dpage_0 + 4
7:
	sub	r2, r0			! r0 = initial - r2 (decrement applied)
	mov	#4, r1
	cmp/eq	r1, r0
	bt	9f
	mov	#8, r1
	cmp/eq	r1, r0
	bt	91f
	tst	r0, r0
	bt	92f
	mov.l	q_bad_baseX, r9		! some other corrupt value
	bra	_fail
	nop
91:	mov.l	q_bad_base8, r9		! applied TWICE (re-execution defect)
	bra	_fail
	nop
92:	mov.l	q_bad_base0, r9		! LOST (restore never reapplied)
	bra	_fail
	nop
9:
	! ---- The stored word at _dpage_0 must equal the GBR sentinel. ----
	mov.l	p_d0, r0
	mov.l	@r0, r1
	mov.l	l_sentinel, r0
	bra	l_sentinel_used
	nop
	.align 2
l_sentinel:	.long 0xABCD1234
l_sentinel_used:
	cmp/eq	r0, r1
	bt	10f
	mov.l	q_bad_val, r9
	bra	_fail
	nop
10:
	! ---- NON-VACUITY: exactly ONE fault must have been taken. ----
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
q_bad8:		.long 0x0000BAD8
q_bad_base8:	.long 0x0BADB008
q_bad_base0:	.long 0x0BADB000
q_bad_baseX:	.long 0x0BADBADB
q_bad_val:	.long 0x0BADDA7A
q_fc:		.long _fault_count
p_d0:		.long _dpage_0

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

#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

	! ---- VA-driven TLB-fault handler at VBR+0x400 ----
	.balign 4
	.space 0x400, 0
	.balign 4
_v_pc:
        mov.l   Hpteh_a, r1
        mov.l   @r1, r1                 ! r1 = PTEH (P4 alias) -- HW-captured faulting VPN
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
Hpteh_a:        .long 0xFF000000
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
