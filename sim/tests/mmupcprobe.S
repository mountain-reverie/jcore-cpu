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
! mmustale.S:89) -- but only coarsely, i.e. they check that control flow
! survived and the value arrived, not WHERE the restart landed.
! (mmurestartpc.S and mmudrain.S fault on @Rn+ loads, so they do not exercise
! the plain-load shape at all.) While this probe was unwired, an off-by-N
! regression in the normal arm would have left the whole suite green.
! sim/tests/mmudspcprobe.S is its delay-slot analogue.
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
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). STRONGER, not weaker: the
! window, the tripwires, the composite and the one-fault non-vacuity check are
! all unchanged, and a new check pins the fault KIND via EXPEVT (result 0x41),
! which the LDTLB version never asserted. The code region is published as TSB
! rows before AT goes on and the walker installs each page on its first fetch;
! the fault handler publishes the faulting page's row THROUGH THE P1 ALIAS (AT
! is on and the TSB is unmapped, so a P0 store from the handler would fault
! inside the handler) and returns with a plain RTE -- the access then retries,
! misses again, and the walker installs. The probe page still has NO row, so it
! still faults exactly once.
!
! One thing the walker forces that LDTLB did not: the code pages must be warmed
! on the D SIDE before the window. The handler runs with RB=1, where the walker
! is not armed, so its literal loads and its _fault_count update would take an
! unrecoverable nested fault on a page that is only I-resident.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
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

	! ---- Point the walker at a TSB of our own (base 0x00014000,
	! ---- TSB_SIZE_LOG=8 -> 256 sets x 32 bytes; HASH_SHIFT=6, HASH_MODE=1).
	! ---- The image is padded past its end so the walker's PHYSICAL reads
	! ---- land in SRAM, and it is zero-filled there, so every row starts
	! ---- invalid: _dpage_0 has no row and still faults, exactly as it did
	! ---- under LDTLB.
	mov.l	p_tsbbr_addr, r0
	mov.l	p_tsbbr_val, r1
	mov.l	r1, @r0
	mov.l	p_tsbcfg_addr, r0
	mov.l	p_tsbcfg_val, r1
	mov.l	r1, @r0
	mov	#0, r0
	.word	0x407E			! LDC r0, ASIDR  (ASID 0 throughout)
	nop
	nop

	! ---- Publish an identity TSB row per code page BEFORE enabling AT.
	! ---- The set address comes from the P4 helper at 0xFF000048; AT is off,
	! ---- so these are plain P0 stores. PTEL keeps U clear: these pages are
	! ---- FETCHED and a kernel fetch of a U=1 page is an SMEP fault.
	mov.l	p_code_start, r2
	mov.l	p_code_end, r3
	mov.l	p_tsbslot, r12
	mov	#0, r7			! ASID_TAG = 0
1:	mov.l	p_code_flags, r1
	mov	r2, r0
	or	r1, r0
	mov	r0, r8			! PTEL = PA | W|X|C|V
	mov.l	r2, @r12		! ask the helper for this VA's set
	mov.l	@r12, r10
	tsb_fill r10, r2, r7, r8
	mov.l	p_page_sz, r0
	add	r0, r2
	cmp/hs	r3, r2
	bf	1b

	! ---- Enable AT. ----
	mov.l	p_mmucr, r0
	mov	#1, r1
	mov.l	r1, @r0

	! ---- Warm the D-side of every code page. The fault handler makes
	! ---- PC-relative literal loads and updates _fault_count, and it runs
	! ---- with RB=1 -- where core/cpu.vhd's walk_req is NOT armed -- so a
	! ---- D-miss inside the handler would be an unrecoverable nested fault.
	! ---- Under LDTLB the pre-AT loop wrote BOTH arrays and these pages were
	! ---- D-resident for free; the walker installs I-side only, on a fetch.
	! ---- These touches happen BEFORE the fault-count baseline is read, so
	! ---- they sit outside the measured delta.
	mov.l	p_code_start, r2
	mov.l	p_code_end, r3
2:	mov.l	@r2, r1
	mov.l	p_page_sz, r0
	add	r0, r2
	cmp/hs	r3, r2
	bf	2b

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
p_code_flags:	.long 0x000000C9	! PA | W|X|C|V (U clear: SMEP)
p_page_sz:	.long PAGE_SZ
p_tsbslot:	.long 0xFF000048	! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:	.long 0xFF000014
p_tsbbr_val:	.long 0x00014008	! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:	.long 0xFF000018
p_tsbcfg_val:	.long 0x00000061	! HASH_SHIFT=6, HASH_MODE=1
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
	! ---- The fault taken must have been the kind this guard names. ----
	mov.l	q_evtbad, r0
	mov.l	@r0, r1
	tst	r1, r1
	bt	9f
	mov	#0x41, r9		! wrong EXPEVT: not the named fault kind
	bra	_fail
	nop
9:
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
q_evtbad:	.long _expevt_bad

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
	mov	r0, r4			! r4 = PTEL (V set)
	! Publish the row for the faulting page. The set address comes from the
	! P4 helper and is addressed THROUGH P1: AT is on and the TSB is
	! unmapped, so a P0 store from here would fault inside the handler.
	! Only r0-r7 are touched -- they are banked, and RB=1 here, so the
	! window's bank-0 tripwires survive untouched.
	mov.l	Hslot, r0
	mov.l	r1, @r0
	mov.l	@r0, r6
	mov.l	Hp1, r0
	or	r0, r6
	mov	#0, r7			! ASID_TAG = 0
	mov.l	r4, @(8, r6)		! data first ...
	mov.l	r7, @(4, r6)		! ... tag_lo second ...
	mov.l	r1, @(0, r6)		! ... tag_hi LAST (the commit point)
	mov.l	Hcount, r0		! non-vacuity: count the fault
	mov.l	@r0, r1
	add	#1, r1
	mov.l	r1, @r0
	! ---- Pin the FAULT KIND. This guard names its fault (DMISS) in the
	! ---- window; without this, a protection fault or a different miss kind
	! ---- would reach the same handler, be resolved the same way, and the
	! ---- composite would still match. Flag it here, judged in _verify.
	.word	0x0052			! STC EXPEVT, r0
	mov.l	Hexp_evt, r1
	cmp/eq	r1, r0
	bt	3f
	mov.l	Hevtbad, r0
	mov	#1, r1
	mov.l	r1, @r0
3:
	rte				! PC <- SPC (hardware restart PC); the
	nop				! access retries, misses, and the walker
					! installs the row just published
_h_fail_spin:
	bra	_h_fail_spin
	nop
	.align 2
Hpagemask:	.long 0xFFFFF000
Hpteh_a:        .long 0xFF000000
Hflags:		.long 0x000000E9
Hcflags:	.long 0x000000C9
Hdbase:		.long _dpage_0
Hslot:		.long 0xFF000048	! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
Hp1:		.long 0x80000000
Hexp_evt:	.long 0x060
Hevtbad:	.long _expevt_bad
Hcount:		.long _fault_count

	.balign 4
ENTRY(_fault_count)
	.long 0

	.balign 4
ENTRY(_expevt_bad)
	.long 0

	.balign 4
ENTRY(_code_end)

	! ======================= unmapped region =======================
	.balign PAGE_SZ
_dpage_0:	.long 0xD0000000
	.space PAGE_SZ - 4, 0

	! ---- The image must reach past the END of the guard's TSB: the walker
	! ---- reads it by PHYSICAL address and a physical alias is backed by
	! ---- SRAM only within the loaded image extent.
	.org 0x16000

#endif
