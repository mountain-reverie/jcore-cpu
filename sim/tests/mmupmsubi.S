! mmupmsubi.S -- Group-B case B2 of the TSB PageMask / tag-granularity
! contract (docs/mmu/pagemask-walker-contract.md §7.1, hardware-spec.md §7.0a,
! linux-spec.md §4.3a). The I-SIDE twin of mmupmsub4k (B1a/b/c).
!
! LANE 2: links the REAL linux@jcore objects (arch/sh/mm/tlb-jcore.o,
! arch/sh/kernel/cpu/jcore/{ex,entry}.o), so the TSB row under test is written
! by the REAL __jcore_tlb_walk(). Run by sim/linux_sim.sh and by
! .github/workflows/full-regression.yml, NOT by sim/mmu_sim.sh.
!
! ---------------------------------------------------------------------------
! WHY A SEPARATE CASE FROM B1
! ---------------------------------------------------------------------------
! The defect is identical -- a `addr & PAGE_MASK` tag_hi has VA[13:12] forced
! to zero and can never satisfy the walker's exact 4 KB compare for a first
! touch outside the page's base 4 KB sub-page -- but the I-side reaches the
! walker through its own arming and suppression logic (core/cpu.vhd's
! walk_supp_i / walk_i_arm_raw, and walk_va <= i_va_32), and an I-side miss is
! delivered by a different path than a D-side one. A D-side-only guard would
! leave that half unpinned.
!
! Construction: ONE 16 KB mapping (page-size slot 0 -> PageMask pm=1)
!
!     VA 0x00400000 -> PA 0x001C0000
!
! whose FIRST access of any kind is an INSTRUCTION FETCH at VA + 0x2000
! (VA[13:12] = 10) -- a jmp into the middle of the page. Two code stubs are
! staged by physical address beforehand:
!
!     PA + 0x2000   the REAL stub: stores 0x1EC0DE01 and returns to P1
!     PA + 0x0000   a DECOY at the page's base sub-page: stores 0x1EC0DE02
!
! so a translation that aliased down to VA[13:12] = 00 does not merely "still
! work" -- it executes the decoy and is caught by result 0x05. That is the
! I-side equivalent of B1's PA readback.
!
! The pte is X=1, U=0: core/tlb.vhd's SMEP check rejects a kernel fetch of a
! U=1 page, so a U=1 code page would fault for a reason that has nothing to do
! with this contract.
!
! ---------------------------------------------------------------------------
! MANDATORY INSTRUMENTATION (contract §7.0 P1/P2)
! ---------------------------------------------------------------------------
! P2: VBR points at this harness's OWN vector page, whose +0x400 shim counts
! faults and reports 0xE0|phase past FAULT_BOUND before jumping to the real
! jcore_tlb_miss. Without it the pre-fix failure is an unbounded fault loop
! that presents only as a --stop-time timeout, which jcore-cpu CLAUDE.md rules
! out as a failure signal. Expected total faults: 1. FAULT_BOUND: 8.
!
! P1: cnt_hits from P4_TSBCNT must increase by EXACTLY 1 across the fetch. A
! case that executed the right instructions with cnt_hits unchanged proves
! only that software resolved it, and reports 0xF0.
!
! ---------------------------------------------------------------------------
! Memory map (P1 = 0x80000000 | physical)
! ---------------------------------------------------------------------------
!   0x00020000  PGD table       (16 KB, P1 0x80020000)
!   0x00024000  PTE table       (16 KB, P1 0x80024000) -- covers pgd[0]
!   0x00028000  TSB             (512 B, P1 0x80028000, TSB_SIZE_LOG=4)
!   0x00029000  scratch globals
!   0x0002A000  stack           (P1 0x8002AF00)
!   0x001C0000  PA of the 16 KB code page  (decoy stub at +0, real at +0x2000)
!
! (0xE0|phase rather than the contract's flat 0xFE -- see mmupmsub4k.S's header
! for why that refinement is deliberate. Phases must stay <= 15: 0xE0|16 is
! 0xF0, the reserved P1 anti-vacuity code.)
!
! ---------------------------------------------------------------------------
! Result codes (printed by sim/cpu_ctb.c as unsigned DECIMAL)
! ---------------------------------------------------------------------------
!   0x04  ( 4)  the staged stub did not run at all (flag word untouched, or
!               some third value)
!   0x05  ( 5)  the fetch aliased to the page's BASE 4 KB sub-page -- the
!               decoy at PA+0 ran instead of the real stub at PA+0x2000
!   0x14  (20)  TLB-miss fault count across the fetch != 1
!   0x24  (36)  cnt_hits delta != 1 (but != 0)
!   0xE4  (228) P2: repeat-fault bound exceeded. THE PRE-FIX FAILURE.
!   0xF0  (240) P1: cnt_hits did not move -- software resolved it, not the
!               walker (vacuous case)
!   0xF1  (241) unexpected general exception at VBR+0x100 (MULTI_HIT, IPROT,
!               illegal, ...)
!   0xF2  (242) unexpected interrupt at VBR+0x600
!   0xF3  (243) do_page_fault() reached -- the pte here is present and
!               executable, so this is a defect
!   0xFE  (254) P2 bound exceeded with phase == 0
!   0x7F  (127) _fail integrity net (a fail code of 0 names nothing)
!
! ---------------------------------------------------------------------------
! MUTATION RECORD (contract §7.0 P4) -- measured, not asserted
! ---------------------------------------------------------------------------
!   the defect itself: revert arch/sh/mm/tlb-jcore.c to `addr & PAGE_MASK`
!                      -> FAIL Result=228 (0xE4), the I-side fetch livelocks
!   the data assertion: v_iflag_ok 0x1EC0DE01 -> 0x1EC0DE77
!                      -> FAIL Result=4, a code of this guard's own
!   unmutated          -> Test Passed

#include "sim_instr.h"
#include <asm/pgtable-bits-jcore.h>
#define ENTRY(name) .globl name; .balign 4; name:

! ---- Page-table / TSB layout, and the pte flag word for a CODE page:
! ---- V|C|D|X with U DELIBERATELY CLEAR -- core/tlb.vhd's SMEP check rejects a
! ---- kernel fetch of a U=1 page, so a U=1 code page would fault for a reason
! ---- that has nothing to do with this contract. W is not needed. D is set so
! ---- jcore_pte_to_ptel() does not take its clean-page W-withholding arm.
#define PGD_TBL   0x80020000
#define PTE_TBL   0x80024000
#define TSB_BASE  0x80028000
#define PTE_FLAGS 0x59                  /* V|C|D|X, U=0, size slot 0 */

! ---- Scratch globals. `mov.l @(disp,PC)` reaches FORWARDS only, so several
! ---- literal pools in this file each need their own copy of these addresses;
! ---- naming them here is what stops those copies drifting apart.
#define K_SCRATCH       0x80029000
#define K_SCRATCH_WORDS 8               /* zeroes K_SCRATCH .. K_SCRATCH+0x1C */
#define K_FAULTCNT      0x80029004      /* do_page_fault() count             */
#define K_TLBFAULTS     0x80029014      /* P2 bounded repeat-fault counter   */
#define K_PHASE         0x80029018      /* scenario id, named by the P2 trip */
#define K_IFLAG         0x8002901C      /* which staged stub actually ran    */

! ---- The workload: ONE 16 KB code page whose first access of any kind is an
! ---- instruction fetch at a non-base 4 KB sub-page. P1() is the untranslated
! ---- kernel alias used to stage the stubs by PHYSICAL address.
#define P1(x)     ((x) | 0x80000000)
#define VA_I      0x00400000
#define PA_I      0x001C0000
#define D_I       0x2000                /* VA[13:12] = 10 */

! ---- The two markers. IFLAG_BAD MUST be IFLAG_OK + 1: _istubbad derives it
! ---- with `add #1, r2` because it may hold no literal pool of its own (see
! ---- the stubs below), so the two cannot be chosen independently. Deriving it
! ---- here with the same +1 makes that coupling mechanical instead of a
! ---- comment somebody can miss: if IFLAG_OK ever ends in 0xFF the pair still
! ---- stays distinct, and results 0x04 and 0x05 cannot collapse into one.
#define IFLAG_OK  0x1EC0DE01
#define IFLAG_BAD (IFLAG_OK + 1)

! Bounded repeat-fault limit (contract §7.0 P2). Expected total is 1.
#define FAULT_BOUND 8

        .section .vect,"a"
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

        .section .textlo,"ax"
ENTRY(start)
        mov.l   p_sp,    r15
        mov.l   p_kmain, r0
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x8002AF00
p_kmain: .long kmain

        .text

! ===========================================================================
! Harness vector page -- see mmupmsub4k.S's header for the full rationale.
! VBR points here, not at jcore_vbr_base, purely so the pre-fix unbounded
! fault loop reports a named code instead of timing out. Every fault still
! runs the real kernel handler; the kernel objects are unmodified.
! ===========================================================================
        .balign 0x100
ENTRY(harness_vbr_base)
0:      bra     0b
        nop

        .org    harness_vbr_base + 0x100
        mov.l   g_res, r0
        mov.l   g_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
g_res:  .long TEST_RESULT_ADDRESS
g_code: .long 0x000000F1

        .org    harness_vbr_base + 0x400
        mov.l   t_cnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov     #FAULT_BOUND, r2
        cmp/hi  r2, r1
        bt      9f
        mov.l   t_real, r0
        jmp     @r0                     ! jcore_tlb_miss
        nop
9:      mov.l   t_phase, r0
        mov.l   @r0, r1
        tst     r1, r1
        bt      6f
        mov.l   t_e0, r2
        or      r2, r1
        bra     8f
        nop
6:      mov.l   t_fe, r1
8:      mov.l   t_res, r0
        mov.l   r1, @r0
7:      bra     7b
        nop
        .align 2
t_cnt:   .long K_TLBFAULTS
t_phase: .long K_PHASE
t_real:  .long jcore_tlb_miss
t_e0:    .long 0x000000E0
t_fe:    .long 0x000000FE
t_res:   .long TEST_RESULT_ADDRESS

        .org    harness_vbr_base + 0x600
        mov.l   i_res, r0
        mov.l   i_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
i_res:  .long TEST_RESULT_ADDRESS
i_code: .long 0x000000F2

        .org    harness_vbr_base + 0x700

! ===========================================================================
kmain:
        ! ---- RB=0 (core/cpu.vhd gates walk_req on dp_sr.rb = '0'). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        mov     #0, r0
        lds     r0, pr

        ! ---- Pre-zero the GPRs the fault handlers push, in BOTH banks. ----
        mov.l   p_rbset,  r8
        mov.l   p_rbclear, r9
        stc     sr, r0 ; or  r8, r0 ; ldc r0, sr
        nop ; nop
        mov     #0, r0 ; mov #0, r1 ; mov #0, r2 ; mov #0, r3
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7
        stc     sr, r0 ; and r9, r0 ; ldc r0, sr
        nop ; nop
        mov     #0, r4
        mov     #0, r5
        mov     #0, r6
        mov     #0, r7
        mov     #0, r8
        mov     #0, r9
        mov     #0, r10
        mov     #0, r11
        mov     #0, r12
        mov     #0, r13
        mov     #0, r14

        mov     #0, r0
        ldc     r0, asidr
        nop
        nop
        mov     #0, r0
        ldc     r0, gbr
        nop
        nop

        ! ---- Zero the scratch globals. ----
        mov.l   k_scratch, r0
        mov     #K_SCRATCH_WORDS, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- pgd[0] -> pte table; the one 16 KB code pte (X=1, U=0). ----
        mov.l   k_pgd,   r0
        mov.l   k_ptetbl, r1
        mov.l   r1, @r0
        mov.l   k_pte_i, r0 ; mov.l v_pte_i, r1 ; mov.l r1, @r0

        ! ---- Zero the TSB (16 sets x 32 bytes => 128 words). ----
        mov.l   k_tsb,  r0
        mov     #64, r2
        shll    r2
        mov     #0,  r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Stage the two code stubs BY PHYSICAL ADDRESS (P1 stores). The
        ! ---- real one at PA+0x2000, the decoy at PA+0. Both are copied
        ! ---- verbatim from .text, literal pools included -- their `mov.l
        ! ---- @(disp,PC)` operands stay in range because the whole block
        ! ---- moves together. ----
        mov.l   k_copy_tab, r14
        mov.l   k_copy_end, r13
_copy_row:
        mov.l   @r14+, r10              ! src (P1)
        mov.l   @r14+, r11              ! dst (P1)
        mov.l   @r14+, r12              ! word count
1:      mov.l   @r10+, r0
        mov.l   r0, @r11
        add     #4, r11
        dt      r12
        bf      1b
        cmp/hs  r13, r14
        bf      _copy_row

        ! ---- MMU_TTB -> our pgd; VBR -> the harness vector page. ----
        mov.l   k_ttb_a, r0 ; mov.l k_pgd, r1 ; mov.l r1, @r0
        mov.l   k_vbr, r0
        ldc     r0, vbr
        nop
        nop

        ! ---- TSB config, then enable AT. ----
        mov.l   k_tsbbr_a,  r0 ; mov.l v_tsbbr,  r1 ; mov.l r1, @r0
        mov.l   k_tsbcfg_a, r0 ; mov.l v_tsbcfg, r1 ; mov.l r1, @r0
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0
        nop
        nop

        ! ---- Publish the phase for the VBR+0x400 shim. ----
        mov.l   k_phase, r0
        mov     #4, r1
        mov.l   r1, @r0

        ! ---- Baselines. ----
        mov.l   k_tlbfaults, r0
        mov.l   @r0, r8                 ! f0
        mov.l   k_walkcnt, r0
        mov.l   @r0, r7
        extu.w  r7, r7                  ! hits0

        ! ---- Hand the staged stub everything it needs IN REGISTERS: r1 =
        ! ---- the flag address, r2 = the value to store, r3 = the P1 return
        ! ---- address. The stub therefore makes NO data access inside the
        ! ---- page under test.
        ! ----
        ! ---- That is load-bearing for the P1 (cnt_hits) assertion, not
        ! ---- tidiness. An earlier revision used PC-relative literals inside
        ! ---- the stub; those are D-side accesses to the same 4 KB VPN, and
        ! ---- since the I-side install goes into the ITLB only, the first one
        ! ---- MISSES THE DTLB, walks, and finds the very row the I-side fault
        ! ---- had written -- a second walk hit. Measured: cnt_hits moved by 2,
        ! ---- and the case then could not say whether the I-side path itself
        ! ---- had worked. With no data access in the page the delta is exactly
        ! ---- the one I-side hit this case is about.
        mov.l   k_iflag_r,   r1
        mov.l   v_iflag_ok_r, r2
        mov.l   k_iback_r,   r3

        ! ================= THE FIRST TOUCH: an INSTRUCTION FETCH at a
        ! ================= NON-BASE 4 KB SUB-PAGE of the 16 KB page.
        mov.l   k_va_istub, r0          ! 0x00402000
        jmp     @r0
        nop
ENTRY(_iback)

        ! ---- Deltas, then AT off for the readback. ----
        mov.l   k_tlbfaults, r0
        mov.l   @r0, r6
        sub     r8, r6                  ! r6 = fault delta
        mov.l   k_walkcnt, r0
        mov.l   @r0, r4
        extu.w  r4, r4
        sub     r7, r4                  ! r4 = cnt_hits delta

        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0
        nop
        nop

        ! ---- Which stub ran? ----
        mov.l   k_iflag, r0
        mov.l   @r0, r5
        mov.l   v_iflag_bad, r1
        cmp/eq  r1, r5
        bf      1f
        mov     #5, r9                  ! aliased to the BASE sub-page
        bra     _fail
        nop
1:      mov.l   v_iflag_ok, r1
        cmp/eq  r1, r5
        bt      2f
        mov     #4, r9                  ! the staged stub never ran
        bra     _fail
        nop
2:
        ! ---- Exactly one TLB-miss fault. ----
        mov     #1, r0
        cmp/eq  r0, r6
        bt      3f
        mov     #0x14, r9
        bra     _fail
        nop
3:
        ! ---- P1 anti-vacuity: cnt_hits moved, and by exactly 1. ----
        tst     r4, r4
        bf      4f
        mov.l   v_f0code, r9
        bra     _fail
        nop
4:      mov     #1, r0
        cmp/eq  r0, r4
        bt      5f
        mov     #0x24, r9
        bra     _fail
        nop
5:
        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000
k_pgd:          .long PGD_TBL
k_ptetbl:       .long PTE_TBL
k_tsb:          .long TSB_BASE
k_scratch:      .long K_SCRATCH
k_tlbfaults:    .long K_TLBFAULTS
k_phase:        .long K_PHASE
k_iflag:        .long K_IFLAG
k_walkcnt:      .long 0xFF000054
k_ttb_a:        .long 0xFF000008
k_vbr:          .long harness_vbr_base
k_tsbbr_a:      .long 0xFF000014
v_tsbbr:        .long TSB_BASE | 4     ! TSB_SIZE_LOG=4 -> 16 sets
k_tsbcfg_a:     .long 0xFF000018
v_tsbcfg:       .long 0x00000061
k_mmucr:        .long 0xFF000010
k_copy_tab:     .long _copy_tab
k_copy_end:     .long _copy_tab_end
k_va_istub:     .long VA_I + D_I
k_iflag_r:      .long K_IFLAG           ! handed to the stub in r1
v_iflag_ok_r:   .long IFLAG_OK          ! handed to the stub in r2
k_iback_r:      .long _iback            ! == the P1 return address (r3)
v_iflag_ok:     .long IFLAG_OK
v_iflag_bad:    .long IFLAG_BAD
v_f0code:       .long 0x000000F0

! ---- The one 16 KB code pte, addressed the way the walker indexes it:
! ---- pte_index = (VA >> 14) & 0xFFF, pgd_index = VA >> 26 == 0. Computing the
! ---- index from the VA rather than hardcoding it means a VA edit cannot leave
! ---- the pte behind at a stale slot.
k_pte_i:        .long PTE_TBL + ((VA_I >> 14) & 0xFFF) * 4
v_pte_i:        .long PA_I | PTE_FLAGS

        .balign 4
_copy_tab:
        ! src (P1)      dst (P1)      words
        .long _istub,     P1(PA_I + D_I), (_istub_end - _istub) / 4
        .long _istubbad,  P1(PA_I),       (_istubbad_end - _istubbad) / 4
_copy_tab_end:

! ---- The staged stubs. Copied verbatim to physical memory and executed
! ---- through the translation under test. They contain NO literal pool and
! ---- make NO data access inside the page: r1/r2/r3 are set up by the caller
! ---- (see the note at the jmp above). r1/r2/r3 are bank-0 registers, so the
! ---- I-side fault -- which enters with SR.RB=1 -- cannot disturb them.
! ----
! ---- DO NOT ADD A LITERAL POOL HERE. It is not a tidiness rule. A `mov.l
! ---- @(disp,PC)` in a stub is a D-SIDE access to the same 4 KB VPN, and the
! ---- I-side install goes into the ITLB only -- so it misses the DTLB, walks,
! ---- and hits the very row the I-side fault wrote. cnt_hits then moves by 2
! ---- and result 0x24 fires for a reason with nothing to do with the I-side.
! ---- Measured, not theorised; see the note at the jmp above.
        .balign 4
_istub:
        mov.l   r2, @r1                 ! flag = IFLAG_OK
        jmp     @r3                     ! back to P1
        nop
        nop                             ! pad: the copy loop counts WORDS, so
                                        ! the block must be a whole number of
                                        ! them ((_istub_end - _istub) / 4)
_istub_end:

! ---- The DECOY, staged at the page's BASE 4 KB sub-page. If the fetch ever
! ---- aliased down to VA[13:12] = 00 this runs instead, and it writes a
! ---- DIFFERENT value so the harness can say so (result 0x05) rather than
! ---- passing on the strength of a wrong translation.
        .balign 4
_istubbad:
        add     #1, r2                  ! -> IFLAG_BAD, the decoy marker
        mov.l   r2, @r1
        jmp     @r3
        nop
_istubbad_end:

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

! ===========================================================================
! Stub set for the real linux@jcore objects' cross-object undefined symbols
! (same set as sim/tests/mmuhuge.S).
! ===========================================================================
ENTRY(do_page_fault)
        mov.l   dpf_faultcnt, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.l   dpf_res, r0
        mov.l   dpf_code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .align 2
dpf_faultcnt:   .long K_FAULTCNT
dpf_res:        .long TEST_RESULT_ADDRESS
dpf_code:       .long 0x000000F3

ENTRY(exception_handler)
        rts
        nop
ENTRY(jcore_handle_exception)
1:      bra     1b
        nop
ENTRY(do_IRQ)
1:      bra     1b
        nop
ENTRY(arch_local_irq_restore)
        rts
        nop
ENTRY(arch_local_save_flags)
        mov     #0, r0
        rts
        nop

ENTRY(memset)
        mov     r4, r3
1:      tst     r6, r6
        bt      2f
        mov.b   r5, @r4
        add     #1, r4
        add     #-1, r6
        bra     1b
        nop
2:      mov     r3, r0
        rts
        nop

        .bss
        .balign 16
        .globl  jcore_boot_tsb
        .type   jcore_boot_tsb, @object
        .size   jcore_boot_tsb, 4096
jcore_boot_tsb:
        .skip   4096
        .text
