! mmushadowst.S -- a STORE issued in a TLB fault's shadow must not reach memory.
!
! THE UNTESTED HALF.  Defect 2 (see mmushadowld.S) was that tlb_squash
! suppressed the GPR writebacks of shadow instructions but NOT their memory
! accesses (the memory-issue block now also carries `and tlb_squash_r = '0'`).
! The load side is self-masking in the common case (a dropped/duplicated load is
! only visible through the @Rn+ base), so it took a ten-deep train to surface.
! The STORE side is the more serious half and was covered NOWHERE in the suite
! before this guard: a shadow store WRITES MEMORY, and a write cannot be taken
! back by the restart.
!
! ---- making a shadow store DETECTABLE (the hard part) ----
! A plain store re-executed after the restart writes the same value to the same
! address, so it is IDEMPOTENT and therefore INVISIBLE -- a naive "store twice
! and check the word" guard passes pre-fix and proves nothing.  The tripwire has
! to be an address that ONLY the shadow execution can touch:
!
!   mov.l   @r2+, r6        ! DMISS_R -- the FAULT.  r6 := the real target
!                           !   address, but the writeback is SQUASHED, so r6
!                           !   still holds the DECOY address at this point.
!   mov.l   r7, @r6         ! issued in the fault's shadow.  Pre-fix its access
!                           !   is NOT squashed, so it writes r7 through the
!                           !   STALE r6 -- i.e. into the DECOY word.
!
! After the restart r6 holds the real target and the store lands correctly, so
! the TARGET word is right either way.  The DECOY word is the oracle:
!   decoy != sentinel  -> a shadow store reached memory   (THE DEFECT)
!   decoy == sentinel  -> no access was issued in the shadow (correct)
! A guard word immediately after the target catches an off-by-one/size error,
! and the target word itself catches a lost store.
!
! Both the decoy and the target live in the ALREADY-MAPPED code region, so the
! shadow store takes no fault of its own -- it just silently corrupts.  That is
! exactly the scenario the fix must eliminate: an instruction in the fault
! shadow is going to be re-executed after the restart, so it must issue no
! access at all.
!
! ---- CRITICAL TEST-CONSTRUCTION HAZARD (learned on the Defect 1 guard) ----
! ma_autoupd and friends are rewritten at the MEMORY-ACCESS pipeline point, so
! ANY intervening memory access -- including an innocent PC-relative literal
! load (`mov.l label, rN`) -- between the faulting access and the instruction
! under test clears the stale shadow and HIDES the defect.  Everything the
! window needs is staged into registers BEFORE the window and every assertion is
! deferred to _verify_T.
!
! ---- non-vacuity ----
! The handler counts faults; the guard asserts count >= 1 (fail 0x10), LOOSE by
! design -- faults pre-empt each other so a handler-side counter under-reports
! and is never used as the primary oracle.  It only rules out the vacuous run
! where the data page was accidentally mapped and nothing ever faulted.  It runs
! AFTER the memory checks so a real defect reports as 2/3/4.
!
! ---- traps inherited from mmudrain.S / mmuimissrest.S (do not re-introduce) --
!  1. Do NOT identity-map down to VA 0: a VPN==0 entry makes the very first
!     D-side miss hang.  Map from `start`'s page; `start` is .balign PAGE_SZ.
!  2. Install code/stub pages with U=0 (0xC8); 0xE8 sets U and SMEP blocks the
!     kernel fetch forever.  The handler picks flags by comparing the faulting
!     VA against the data pool base.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   STC PTEH,r1 = 0x0153   LDC r0,VBR  = 0x402E   LDC r0,PTEH  = 0x405E
!   LDC r0,PTEL = 0x406E   LDC r0,ASIDR= 0x407E   LDTLB = 0x0038  LDTLB.RN = 0x0078
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; _fail still clamps r9==0
! to 0x7F.
#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

#define PAGE_SZ  0x1000

#define SENTINEL 0xA5A5A5A5             ! decoy pre-seed -- must survive
#define GUARDVAL 0x5A5A5A5A             ! word after the target -- must survive
#define STVAL    0x1234ABCD             ! the value the store writes

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

        ! ---- VBR = _v_sht - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Identity-map every code page: start .. _code_end. ----
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

        ! ---- Seed the tripwires (still with AT off -- these are mapped 1:1). --
        mov.l   p_decoy, r0
        mov.l   p_sentinel, r1
        mov.l   r1, @r0                 ! decoy  = SENTINEL
        mov.l   p_target, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! target = 0
        mov.l   p_tguard, r0
        mov.l   p_guardval, r1
        mov.l   r1, @r0                 ! target+4 = GUARDVAL

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- snapshot the fault count ----
        mov.l   p_fc, r0
        mov.l   @r0, r11

        ! ---- stage EVERYTHING the window needs (see the hazard note above) ----
        ! The unmapped data page's first word holds the REAL target address, so
        ! the faulting load is what produces the store's address register.
        mov.l   p_dpage, r2             ! r2 = unmapped data page (the fault)
        mov.l   p_decoy, r6             ! r6 = DECOY -- the stale address that a
                                        !      shadow store would write through
        mov.l   p_stval, r7             ! r7 = the value to store
        mov.l   p_target, r10           ! expected r6 after the restart
        mov.l   p_dpage, r8             ! expected r2 afterwards = page + 4
        add     #4, r8
        nop
        nop
        nop

        ! ================= THE WINDOW ========================================
        mov.l   @r2+, r6                ! DMISS_R -- the FAULT.  r6 := target,
                                        !   but the writeback is squashed, so in
                                        !   the shadow r6 still reads DECOY.
        mov.l   r7, @r6                 ! shadow STORE -- must issue NO access.
        ! ====================================================================
        nop
        nop
        nop
        nop
        nop
        nop
        bra     _verify_T
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_sht - 0x400
p_mmucr:        .long 0xFF000010
p_code_start:   .long start
p_code_end:     .long _code_end
p_code_flags:   .long 0x000000C8
p_page_sz:      .long PAGE_SZ
p_fc:           .long _fault_count
p_dpage:        .long _dpage_T
p_decoy:        .long _decoy
p_target:       .long _target
p_tguard:       .long _target + 4
p_sentinel:     .long SENTINEL
p_guardval:     .long GUARDVAL
p_stval:        .long STVAL

! ---------------------------------------------------------------------------
! Verification -- deferred to the far side of the window.
! ---------------------------------------------------------------------------
ENTRY(_verify_T)
        ! ---- layer 1 (THE ORACLE): the decoy word must be UNTOUCHED ----
        ! Only a store issued in the fault shadow, through the stale r6, can
        ! reach this address.  Pre-fix it holds STVAL instead of SENTINEL.
        mov.l   q_decoy, r0
        mov.l   @r0, r1
        mov.l   q_sentinel, r0
        cmp/eq  r0, r1
        mov     #2, r9
        bt      1f
        bra     _fail
        nop
1:
        ! ---- layer 2: the store landed EXACTLY ONCE, at the right address ----
        mov.l   q_target, r0
        mov.l   @r0, r1
        mov.l   q_stval, r0
        cmp/eq  r0, r1
        mov     #3, r9
        bt      2f
        bra     _fail
        nop
2:
        ! ---- layer 3: the neighbouring word is untouched (size/off-by-one) ----
        mov.l   q_tguard, r0
        mov.l   @r0, r1
        mov.l   q_guardval, r0
        cmp/eq  r0, r1
        mov     #4, r9
        bt      3f
        bra     _fail
        nop
3:
        ! ---- layer 4: the faulting load itself was precise (@Rn+ exactly once)
        cmp/eq  r8, r2
        mov     #5, r9
        bt      4f
        bra     _fail
        nop
4:
        ! ---- layer 5: the load did deliver the real target address to r6 ----
        cmp/eq  r10, r6
        mov     #6, r9
        bt      5f
        bra     _fail
        nop
5:
        ! ---- non-vacuity (LOOSE lower bound; see the header) ----
        mov.l   q_fc, r0
        mov.l   @r0, r12
        sub     r11, r12                ! faults taken by this run
        mov     #1, r0
        cmp/ge  r0, r12                 ! T = (r12 >= 1)
        mov     #0x10, r9
        bt      6f
        bra     _fail
        nop
6:
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
q_decoy:        .long _decoy
q_target:       .long _target
q_tguard:       .long _target + 4
q_sentinel:     .long SENTINEL
q_guardval:     .long GUARDVAL
q_stval:        .long STVAL

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
        .balign 4
        .space 0x400, 0
        .balign 4
_v_sht:
        .word   0x0153                  ! STC PTEH, r1 -- HW-captured faulting VPN
        mov.l   Hpagemask, r0
        and     r0, r1                  ! r1 = page base
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
Hdbase:         .long _dpage_T
Hcount:         .long _fault_count

        .balign 4
ENTRY(_fault_count)
        .long 0

        ! ---- the tripwires: mapped, writable, inside the code region ----
        .balign 4
_decoy:         .long 0                 ! seeded SENTINEL; must survive
_target:        .long 0                 ! must end up == STVAL
                .long 0                 ! seeded GUARDVAL; must survive

        .balign 4
ENTRY(_code_end)                        ! everything above is identity-mapped code

! ======================= unmapped region starts here =======================
        .balign PAGE_SZ
_dpage_T:   .long _target               ! first word = the REAL store address
            .space PAGE_SZ - 4, 0

#endif
