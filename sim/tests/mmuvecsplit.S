! mmuvecsplit.S -- the miss/protection vector split is the WHOLE subject.
!
! J4 used to deliver all six TLB causes to the single vector VBR+0x400. That
! forced the miss fast path to test EXPEVT on every TSB hit, because a
! protection fault against a still-resident TSB entry also hits there and
! reinstalling the same entry livelocks. SH-4 does not do this: its own
! exception table (SH7750 hardware manual Rev 2.0, 02/99) splits them --
!
!   Instruction TLB miss             VBR + H'400
!   Data TLB miss (read / write)     VBR + H'400
!   Instruction TLB protection       VBR + H'100
!   Data TLB protection (read/write) VBR + H'100
!
! -- so J4 now does too, the EXPEVT test is gone from the hot path, and the
! CMP/MISS EXPEVT instruction that existed only to perform it was withdrawn.
!
! Every OTHER protection-exercising guard (mmufault, mmufsr, mmuglobal,
! mmusmep) routes both vectors to one EXPEVT-driven handler, so none of them
! can tell which vector actually fired -- they would all still pass if the
! split silently regressed. This guard exists to close that hole: each vector
! writes a DISTINCT marker, and every sub-test asserts the marker it expects.
! Corrupt the split (send protection back to 0x400) and sub-tests D-F fail
! with their own codes rather than passing quietly.
!
! Layout: VBR = _vbase; +0x100 = _v_prot, +0x400 = _v_miss.
!
! Sub-tests (all supervisor except E/F, which need MD=0 -- see mmufault):
!   A  DMISS_R (0x060) load  from an unmapped page  -> expect MISS vector
!   B  DMISS_W (0x080) store to   an unmapped page  -> expect MISS vector
!   C  IMISS   (0x040) fetch from an unmapped page  -> expect MISS vector
!   D  DPROT_W (0x0C0) store to a W=0 page          -> expect PROT vector
!
! Result codes:
!   1  sub-test A took the wrong vector      4  sub-test D took the wrong vector
!   2  sub-test B took the wrong vector      5  EXPEVT mismatch in a handler
!   3  sub-test C took the wrong vector      6  handler reached with no sub-test armed
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC EXPEVT,r0 =0x0052   LDC r0,VBR =0x402E   LDC r0,SPC =0x404E
!   LDC r0,ASIDR  =0x407E   LDC r0,PTEL=0x406E   LDC r0,PTEH=0x405E
#include "sim_instr.h"
#include "mmuwalk_common.inc"
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
#if CONFIG_PRIV_ARCH
        mov.l   p_sp,   r15
        mov.l   p_kmain, r0
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x80002F00
p_kmain: .long 0x80000000 + kmain

kmain:
        ! ---- RB=0, MD=1 ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- VBR = _vbase (P1 alias) ----
        mov.l   k_vbr, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Zero the markers ----
        mov.l   k_which, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_armed, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ---- Publish ONE read-only mapping for the protection sub-test.
        ! VA 0x00200000 -> PA 0x00200000, flags X|U|C|V (W=0) so a store
        ! raises DPROT_W while a load would hit. Under walker-only install the
        ! row goes in the TSB and the store itself is what installs it: the
        ! store misses, the walker installs the W=0 entry, the access re-runs
        ! and NOW takes DPROT_W. Sub-test D therefore also pins the ordering
        ! (install first, permission check after) that LDTLB pre-empted.
        !
        ! TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x 32 bytes),
        ! HASH_SHIFT=6, HASH_MODE=1. The set address is asked of the P4 helper
        ! at 0xFF000048 rather than hand-computed. All stores here are P1
        ! (untranslated) and AT is still off, so the fill cannot fault.
        mov.l   k_tsbbr_addr, r0
        mov.l   k_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   k_tsbcfg_addr, r0
        mov.l   k_tsbcfg_val, r1
        mov.l   r1, @r0

        mov.l   k_tsbslot, r12          ! r12 = 0xFF000048
        mov.l   va_ro, r6               ! VA
        mov     #0, r7                  ! ASID
        mov.l   ptel_ro, r8             ! PTEL (PA | X|U|C|V, W=0)
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8

        ! ---- AT is enabled per sub-test below, not once here: the shared
        ! handler disables it so the faulting access can RETRY untranslated
        ! and make forward progress. Without a per-sub-test re-arm, only the
        ! first sub-test would ever fault (found the hard way: sub-test B
        ! reported "wrong vector" when in truth it never faulted at all). ----

        ! ================= A: DMISS_R -> MISS vector =================
        mov.l   k_armed, r0 ; mov #1, r1 ; mov.l r1, @r0
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! re-arm AT
        mov.l   c_expevt_dmiss_r, r1 ; mov.l k_exp, r0 ; mov.l r1, @r0
        mov.l   va_unmapped, r2
        mov.l   @r2, r3                 ! FAULT -> expect _v_miss
        mov.l   k_which, r0 ; mov.l @r0, r2
        mov     #1, r3 ; cmp/eq r3, r2 ; mov #1, r9 ; bf _fail

        ! ================= B: DMISS_W -> MISS vector =================
        mov.l   k_which, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! re-arm AT
        mov.l   c_expevt_dmiss_w, r1 ; mov.l k_exp, r0 ; mov.l r1, @r0
        mov.l   va_unmapped, r2
        mov     #0, r3
        mov.l   r3, @r2                 ! FAULT -> expect _v_miss
        mov.l   k_which, r0 ; mov.l @r0, r2
        mov     #1, r3 ; cmp/eq r3, r2 ; mov #2, r9 ; bf _fail

        ! ================= C: IMISS -> MISS vector =================
        mov.l   k_which, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! re-arm AT
        mov.l   c_expevt_imiss, r1 ; mov.l k_exp, r0 ; mov.l r1, @r0
        mov.l   p_after_c, r0 ; mov.l k_resume, r1 ; mov.l r0, @r1
        mov.l   va_unmapped, r0
        jmp     @r0                     ! FAULT -> expect _v_miss
        nop
_after_c:
        mov.l   k_which, r0 ; mov.l @r0, r2
        mov     #1, r3 ; cmp/eq r3, r2 ; mov #3, r9 ; bf _fail

        ! ================= D: DPROT_W -> PROT vector =================
        ! Store to the W=0 page installed above. Supervisor DPROT_W needs only
        ! d_we=1 AND w=0 (no user mode), same construction as mmufault's D.
        mov.l   k_which, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! re-arm AT
        mov.l   c_expevt_dprot_w, r1 ; mov.l k_exp, r0 ; mov.l r1, @r0
        mov.l   va_ro, r2
        mov     #0, r3
        mov.l   r3, @r2                 ! FAULT -> expect _v_prot
        mov.l   k_which, r0 ; mov.l @r0, r2
        mov     #2, r3 ; cmp/eq r3, r2 ; mov #4, r9 ; bf _fail

        ! ---- Disable AT and pass ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:        .long 0xDFFFFFFF
k_vbr:            .long 0x80000000 + _vbase
k_mmucr:          .long 0xFF000010
k_which:          .long 0x80002D00      ! 1 = miss vector, 2 = prot vector
k_armed:          .long 0x80002D04
k_exp:            .long 0x80002D08      ! expected EXPEVT for the armed sub-test
k_resume:         .long 0x80002D0C      ! resume address for the I-fetch sub-test
va_unmapped:      .long 0x00300000      ! never mapped
va_ro:            .long 0x00200000
ptel_ro:          .long 0x00200069      ! PA | X|U|C|V (W=0 -> DPROT_W on store)
k_tsbbr_addr:     .long 0xFF000014
k_tsbbr_val:      .long 0x00014008      ! base=0x00014000, TSB_SIZE_LOG=8
k_tsbcfg_addr:    .long 0xFF000018
k_tsbcfg_val:     .long 0x00000061      ! HASH_SHIFT=6, HASH_MODE=1
k_tsbslot:        .long 0xFF000048      ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
c_expevt_imiss:   .long 0x00000040
c_expevt_dmiss_r: .long 0x00000060
c_expevt_dmiss_w: .long 0x00000080
c_expevt_dprot_w: .long 0x000000C0
p_after_c:        .long 0x80000000 + _after_c
#endif

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

#if CONFIG_PRIV_ARCH
        ! ===================== Vector page =====================
        .balign 4
_vbase:
        .org    _vbase + 0x100
        ! ---- VBR+0x100: TLB PROTECTION (IPROT / DPROT_R / DPROT_W) ----
_v_prot:
        mov     #2, r1                  ! marker: arrived via the PROT vector
        bra     _v_common
        nop

        .org    _vbase + 0x400
        ! ---- VBR+0x400: TLB MISS (IMISS / DMISS_R / DMISS_W) ----
_v_miss:
        mov     #1, r1                  ! marker: arrived via the MISS vector

        ! ---- Shared tail: record which vector fired, check EXPEVT, resume.
        ! AT is disabled here so the resumed code re-runs untranslated and the
        ! faulting access is not retried (this guard never wants a retry -- it
        ! is testing vector routing, not translation). ----
_v_common:
        mov.l   Hwhich, r0
        mov.l   r1, @r0                 ! g_which = 1 (miss) or 2 (prot)

        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! disable AT

        mov.l   Harmed, r0
        mov.l   @r0, r0
        tst     r0, r0
        bt      _v_unarmed              ! reached with no sub-test armed

        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _v_bad_expevt

        ! Resume: for the I-fetch sub-test SPC must be redirected to the
        ! recorded label (the faulting VA is unmapped and AT is now off, but
        ! the fetch VA itself is not valid code). For the D-side sub-tests SPC
        ! already points at the faulting instruction, which with AT off now
        ! addresses real memory and completes.
        mov.l   Hresume, r0
        mov.l   @r0, r0
        tst     r0, r0
        bt      1f
        .word   0x404E                  ! LDC r0, SPC
        mov     #0, r0
        mov.l   Hresume, r1
        mov.l   r0, @r1                 ! one-shot: clear the redirect
1:
        rte
        nop

_v_unarmed:
        mov.l   Hresult, r0
        mov     #6, r1
        mov.l   r1, @r0
1:      bra     1b
        nop

_v_bad_expevt:
        mov.l   Hresult, r0
        mov     #5, r1
        mov.l   r1, @r0
1:      bra     1b
        nop

        .align 2
Hwhich:   .long 0x80002D00
Harmed:   .long 0x80002D04
Hexp:     .long 0x80002D08
Hresume:  .long 0x80002D0C
Hmmucr:   .long 0xFF000010
Hresult:  .long TEST_RESULT_ADDRESS

        ! ---- Backing store for the TSB at PA 0x14000..0x15FFF. The walker
        ! ---- reads the TSB by PHYSICAL address and physical aliases are
        ! ---- backed by SRAM only within the loaded image extent, so the
        ! ---- image must reach past the END of the TSB.
_tsb_backing:
        .space 0x16000, 0
#endif
