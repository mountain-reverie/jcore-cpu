! mmuimissrest.S -- an I-side fetch miss must NOT restore a D-side @Rn+ base.
!
! DEFECT ISOLATED (Defect 1):
! core/datapath.vhm's fault-capture block arms the @Rn+ base restore from the
! ma_numz / ma_autoupd / ma_predec shadows.  Those shadows are written only at
! the memory-access pipeline point and are NEVER cleared on a non-memory
! instruction, and the arming block WAS NOT gated on tlb_exc_is_i (even though
! tlb_exc_is_i was used ~20 lines earlier to pick the restart PC); it now IS.
! Pre-fix, therefore, an
! INSTRUCTION-FETCH fault (IMISS/IPROT) inherits the last post-increment load's
! ma_numz plus a stale ma_autoupd='1', arms a bogus base restore, and
! restore_fire writes the I-side faulting FETCH VA into that GPR.
!
! Shape (deliberately minimal, see "second defect" below):
!   1. map the code pages, enable AT
!   2. ONE faulting post-increment load  `mov.l @r2+, r13`  (DMISS_R)
!   3. assert r2 == _dpage_M + 4        -- fail 2 (must already hold today;
!                                          this is mmuainc.S's property and it
!                                          proves the setup is sound)
!   4. jmp to an UNMAPPED stub page      (IMISS)
!   5. assert r2 is STILL _dpage_M + 4  -- fail 3  <== THE DEFECT
!
! Pre-fix, step 5 fails: r2 has been clobbered with the stub page's fetch VA.
!
! ---- why exactly ONE faulting load ----
! A SECOND defect exists (since FIXED, 84378f9): a train of back-to-back @Rn+
! loads lost every second access (tlb_squash killed the slot-0 base bump while
! the slot-1 access still issued at Rn-4).  mmudrain.S covers that.  To isolate
! Defect 1 cleanly this guard uses a single faulting post-increment load, well
! separated from any other memory traffic by nops.
!
! ---- non-vacuity ----
! The handler counts faults; the guard asserts count >= 2 (fail 0x10).  The
! check is deliberately LOOSE (>=, not ==): a handler-side counter is not a
! reliable exact oracle when faults pre-empt each other.  It only has to rule
! out the vacuous run where the pages were accidentally mapped and nothing ever
! faulted.  It runs AFTER the register checks so a real defect reports as 2/3
! rather than being masked by a count mismatch.
!
! ---- traps inherited from mmudrain.S (do not re-introduce) ----
!  1. Do NOT identity-map down to VA 0: a VPN==0 entry makes the very first
!     D-side miss hang.  Map from `start`'s page; `start` is .balign PAGE_SZ.
!  2. The handler must install instruction (STUB) pages with U=0 (0xC8).  0xE8
!     sets U and a kernel fetch from a U=1 page is blocked by SMEP, so an IMISS
!     installed with 0xE8 re-faults forever.  Hence the layout contract:
!     [ code | _code_end | stub page | data page ] -- stub BELOW the data pool,
!     and the handler picks flags by comparing the faulting VA against _dpage_M.
!
! Overlay .word encodings (the assembler does not know these J4 forms):
!   LDC r0,VBR  = 0x402E   LDC r0,PTEH  = 0x405E   (PTEH is READ via the
!   read-only P4 alias 0xFF000000, not STC)
!   LDC r0,ASIDR= 0x407E
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). SAME strength: both register
! assertions, the loose fault-count non-vacuity check and the layout contract
! are untouched. Only the install path moves -- the setup loop publishes a TSB
! ROW per code page, and the demand-paging handler publishes the faulting
! page's row (through the P1 alias, because AT is on and the TSB itself is
! unmapped) and returns with a plain RTE instead of LDTLB.RN. The stub-page
! U=0 half of the layout contract is unchanged and, if anything, more
! load-bearing: the row is what SMEP now judges.
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS; _fail still clamps r9==0
! to 0x7F.
#include "sim_instr.h"
#include "mmuwalk_common.inc"
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

        ! ---- VBR = _v_imr - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Publish a TSB row for every code page: start .. _code_end. ----
        ! TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x 32 bytes),
        ! HASH_SHIFT=6, HASH_MODE=1; set addresses come from the P4 helper at
        ! 0xFF000048. AT is off here, so these are plain P0 stores.
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR  (ASID 0 throughout)
        nop
        nop
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        mov.l   p_tsbslot, r12
        mov.l   p_code_start, r2
        mov.l   p_code_end, r3
1:      mov.l   r2, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        mov.l   p_code_flags, r1
        mov     r2, r0
        or      r1, r0                  ! PTEL = page | 0xC9 (kernel code, U clear)
        mov     r0, r8
        mov     #0, r7                  ! ASID_TAG = 0
        tsb_fill r10, r2, r7, r8
        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- snapshot the fault count ----
        mov.l   p_fc, r0
        mov.l   @r0, r11

        ! ================= the single faulting post-increment load ==========
        ! CRITICAL WINDOW: nothing between the faulting @r2+ load and the jmp
        ! may touch memory.  ma_autoupd is (re)written at the memory-access
        ! pipeline point, so ANY intervening access -- including an innocent
        ! PC-relative literal load -- clears the stale shadow and hides the
        ! defect.  Everything the window needs is therefore staged into
        ! registers FIRST, and both assertions are deferred to _verify_M.
        mov.l   p_dpage, r2             ! r2 = unmapped data page (the base)
        mov.l   p_stub, r14             ! r14 = the unmapped stub page
        mov.l   p_dpage, r8             ! r8 = expected post-increment value
        add     #4, r8
        nop
        nop
        nop
        mov.l   @r2+, r13               ! DMISS_R -> handler installs -> LDTLB.RN
        nop
        nop
        nop
        nop
        nop
        nop
        mov     r2, r3                  ! register-only snapshot of r2 pre-IMISS
        nop
        nop
        ! ================= the I-side fetch miss (the drain) ================
        jmp     @r14                    ! IMISS on the unmapped stub page
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_imr - 0x400
p_mmucr:        .long 0xFF000010
p_code_start:   .long start
p_code_end:     .long _code_end
p_code_flags:   .long 0x000000C9        ! W|X|C|V, U clear (SMEP: fetched pages)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_page_sz:      .long PAGE_SZ
p_fc:           .long _fault_count
p_stub:         .long _stub_M
p_dpage:        .long _dpage_M

! ---------------------------------------------------------------------------
! Verification, on the far side of the IMISS stub.
! ---------------------------------------------------------------------------
ENTRY(_verify_M)
        ! ---- assert 1: the post-increment happened exactly once, pre-IMISS ---
        ! r3 is the register-only snapshot taken before the jmp, r8 the expected
        ! value; both were computed with no memory traffic in the window.
        ! (mmuainc.S's property; must already hold today.  If THIS fails the
        !  setup is broken, not Defect 1.)
        cmp/eq  r8, r3
        mov     #2, r9
        bt      1f
        bra     _fail
        nop
1:
        ! ---- assert 2 (THE DEFECT): r2 must be untouched by the I-fault ----
        ! Pre-fix r2 holds the stub page's faulting FETCH VA instead.
        cmp/eq  r8, r2
        mov     #3, r9
        bt      2f
        bra     _fail
        nop
2:
        ! ---- non-vacuity: at least the DMISS + the IMISS must have fired ----
        ! Loose (>=): a handler-side counter is not an exact oracle when faults
        ! pre-empt each other.  This only rules out "pages were already mapped".
        mov.l   q_fc, r0
        mov.l   @r0, r12
        sub     r11, r12                ! r12 = faults taken by this run
        mov     #2, r0
        cmp/ge  r0, r12                 ! T = (r12 >= 2)
        mov     #0x10, r9
        bt      3f
        bra     _fail
        nop
3:
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
_v_imr:
        mov.l   Hpteh_a, r1
        mov.l   @r1, r1                 ! r1 = PTEH (P4 alias) -- HW-captured faulting VPN
        mov.l   Hpagemask, r0
        and     r0, r1                  ! r1 = page base
        ! Layout contract: the stub page sits BELOW the data page, so a fault
        ! under _dpage_M is an I-side stub fetch and must be installed with U=0
        ! -- 0xE8 (U=1) there makes the kernel fetch fault forever under SMEP.
        mov.l   Hdbase, r0
        cmp/hs  r0, r1                  ! T = (page >= data page)
        bt      1f
        mov.l   Hcflags, r0             ! stub page: 0xC9 (kernel code, U clear)
        bra     2f
        nop
1:      mov.l   Hflags, r0              ! data page: 0xE9
2:      or      r1, r0                  ! PTEL = page | flags
        mov     r0, r4                  ! r4 = PTEL

        ! Publish the row for this page. The set address comes from the P4
        ! helper and is addressed THROUGH P1: AT is on and the TSB is unmapped,
        ! so a P0 store from the handler would fault inside the handler.
        mov.l   Hslot, r0
        mov.l   r1, @r0                 ! r1 = page base (the row's VA key)
        mov.l   @r0, r3
        mov.l   Hp1, r0
        or      r0, r3
        mov     #0, r5                  ! ASID_TAG = 0
        mov.l   r4, @(8, r3)            ! data first ...
        mov.l   r5, @(4, r3)            ! ... tag_lo second ...
        mov.l   r1, @(0, r3)            ! ... tag_hi LAST (the commit point)

        mov.l   Hcount, r0              ! non-vacuity: count this fault
        mov.l   @r0, r2
        add     #1, r2
        mov.l   r2, @r0
        rte                             ! retry: the walker installs the row
        nop
_h_fail_spin:
        bra     _h_fail_spin
        nop
        .align 2
Hpagemask:      .long 0xFFFFF000
Hpteh_a:        .long 0xFF000000
Hflags:         .long 0x000000E9        ! data page: W|X|U|C|V
Hcflags:        .long 0x000000C9        ! stub page: W|X|C|V, U clear
Hslot:          .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
Hp1:            .long 0x80000000
Hdbase:         .long _dpage_M
Hcount:         .long _fault_count

        .balign 4
ENTRY(_fault_count)
        .long 0

        .balign 4
ENTRY(_code_end)                        ! everything above is identity-mapped code

! ======================= unmapped region starts here =======================
        .balign PAGE_SZ
_stub_M:                                ! own unmapped page -> IMISS on entry
        mov.l   sM_back, r10
        jmp     @r10
        nop
        .align 2
sM_back:        .long _verify_M

        .balign PAGE_SZ
_dpage_M:   .long 0xD0000000
            .space PAGE_SZ - 4, 0

        ! ---- The image must reach past the END of the TSB (PA 0x14000..
        ! ---- 0x15FFF): the walker reads the TSB by PHYSICAL address and a
        ! ---- physical alias is backed by SRAM only within the loaded image.
_tsb_backing:
        .space 0x16000, 0

#endif
