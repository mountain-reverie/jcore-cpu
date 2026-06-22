! mmufault.S -- comprehensive TLB fault coverage test (J4 + MMU_ARCH).
!
! Exercises all six TLB fault kinds, asserting EXPEVT, TEA, and correct
! access-type vector for each.
!
! VBR layout strategy (no stubs, no dispatch indirection):
!   Set VBR = _v_ifetch - 0x400 so:
!     VBR+0x400 = _v_ifetch  (I-fetch handler:  IMISS=0x040, IPROT=0x0A0)
!     VBR+0x420 = _v_load    (D-load handler:   DMISS_R=0x060, DPROT_R=0x0C0)
!     VBR+0x440 = _v_store   (D-store handler:  DMISS_W=0x080, DPROT_W=0x0C0)
!
!   Each handler block is exactly 0x20 bytes (16 instructions):
!     disable AT + check EXPEVT + check TEA + set SPC=resume + RTE
!   They are placed with explicit .space to enforce the 0x20 spacing.
!   All three reside in the code section (page 0, VA 0x0000-0x0FFF).
!
! All TLB exceptions save SPC<-PC-2 (faulting instruction restart).
! The handler overwrites SPC with the per-sub-test resume label and RTE,
! returning to the correct place in the main test body.
!
! Addressing model (cpu_ctb bus):
!   Binary image mapped flat at VA 0. Page 0 (0x0000-0x0FFF) identity-mapped
!   in TLB (W+X+U+C=0xE8). Pages 1-4 (0x1000-0x4FFF) padded with zeros so
!   bus does not fault before the TLB exception fires.  Pages 2-4 are
!   installed with restricted permissions for protection tests.
!
! PTEL flag bit layout (core/tlb.vhd lines 120-126):
!   bit7=W  bit6=X  bit5=U  bit4=D  bit3=C
!   page 0 full-access : W|X|U|C = 0xE8
!   page 2 read-only   : X|U|C   = 0x68  (W=0 -> DPROT_W on store)
!   page 3 no-execute  : W|U|C   = 0xA8  (X=0 -> IPROT  on fetch)
!   page 4 super-only  : W|X|C   = 0xC8  (U=0 -> DPROT_R on user load)
!
! Fault class coverage:
!   DMISS_R (0x060) A -- runtime, supervisor, load  from page 1 (unmapped)
!   DMISS_W (0x080) B -- runtime, supervisor, store to   page 1 (unmapped)
!   IMISS   (0x040) C -- runtime, supervisor, jump  to   page 1 (unmapped)
!   DPROT_W (0x0C0) D -- runtime, supervisor, store to   page 2 (W=0)
!   IPROT   (0x0A0) E -- runtime, USER MODE, jump   to   page 3 (X=0)
!   DPROT_R (0x0C0) F -- runtime, USER MODE, load   from page 4 (U=0)
!
!   IPROT and DPROT_R require user mode (MD=0) because in supervisor the
!   only supervisor-reachable D-prot path is d_we=1 AND w=0 (DPROT_W).
!   The I-prot x=0 path fires in any mode; we use user mode for broader
!   coverage. User-mode entry: clear SR.MD (bit 30) as in privmode.S.
!   Exception entry (PM2/PM3 register model) restores MD=1 via SSR.
!
! Result codes:
!   0  all pass
!   1  A: no exception    2  A: EXPEVT!=0x060    3  A: TEA!=0x1000
!   4  B: no exception    5  B: EXPEVT!=0x080    6  B: TEA!=0x1000
!   7  C: no exception    8  C: EXPEVT!=0x040    9  C: TEA!=0x1000
!  10  D: no exception   11  D: EXPEVT!=0x0C0   12  D: TEA!=0x2000
!  13  E: no exception   14  E: EXPEVT!=0x0A0   15  E: TEA!=0x3000
!  16  F: no exception   17  F: EXPEVT!=0x0C0   18  F: TEA!=0x4000
!
! J4 overlay opcodes:
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E
!   STC EXPEVT,r0=0x0052
!   STC SPC,r0=0x0042   LDC r0,SPC=0x404E

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

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
ENTRY(start)
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_ifetch - 0x400 (so VBR+0x400=_v_ifetch). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ==============================================================
        ! Sub-test A: DMISS_R (EXPEVT=0x060) -> VBR+0x420 (_v_load)
        ! Load from VA 0x1000 (page 1: in bus range, not in TLB).
        ! ==============================================================
        mov.l   p_g_exp_expevt, r0
        mov.l   c_dmiss_r, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x060
        mov.l   p_g_exp_tea, r0
        mov.l   c_page1_va, r1
        mov.l   r1, @r0                 ! g_exp_tea    = 0x1000
        mov.l   p_g_bad_expevt, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 2
        mov.l   p_g_bad_tea, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! TEA wrong    -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_after_a, r1
        mov.l   r1, @r0                 ! resume -> after_a

        mov     #1, r9                  ! sentinel: no exception = result 1
        mov.l   c_page1_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (VBR+0x420), DMISS_R

        bra     _fail
        nop

ENTRY(after_a)
        ! ==============================================================
        ! Sub-test B: DMISS_W (EXPEVT=0x080) -> VBR+0x440 (_v_store)
        ! Store to VA 0x1000 (page 1, unmapped).
        ! ==============================================================
        ! Handler disabled AT; re-enable so the store below faults via MMU.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! MMUCR = 1 (AT=1)

        mov.l   p_g_exp_expevt, r0
        mov.l   c_dmiss_w, r1
        mov.l   r1, @r0
        mov.l   p_g_exp_tea, r0
        mov.l   c_page1_va, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_expevt, r0
        mov     #5, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_tea, r0
        mov     #6, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_b, r1
        mov.l   r1, @r0

        mov     #4, r9
        mov     #0x55, r3
        mov.l   c_page1_va, r2
        mov.l   r3, @r2                 ! FAULTS -> _v_store (VBR+0x440), DMISS_W

        bra     _fail
        nop

ENTRY(after_b)
        ! ==============================================================
        ! Sub-test C: IMISS (EXPEVT=0x040) -> VBR+0x400 (_v_ifetch)
        ! Jump to VA 0x1000 (page 1, unmapped) -> I-fetch miss.
        ! ==============================================================
        ! Handler disabled AT; re-enable so the jump below faults via MMU.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! MMUCR = 1 (AT=1)

        mov.l   p_g_exp_expevt, r0
        mov.l   c_imiss, r1
        mov.l   r1, @r0
        mov.l   p_g_exp_tea, r0
        mov.l   c_page1_va, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_expevt, r0
        mov     #8, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_tea, r0
        mov     #9, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_c, r1
        mov.l   r1, @r0

        mov     #7, r9
        mov.l   c_page1_va, r0
        jmp     @r0                     ! FAULTS -> _v_ifetch (VBR+0x400), IMISS
        nop

        bra     _fail
        nop

ENTRY(after_c)
        ! ==============================================================
        ! Sub-test D: DPROT_W (EXPEVT=0x0C0) -> VBR+0x440 (_v_store)
        ! Map page 2 (VA 0x2000) read-only (W=0, X|U|C = 0x68).
        ! Supervisor: d_we=1 AND w=0 fires DPROT_W (no user mode needed).
        ! ==============================================================
        mov.l   c_page2_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=2, ASID=0)
        mov.l   p_ptel_ro, r0
        .word   0x406E                  ! LDC r0, PTEL = 0x68
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! Handler disabled AT on entry; re-enable.
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov.l   p_g_exp_expevt, r0
        mov.l   c_dprot, r1
        mov.l   r1, @r0                 ! 0x0C0
        mov.l   p_g_exp_tea, r0
        mov.l   c_page2_va, r1
        mov.l   r1, @r0                 ! 0x2000
        mov.l   p_g_bad_expevt, r0
        mov     #11, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_tea, r0
        mov     #12, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_d, r1
        mov.l   r1, @r0

        mov     #10, r9
        mov     #0x66, r3
        mov.l   c_page2_va, r2
        mov.l   r3, @r2                 ! FAULTS -> _v_store (VBR+0x440), DPROT_W

        bra     _fail
        nop

ENTRY(after_d)
        ! ==============================================================
        ! Sub-test E: IPROT (EXPEVT=0x0A0) -> VBR+0x400 (_v_ifetch)
        ! Map page 3 (VA 0x3000) no-execute (X=0, W|U|C = 0xA8).
        ! Drop to user mode; I-prot fires when x=0.
        ! ==============================================================
        mov.l   c_page3_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=3, ASID=0)
        mov.l   p_ptel_nx, r0
        .word   0x406E                  ! LDC r0, PTEL = 0xA8
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT

        mov.l   p_g_exp_expevt, r0
        mov.l   c_iprot, r1
        mov.l   r1, @r0                 ! 0x0A0
        mov.l   p_g_exp_tea, r0
        mov.l   c_page3_va, r1
        mov.l   r1, @r0                 ! 0x3000
        mov.l   p_g_bad_expevt, r0
        mov     #14, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_tea, r0
        mov     #15, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_e, r1
        mov.l   r1, @r0

        ! Drop to user mode (clear SR.MD = bit 30 = 0x40000000).
        stc     sr, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr                  ! MD=0 after this
        nop
        nop
        nop
        nop

        ! In user mode: jump to VA 0x3000 (X=0) -> IPROT.
        mov     #13, r9
        mov.l   c_page3_va, r0
        jmp     @r0                     ! FAULTS -> _v_ifetch (VBR+0x400), IPROT
        nop

        bra     _fail
        nop

ENTRY(after_e)
        ! ==============================================================
        ! Sub-test F: DPROT_R (EXPEVT=0x0C0) -> VBR+0x420 (_v_load)
        ! Map page 4 (VA 0x4000) supervisor-only (U=0, W|X|C = 0xC8).
        ! Drop to user mode; D-prot fires when u=0 AND md=0 on load.
        ! ==============================================================
        mov.l   c_page4_pteh, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=4, ASID=0)
        mov.l   p_ptel_super, r0
        .word   0x406E                  ! LDC r0, PTEL = 0xC8
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! re-enable AT

        mov.l   p_g_exp_expevt, r0
        mov.l   c_dprot, r1
        mov.l   r1, @r0                 ! 0x0C0
        mov.l   p_g_exp_tea, r0
        mov.l   c_page4_va, r1
        mov.l   r1, @r0                 ! 0x4000
        mov.l   p_g_bad_expevt, r0
        mov     #17, r1
        mov.l   r1, @r0
        mov.l   p_g_bad_tea, r0
        mov     #18, r1
        mov.l   r1, @r0
        mov.l   p_g_resume, r0
        mov.l   p_after_f, r1
        mov.l   r1, @r0

        ! Drop to user mode.
        stc     sr, r3
        mov.l   p_mdmask, r4
        and     r4, r3
        ldc     r3, sr                  ! MD=0 after this
        nop
        nop
        nop
        nop

        ! In user mode: load from VA 0x4000 (U=0) -> DPROT_R.
        mov     #16, r9
        mov.l   c_page4_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (VBR+0x420), DPROT_R

        bra     _fail
        nop

ENTRY(after_f)
        bra     _done
        nop

        ! ============================================================
        ! Pointer literals used by main body.
        ! ============================================================
        .align 2
p_rbclear:          .long 0xDFFFFFFF
p_mdmask:           .long 0xBFFFFFFF
p_vbr_val:          .long _v_ifetch - 0x400 ! VBR so VBR+0x400 = _v_ifetch
p_mmucr:            .long 0xFF000010
p_ptel_page0:       .long 0x000000E8   ! W|X|U|C
p_ptel_ro:          .long 0x00000068   ! X|U|C  (W=0 -> DPROT_W)
p_ptel_nx:          .long 0x000000A8   ! W|U|C  (X=0 -> IPROT)
p_ptel_super:       .long 0x000000C8   ! W|X|C  (U=0 -> DPROT_R)
! handler globals
p_g_exp_expevt:     .long _g_exp_expevt
p_g_exp_tea:        .long _g_exp_tea
p_g_resume:         .long _g_resume
p_g_bad_expevt:     .long _g_bad_expevt
p_g_bad_tea:        .long _g_bad_tea
! resume labels
p_after_a:          .long after_a
p_after_b:          .long after_b
p_after_c:          .long after_c
p_after_d:          .long after_d
p_after_e:          .long after_e
p_after_f:          .long after_f
! EXPEVT codes
c_imiss:            .long 0x00000040
c_dmiss_r:          .long 0x00000060
c_dmiss_w:          .long 0x00000080
c_iprot:            .long 0x000000A0
c_dprot:            .long 0x000000C0
! VA / PTEH constants
c_page1_va:         .long 0x00001000
c_page2_va:         .long 0x00002000
c_page3_va:         .long 0x00003000
c_page4_va:         .long 0x00004000
c_page2_pteh:       .long 0x00002000
c_page3_pteh:       .long 0x00003000
c_page4_pteh:       .long 0x00004000
! P4 TEA register
p_h_tea_addr:       .long 0xFF00000C

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ================================================================
        ! Three VBR entry handlers placed at exactly VBR+0x400/0x420/0x440.
        !
        ! Handler body (must fit in <= 0x20 bytes = 16 instructions each):
        !   1. disable AT (store 0 to MMUCR via r0/r1)                 3 instrs
        !   2. STC EXPEVT, r0                                           1 word
        !   3. load g_exp_expevt -> r1, compare                        2 instrs + bf  = 3
        !   4. load TEA from P4, load g_exp_tea -> r1, compare         5 instrs + bf  = 7
        !   5. load g_resume -> r0, LDC r0, SPC, RTE + nop             4 instrs
        !   Total: 3+1+3+7+4 = 18 instrs - exceeds 16!
        !
        ! Plan: Each handler disables AT and then branches (bra + delay
        ! slot nop) to a SHARED handler body. The bra is a PC-relative
        ! short branch (within +-0x7FF bytes). The shared body sits
        ! immediately before _v_ifetch (NOT between handlers) so it's
        ! not subject to the 0x20 constraint.
        !
        ! Stub layout (exactly 0x20 bytes = 16 instructions = 32 bytes):
        !   disable AT inline (requires 0xFF000010 literal -> 16 bytes):
        !     mov.l Lmmucr_N, r0   [2 bytes] (offset to literal: 16-4=12 bytes ahead)
        !     mov   #0, r1         [2 bytes]
        !     mov.l r1, @r0        [2 bytes] -- MMUCR = 0
        !     bra   _handler_body  [2 bytes]
        !     nop                  [2 bytes] (delay slot)
        !     nop                  [2 bytes] (pad to 4-byte align for literal)
        !   Lmmucr_N: .long 0xFF000010  [4 bytes]
        !   .space 16, 0               [16 bytes padding to fill 0x20]
        ! Total = 2+2+2+2+2+2+4+16 = 32 = 0x20 bytes. ✓
        !
        ! Wait: the original test reads EXPEVT IMMEDIATELY after AT
        ! disable (directly inside the handler, no bra). Perhaps the
        ! BRA to _handler_body introduces extra cycles that lose EXPEVT.
        !
        ! ALTERNATIVE: fit the EXPEVT read + compare INTO the stub,
        ! and handle pass/fail divergence after the stub.
        !
        ! Minimal stub that reads+compares EXPEVT:
        !   mov.l Lmmucr, r0                        [2] -> disable AT
        !   mov   #0, r1                             [2]
        !   mov.l r1, @r0                            [2] -- AT=0
        !   .word 0x0052 (STC EXPEVT, r0)            [2] -- read EXPEVT
        !   Total so far: 8 bytes; literal needed nearby.
        !   Then: mov.l Lexp, r1; cmp/eq r0,r1; bf _h_bad_expevt
        !         mov.l Ltea_addr, r0; mov.l @r0, r2
        !         mov.l Lexp_tea, r3; cmp/eq r3,r2; bf _h_bad_tea
        !         mov.l Lresume, r0; mov.l @r0, r0; .word 0x404E; rte; nop
        !   = 12 more instrs = 24 bytes. Total = 8+24 = 32 bytes + 4 literals.
        !   But 4 literals (MMUCR, g_exp_expevt ptr, TEA addr, g_resume ptr)
        !   = 16 bytes of literals. The literals must be in PC-rel range
        !   (0-1020 bytes from the instruction). They can be AFTER the handlers
        !   or before them. 32 bytes handler + literals after = fine.
        !
        !   However: each literal is accessed from a different handler (each
        !   handler is 0x20 apart). The SAME literal constants can be shared.
        !   Place a SHARED literal pool after the three stubs.
        !
        ! Revised layout (each stub is 0x20 bytes = all instructions, NO local literal):
        !   The literal pool is placed immediately after _v_store (at _v_ifetch+0x60+).
        !   Each stub uses mov.l @(disp,PC) to reach shared literals.
        !   _v_ifetch is at address X. Literals are at X+0x60 or thereabouts.
        !   From _v_ifetch: disp = (X+0x60 - (X+4))/4 = 0x5C/4 = 23. ✓ (0-255 range)
        !   From _v_load (X+0x20): disp = (X+0x60 - (X+0x20+4))/4 = 0x3C/4 = 15. ✓
        !   From _v_store (X+0x40): disp = (X+0x60 - (X+0x40+4))/4 = 0x1C/4 = 7. ✓
        !   All within range!
        !
        ! Stub body (16 instrs = 0x20 bytes, literals shared after _v_store):
        !   +0  mov.l Hmmucr, r0      [2] -- MMUCR ptr
        !   +2  mov   #0, r1          [2]
        !   +4  mov.l r1, @r0         [2] -- disable AT
        !   +6  .word 0x0052          [2] -- STC EXPEVT, r0
        !   +8  mov.l Hexp_expevt, r1 [2] -- g_exp_expevt ptr
        !  +10  mov.l @r1, r1         [2] -- expected EXPEVT
        !  +12  cmp/eq r0, r1         [2] -- T if EXPEVT correct
        !  +14  bf _h_bad_expevt      [2]
        !  +16  mov.l Htea_addr, r0   [2] -- TEA P4 addr
        !  +18  mov.l @r0, r2         [2] -- r2 = TEA
        !  +20  mov.l Hexp_tea, r1    [2] -- g_exp_tea ptr
        !  +22  mov.l @r1, r1         [2] -- expected TEA
        !  +24  cmp/eq r1, r2         [2] -- T if TEA correct
        !  +26  bf _h_bad_tea         [2]
        !  +28  bra _h_resume         [2] -- common resume path
        !  +30  nop                   [2]
        !   = 16 instructions = 32 bytes = 0x20 ✓
        !
        ! Shared literal pool (at _v_ifetch + 0x60, must be 4-byte aligned):
        !   Hmmucr:        .long 0xFF000010
        !   Hexp_expevt:   .long _g_exp_expevt
        !   Htea_addr:     .long 0xFF00000C
        !   Hexp_tea:      .long _g_exp_tea
        !   = 16 bytes
        !
        ! Common handlers:
        !   _h_resume: loads g_resume, sets SPC, RTE
        !   _h_bad_expevt / _h_bad_tea: loads fail code, branches to _fail
        !
        ! PC-relative disp for Hmmucr from _v_ifetch (at offset X+0):
        !   instruction at +0, PC at +4, literal at X+0x60.
        !   disp = (X+0x60 - (X+4)) / 4 = 0x5C/4 = 23. ✓
        ! ================================================================

        .balign 4
_v_ifetch:                             ! = VBR + 0x400
        mov.l   Hmmucr, r0             ! +0  load MMUCR addr
        mov     #0, r1                 ! +2
        mov.l   r1, @r0               ! +4  MMUCR = 0 (disable AT)
        .word   0x0052                 ! +6  STC EXPEVT, r0
        mov.l   Hexp_expevt, r1        ! +8  r1 = &g_exp_expevt
        mov.l   @r1, r1                ! +10 r1 = expected EXPEVT
        cmp/eq  r0, r1                 ! +12 T if match
        bf      _h_bad_expevt          ! +14
        mov.l   Htea_addr, r0          ! +16 r0 = &TEA
        mov.l   @r0, r2               ! +18 r2 = TEA
        mov.l   Hexp_tea, r1           ! +20 r1 = &g_exp_tea
        mov.l   @r1, r1                ! +22 r1 = expected TEA
        cmp/eq  r1, r2                 ! +24 T if match
        bf      _h_bad_tea             ! +26
        bra     _h_resume              ! +28
        nop                            ! +30

_v_load:                               ! = VBR + 0x420 = _v_ifetch + 0x20
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        .word   0x0052                 ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Htea_addr, r0
        mov.l   @r0, r2
        mov.l   Hexp_tea, r1
        mov.l   @r1, r1
        cmp/eq  r1, r2
        bf      _h_bad_tea
        bra     _h_resume
        nop

_v_store:                              ! = VBR + 0x440 = _v_ifetch + 0x40
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        .word   0x0052                 ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Htea_addr, r0
        mov.l   @r0, r2
        mov.l   Hexp_tea, r1
        mov.l   @r1, r1
        cmp/eq  r1, r2
        bf      _h_bad_tea
        bra     _h_resume
        nop

        ! ---- Shared literal pool (at _v_ifetch + 0x60, 4-byte aligned) ----
        .balign 4
Hmmucr:         .long 0xFF000010       ! P4 MMUCR
Hexp_expevt:    .long _g_exp_expevt    ! ptr to expected EXPEVT global
Htea_addr:      .long 0xFF00000C       ! P4 TEA register address
Hexp_tea:       .long _g_exp_tea       ! ptr to expected TEA global

        ! ---- Common handler tail ----
_h_resume:
        mov.l   Ph_resume, r0
        mov.l   @r0, r0               ! r0 = resume label address
        ! Force return to supervisor (SSR.MD=1): user-mode sub-tests (E/F)
        ! fault with SSR=user SR; without this the RTE resumes in user mode and
        ! the next sub-test's privileged LDC/LDTLB traps. MD bit = 0x40000000.
        .word   0x0132                 ! STC SSR, r1
        mov.l   Pmd_bit, r2
        or      r2, r1
        .word   0x413E                 ! LDC r1, SSR
        .word   0x404E                 ! LDC r0, SPC
        rte
        nop

_h_bad_expevt:
        mov.l   Ph_bad_expevt, r0
        mov.l   @r0, r9               ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

_h_bad_tea:
        mov.l   Ph_bad_tea, r0
        mov.l   @r0, r9               ! r9 = fail code (TEA mismatch)
        bra     _fail
        nop

        .balign 4
Ph_resume:      .long _g_resume
Ph_bad_expevt:  .long _g_bad_expevt
Ph_bad_tea:     .long _g_bad_tea
Pmd_bit:        .long 0x40000000       ! SR.MD bit, set on SSR before RTE

        ! ================================================================
        ! Shared handler globals.
        ! ================================================================
        .balign 4
_g_exp_expevt:  .long 0
_g_exp_tea:     .long 0
_g_resume:      .long 0
_g_bad_expevt:  .long 0
_g_bad_tea:     .long 0

        ! ================================================================
        ! Fault-page padding: VA 0x1000-0x4FFF.
        ! ================================================================
_fault_pages:
        .space 0x4000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
