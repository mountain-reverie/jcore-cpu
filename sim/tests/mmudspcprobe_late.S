! mmudspcprobe_late.S -- Defect 7 reproducer: DELAY-SLOT D-side TLB-fault
! restart PC for a LATE-ACCESS instruction (access launches in slot 1, not
! slot 0).  Byte-for-byte the same harness as mmudspcprobe.S -- same
! tripwires, same composite encoding, same non-vacuity check -- with exactly
! one change: the delay-slot instruction is a POST-INCREMENT load (@Rm+)
! instead of the slot-0 `mov.l @r2,r12`.  Per decode/gen-go/spec/mov.toml,
! MOV.{B,W,L} @Rm+,Rn are two slots: slot 0 computes/writes back the
! incremented base (no memory access), slot 1 is the READ that can fault.
! The only variable between the two files is which slot carries the access --
! that pairing IS the evidence for Defect 7, and it is why each late-access
! form gets its own file rather than being argued for by analogy.
!
! This file is also the shared harness for its per-form siblings; see FORM
! SELECTION below.  Default form (this guard) is MOV.L @Rm+,Rn.
!
! DEFECT 7 (FIXED 2026-08-06; this guard is now ACTIVE and GREEN).  On a
! D-side TLB fault taken in a branch delay slot, the restart landed on the
! delay-slot instruction itself instead of backing up to the branch -- but
! ONLY when the faulting access launched in a slot AFTER slot 0.  The
! hypothesis this file was written to test (ma_dslot shadowed at the
! ACCESS-LAUNCH point, so a late-access instruction sees delay_slot already
! deasserted and takes the "normal" arm tlb_exc_pc := ex_if_pc + 4 instead of
! the delay-slot arm ex_if_pc + 2) was CONFIRMED, and the root cause sits one
! level upstream of the shadow: decode_core re-sampled the delay-slot flag
! from delay_jump on EVERY non-stalled slot, making it a one-SLOT pulse rather
! than a per-INSTRUCTION attribute.  Fix: decode/decode_core.vhm's g_dslot
! samples delay_jump once per instruction (gated on `dispatch') and holds it
! across every slot, so the arm selection no longer depends on which slot
! carries the access.  See the m8_dsdslot_0 Defect 7 writeup in sim/mmu_sim.sh
! for the exhaustive 26-case classification (MOV.{B,W,L} @Rm+,Rn,
! CAS.L Rm,Rn,@R0, and MAC.{L,W} @Rm+,@Rn+ are the five affected forms; all 22
! slot-0-access forms were unaffected).
!
! DO NOT WEAKEN THIS GUARD.  Its whole value is the pairing with
! mmudspcprobe.S: byte-for-byte the same harness, the only variable being
! whether the faulting access launches in slot 0 (there) or slot 1 (here).
! Measured 0x00010101 before the fix, PASS after.  Reproduce the pair with:
!   sim/mmu_sim.sh -n mmudspcprobe      cpu_tb 200us
!   sim/mmu_sim.sh -n mmudspcprobe_late cpu_tb 80us
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

! ---- FORM SELECTION -------------------------------------------------------
! This file is BOTH a guard in its own right (default form: MOV.L @Rm+,Rn) and
! the shared harness for its per-form siblings, which are three-line wrappers
! that #define DSLOT_FORM and #include this file:
!
!   mmudspcprobe_lateb.S   MOV.B @Rm+,Rn
!   mmudspcprobe_latew.S   MOV.W @Rm+,Rn
!   mmudspcprobe_latec.S   CAS.L Rm,Rn,@R0     (locked RMW)
!   mmudspcprobe_latem.S   MAC.L @Rm+,@Rn+     (dual pointer)
!   mmudspcprobe_latemw.S  MAC.W @Rm+,@Rn+     (dual pointer)
!
! Together with this file that is ALL FIVE late-access forms in the machine.
! Each was measured RED (Result=65793 = 0x00010101) on the pre-fix RTL and
! GREEN after, so none of them is vacuous.
!
! Every late-access form has to be checked SEPARATELY even though the fix is
! structural: the whole point of the mmudspcprobe / mmudspcprobe_late pairing
! is that the ONLY variable is which slot carries the access, and that argument
! is per-form. One file per form, one instruction different, nothing else.
!
! The loaded value differs per form because _dpage_0 begins 0xD0000000 and the
! SH-2 is big-endian, so the byte/word loads sign-extend a different slice:
!   MOV.L -> 0xD0000000    MOV.B -> 0xFFFFFFD0    MOV.W -> 0xFFFFD000
! Numbered from 1 DELIBERATELY: an undefined or misspelled form macro
! preprocesses to 0, so with FORM_MOVL==0 a broken wrapper would silently build
! as MOV.L and "pass" while testing nothing. From 1, 0 falls through to #error.
#define FORM_MOVL 1
#define FORM_MOVB 2
#define FORM_MOVW 3
#define FORM_CASL 4
#define FORM_MACL 5
#define FORM_MACW 6
#ifndef DSLOT_FORM
#define DSLOT_FORM FORM_MOVL
#endif

#if   DSLOT_FORM == FORM_MOVL
#define DSLOT_INSN      mov.l @r2+, r12
#define DSLOT_EXPECT    0xD0000000
#define DSLOT_NAME      "MOV.L @Rm+,Rn"
#elif DSLOT_FORM == FORM_MOVB
#define DSLOT_INSN      mov.b @r2+, r12
#define DSLOT_EXPECT    0xFFFFFFD0
#define DSLOT_NAME      "MOV.B @Rm+,Rn"
#elif DSLOT_FORM == FORM_MOVW
#define DSLOT_INSN      mov.w @r2+, r12
#define DSLOT_EXPECT    0xFFFFD000
#define DSLOT_NAME      "MOV.W @Rm+,Rn"
#elif DSLOT_FORM == FORM_CASL
! CAS.L Rm,Rn,@R0 = 0010 nnnn mmmm 0011; here n=12 (r12), m=2 (r2) -> 0x2C23.
! sh2-elf-gas does not know the J-core mnemonic, hence the .word (same idiom
! the prologue uses for LDC PTEH / LDTLB).
!
! Per decode/gen-go/spec/system.toml the READ is slot 1 -- the late access --
! and its wbus is Rn, so Rn (r12) receives the loaded word and the harness's
! existing `cmp/eq r5,r12' check applies UNCHANGED. Rm (r2) is forced to 0 in
! the window so the slot-2 compare mismatches, T stays 0, and the slot-3
! ma_mask=T store is suppressed: the probe page is left pristine and no second
! locked access can fault. CAS.L is a LOCKED RMW (ma_lock=Y on slots 1-3),
! which is why the pre-fix symptom for this form was a bus-ACK hang rather
! than a clean composite -- see the m8_dsdslot_0 writeup in sim/mmu_sim.sh.
#define DSLOT_INSN      .word 0x2C23
#define DSLOT_EXPECT    0xD0000000
#define DSLOT_NAME      "CAS.L Rm,Rn,@R0"
#define DSLOT_PTR_IN_R0 1
#elif DSLOT_FORM == FORM_MACL || DSLOT_FORM == FORM_MACW
! MAC.{L,W} @Rm+,@Rn+ is the DUAL-POINTER late-access form, and the only one of
! the five whose slot 0 ALSO makes an access. Per multiply.toml slot0 reads @Rn
! (xbus=Rn) and slot1 reads @Rm (xbus=Rm), so it is the FIRST operand in source
! syntax -- Rm -- that carries the LATE access. Hence r2 (Rm) points at the COLD
! page and r3 (Rn) at a page deliberately PRE-WARMED before the window: slot 0
! must succeed so the fault lands on slot 1, the arm under test. A cold Rn would
! fault in slot 0 and test nothing new.
!
! Restarting this form re-executes slot 0 too, so its Rn post-increment must be
! undone by the dual-base restore (datapath g_restore2). That is why the check
! below is on the two BASES rather than a destination register: MAC has no GPR
! destination, and base-exactness catches both a lost restore and a double
! auto-modify, which is the stronger property anyway.
#if DSLOT_FORM == FORM_MACL
#define DSLOT_INSN      mac.l @r2+, @r3+
#define DSLOT_STEP      4
#else
#define DSLOT_INSN      mac.w @r2+, @r3+
#define DSLOT_STEP      2
#endif
#define DSLOT_EXPECT    0xD0000000
#define DSLOT_NAME      "MAC @Rm+,@Rn+"
#define DSLOT_DUAL_PTR  1
#else
#error "unknown DSLOT_FORM"
#endif

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
	mov.l	p_d0, r2		! base = unmapped data page
	mov.l	p_v0, r5		! expected loaded value
#ifdef DSLOT_DUAL_PTR
	! Rm (r2) = COLD page (slot-1 access, under test); Rn (r3) = page PRE-WARMED
	! here so slot 0 cannot fault. The warming touch happens BEFORE the
	! fault-count baseline below, so its own fault sits outside the measured
	! delta and the window still accounts for exactly one.
	mov.l	p_d1, r2		! Rm -> cold probe page
	mov.l	p_d0, r3		! Rn -> pre-warmed page
	mov.l	@r3, r1			! the warming touch (faults once, HERE)
#endif
	mov.l	p_fc, r0		! non-vacuity baseline: fault count before
	mov.l	@r0, r11		! the window (delta checked in _verify)
#ifdef DSLOT_PTR_IN_R0
	! CAS.L's pointer operand is the IMPLICIT R0, not the r2 the load forms
	! use. Staged LAST because the fault-count read above clobbers r0. r2 is
	! reused as Rm and zeroed inside the window (register move, no memory).
	mov.l	p_d0, r0		! R0 = the unmapped probe page
#endif
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
#ifdef DSLOT_PTR_IN_R0
	mov	#0, r2			! Rm: must MISMATCH the probe word so the
					! masked store never fires (see above)
	nop
#else
	nop
#endif
	nop
	add	#1, r7			! tripwire: branch_PC - 4
	add	#1, r6			! tripwire: branch_PC - 2
	bra	_dsl_target		! THE BRANCH -- the restart target
	DSLOT_INSN			! DELAY SLOT: the form under test (see
					! DSLOT_FORM above) -- its access is in
					! SLOT 1, NOT slot 0: the late-access
					! shape Defect 7 got wrong.  DMISS_R --
					! THE FAULT
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
#ifdef DSLOT_DUAL_PTR
p_d1:		.long _dpage_1
#endif
p_v0:		.long DSLOT_EXPECT

! ---------------------------------------------------------------------------
ENTRY(_verify)
	! The delay-slot load must actually have landed.
#ifdef DSLOT_DUAL_PTR
	! Both bases must have advanced EXACTLY one element: a lost restore leaves
	! them short, a double auto-modify leaves them long.
	mov.l	q_d1_end, r0
	cmp/eq	r0, r2
	bt	1f
	mov.l	q_bad, r9
	bra	_fail
	nop
1:	mov.l	q_d0_end, r0
	cmp/eq	r0, r3
	bt	11f
	mov.l	q_bad2, r9
	bra	_fail
	nop
11:
#else
	cmp/eq	r5, r12
	bt	1f
	mov.l	q_bad, r9
	bra	_fail
	nop
1:
#endif
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
#ifdef DSLOT_DUAL_PTR
q_bad2:		.long 0x000BAD02
q_d1_end:	.long _dpage_1 + DSLOT_STEP	! Rm advanced by exactly one element
q_d0_end:	.long _dpage_0 + DSLOT_STEP	! Rn advanced by exactly one element
#endif
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

#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

	! ---- VA-driven TLB-fault handler at VBR+0x400 ----
	.balign 4
	.space 0x400, 0
	.balign 4
_v_pc:
	.word	0x018B			! STC PTEH, r1
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
! Second probe page, used only by the dual-pointer (MAC) forms. Emitted
! unconditionally so every form links with an identical memory layout.
_dpage_1:	.long 0xD0000000
	.space PAGE_SZ - 4, 0

#endif
