! mmushadowld.S -- the MINIMAL fault-shadow @Rn+ load train (Defect 2; GREEN)
!
! DEFECT ISOLATED (Defect 2):
! core/datapath.vhm's precise-exception squash `tlb_squash` suppresses the GPR
! writebacks of instructions issued in a fault's shadow (reg_wr_z_g /
! reg_wr_w_g).  It does NOT suppress their MEMORY ACCESSES: the "start new
! memory transactions" block WAS gated only on `mem.issue='1' and
! data_o.en='0'`.  (Pre-fix description: the block now also carries
! `and tlb_squash_r = '0'`.)
!
! Why that breaks the two-slot post-increment load form:
!   slot0  commits Rm := Rm+size on the EX z-port (no access)
!   slot1  reads memory with the address RECOMPUTED as Rm-size
!          (mem.addr_sel=SEL_ZBUS, arith=SUB, base Rm on xbus -- the
!           `mem_autoupd` signature), i.e. slot1 ASSUMES slot0 already bumped.
! In the fault shadow of load i, tlb_squash correctly kills load i+1's slot0
! bump -- but slot1 still issues, now addressing page-4, which lands inside the
! PREVIOUS page.  That phantom access faults on the WRONG page, pre-empts load
! i's handler entry, restores Rn := page-4, and after the restart hits the
! now-mapped previous page so it never faults on its own page.  Net: every
! second access in a train of faulting @Rn+ loads is lost.
!
! VCD evidence (from the mmudrain.S Result=6 investigation):
!   770000ns  load1 bump  we_ex=1, addr=1, din=0x4004  presented with slot_o=0
!             (no commit)
!   780000ns  tlb_squash forces we_ex=0
!   800000ns  load1 issues d_va=0x3ffc  (= 0x4000 - 4)   <== the phantom access
!
! ---- shape: exactly TWO loads, the minimum that reproduces ----
! mmudrain.S leg A uses a ten-deep train plus an I-side drain, which proves the
! symptom but not the mechanism.  This guard is the two-instruction core:
!   mov.l @r2+, r12      ! DMISS_R on _dpage_S0 -- the FAULT
!   mov.l @r3+, r13      ! issued in its shadow -- THE DEFECT
! Nothing at all between them.  Both bases must end at their OWN page + 4, and
! both loads must have returned their own page's seeded value.
!   low by 4  -> the access was DROPPED
!   high by 4 -> the access was executed TWICE
!
! ---- CRITICAL TEST-CONSTRUCTION HAZARD (learned on the Defect 1 guard) ----
! ma_autoupd and friends are rewritten at the MEMORY-ACCESS pipeline point, so
! ANY intervening memory access -- including an innocent PC-relative literal
! load (`mov.l label, rN`) -- between the faulting access and the instruction
! under test clears the stale shadow and HIDES the defect.  Everything the
! window needs is therefore staged into registers BEFORE the window, and every
! assertion is deferred to _verify_S.  A guard that passes pre-fix is a broken
! guard, not a fixed CPU.
!
! ---- CURRENT STATUS: GREEN ----
! Historical note: with only the Defect 2 fix in place this guard's r3 check
! (the shadow load) passed but the r2 check still reported Result=0x21, because
! of a THIRD, INDEPENDENT defect: the D-side restart PC was FOUR BYTES (two
! instructions) too early, so fault 2's restart re-executed load0 and bumped r2
! a second time.  sim/tests/mmurestartpc.S isolates that defect to a single
! faulting load.  Both defects are now FIXED (Defect 2 = 84378f9, Defect 3 =
! 2384dc4) and this guard PASSES.  A failure here is a REAL regression -- do not
! dismiss it as a known defect.
!
! ---- non-vacuity ----
! The handler counts faults and the guard asserts count >= 1 (fail 0x10).  The
! check is deliberately LOOSE (>=, not ==): a handler-side counter is NOT a
! reliable exact oracle, because faults can PRE-EMPT each other and handler
! entries are then silently lost (that pre-emption is the defect itself).  It
! only rules out the vacuous run where the pages were accidentally mapped and
! nothing ever faulted, and it runs AFTER the register checks so a real defect
! reports as 2/3 rather than being masked by a count mismatch.
!
! ---- traps inherited from mmudrain.S / mmuimissrest.S (do not re-introduce) --
!  1. Do NOT identity-map down to VA 0: a VPN==0 entry makes the very first
!     D-side miss hang.  Map from `start`'s page; `start` is .balign PAGE_SZ.
!  2. The handler must install instruction (STUB) pages with U=0 (0xC8).  0xE8
!     sets U and a kernel fetch from a U=1 page is blocked by SMEP, so an IMISS
!     installed with 0xE8 re-faults forever.  Hence the layout contract:
!     [ code | _code_end | data pages ] and the handler picks flags by comparing
!     the faulting VA against _dpage_S0.  (This guard takes no I-side fault, but
!     the handler is kept VA-driven and identical to the rest of the suite.)
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   STC PTEH,r1 = 0x018B   LDC r0,VBR  = 0x402E   LDC r0,PTEH  = 0x405E
!   LDC r0,PTEL = 0x406E   LDC r0,ASIDR= 0x407E   LDTLB = 0x0038  LDTLB.RN = 0x0078
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; _fail still clamps r9==0
! to 0x7F.
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
#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_shl - 0x400. ----
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

        ! ================= THE WINDOW: two back-to-back faulting loads =======
        ! NOTHING between them.  No memory traffic of any kind until _verify_S.
        mov.l   @r2+, r12               ! DMISS_R on page0 -- the FAULT
        mov.l   @r3+, r13               ! issued in its shadow -- THE DEFECT
        ! ====================================================================
        nop
        nop
        nop
        nop
        nop
        nop
        bra     _verify_S
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_shl - 0x400
p_mmucr:        .long 0xFF000010
p_code_start:   .long start
p_code_end:     .long _code_end
p_code_flags:   .long 0x000000C8
p_page_sz:      .long PAGE_SZ
p_fc:           .long _fault_count
p_d0:           .long _dpage_S0
p_d1:           .long _dpage_S1

! ---------------------------------------------------------------------------
! Verification -- everything is deferred to here, on the far side of the window.
! ---------------------------------------------------------------------------
ENTRY(_verify_S)
        ! ---- layer 1 (exactly-once): each base ended at its OWN page + 4 ----
        ! low by 4  -> the access was DROPPED   (the Defect 2 signature)
        ! high by 4 -> the access was executed TWICE
        cmp/eq  r4, r2
        mov     #2, r9
        bt      1f
        ! Classifier: distinguish the two failure modes rather than reporting a
        ! bare "wrong".  0x20 = page0 (access DROPPED), 0x21 = page0+8 (executed
        ! TWICE), 0x22 = anything else.  0x21 is the Defect 3 signature: the
        ! restart re-executed the instruction BEFORE the faulting one.
        mov     r4, r0
        add     #-4, r0                 ! r0 = page0
        cmp/eq  r0, r2
        mov     #0x20, r9
        bt      _fail
        mov     r4, r0
        add     #4, r0                  ! r0 = page0+8
        cmp/eq  r0, r2
        mov     #0x21, r9
        bt      _fail
        mov     #0x22, r9
        bra     _fail
        nop
1:
        cmp/eq  r5, r3
        mov     #3, r9
        bt      2f
        bra     _fail
        nop
2:
        ! ---- layer 2: each load returned ITS OWN page's seeded value ----
        ! A phantom access at page1-4 reads page0's LAST word, so a wrong value
        ! here is independent evidence of the same mis-addressing.
        mov.l   q_v0, r0
        cmp/eq  r0, r12
        mov     #4, r9
        bt      3f
        bra     _fail
        nop
3:
        mov.l   q_v1, r0
        cmp/eq  r0, r13
        mov     #5, r9
        bt      4f
        bra     _fail
        nop
4:
        ! ---- layer 3: both pages really are installed and readable ----
        mov.l   q_d0, r0
        mov.l   @r0, r1
        mov.l   q_v0, r0
        cmp/eq  r0, r1
        mov     #6, r9
        bt      5f
        bra     _fail
        nop
5:
        mov.l   q_d1, r0
        mov.l   @r0, r1
        mov.l   q_v1, r0
        cmp/eq  r0, r1
        mov     #7, r9
        bt      6f
        bra     _fail
        nop
6:
        ! ---- non-vacuity (LOOSE lower bound; see the header) ----
        mov.l   q_fc, r0
        mov.l   @r0, r12
        sub     r11, r12                ! faults taken by this run
        mov     #1, r0
        cmp/ge  r0, r12                 ! T = (r12 >= 1)
        mov     #0x10, r9
        bt      7f
        bra     _fail
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
q_mmucr:        .long 0xFF000010
q_d0:           .long _dpage_S0
q_d1:           .long _dpage_S1
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

#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

        ! ---- VA-driven handler at VBR+0x400 (all six TLB fault kinds) ----
        ! Runs with SR.RB=1, so its bank-1 scratch does not touch the leg's
        ! bank-0 registers.
        .balign 4
        .space 0x400, 0
        .balign 4
_v_shl:
        .word   0x018B                  ! STC PTEH, r1 -- HW-captured faulting VPN
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
Hdbase:         .long _dpage_S0
Hcount:         .long _fault_count

        .balign 4
ENTRY(_fault_count)
        .long 0

        .balign 4
ENTRY(_code_end)                        ! everything above is identity-mapped code

! ======================= unmapped region starts here =======================
        .balign PAGE_SZ
_dpage_S0:  .long 0xD0000000
            .space PAGE_SZ - 4, 0

        .balign PAGE_SZ
_dpage_S1:  .long 0xD1111111
            .space PAGE_SZ - 4, 0

#endif
