! mmuidx.S -- minimal repro for computed-address corruption in handlers (M6).
!
! Symptom (observed in mmurun handler): inside a TLB-miss handler, reads whose
! address is computed with the R0 index (mov.l @(R0,Rn)) return wrong data,
! while plain mov.l @Rn / @(disp,Rn) / @(disp,PC) reads are clean.
!
! ROOT CAUSE (confirmed by this repro + VCD, NOT MMU/fault related):
!   The dedicated R0-index read port (register_file*.vhd `dout_0`) is hardwired
!   to architectural/bank-0 R0 and is NOT bank-remapped. SH-4 exception handlers
!   run with SR.RB=1, so a write to "r0" lands in bank-1 R0 while @(R0,Rn) still
!   reads the stale bank-0 R0. The "faulting VPN merged in" was a coincidence of
!   whatever stale value bank-0 R0 held. Reproduces with RB=1 in PLAIN code too
!   (no exception, no AT) -- see the manual RB=1 experiment in the report.
!
! This test isolates the TRIGGER with three independent cases, each emitting a
! distinct result code on failure. Identity maps throughout (this MMU emits PA
! tags, not bus relocation; all guards use identity). The corruption fires in
! case B (codes 6/8/9, R0-indexed inside the RB=1 handler); cases A and the
! plain/PC-rel sanity reads pass.
!
! Memory model (cpu_ctb): image flat at VA 0, RAM 0..0x1000000. P1 (0x8000xxxx)
! folds to PA 0x0000xxxx on the bus. We use:
!   - data page 0x00010000 (P0, identity-mapped) holding known values
!   - fault page 0x00100000 (P0, UNMAPPED -> DMISS_R), bit 20 set
!   - P1 alias 0x80010000 (folds to PA 0x00010000) for the P0-vs-P1 split
!
! Result codes:
!   0   all pass
!   ---- Case A: AT on, NO handler (does corruption happen outside a handler?) --
!   1   A: plain @Rn read of P0 data wrong (sanity -- should never fire)
!   2   A: @(R0,Rn) computed read of P0 data wrong
!   3   A: @(disp,PC) literal read wrong
!   ---- Case B: inside a DMISS_R handler (handler-only?) -----------------------
!   4   B: handler not reached (no DMISS exception)
!   5   B: plain @Rn read of P0 data wrong inside handler (sanity)
!   6   B: @(R0,Rn) computed read of P0 data wrong inside handler   <-- expected
!   7   B: @(disp,PC) literal read wrong inside handler             <-- expected
!   ---- Case C: P0-identity vs P1 computed read inside handler -----------------
!   8   C: @(R0,Rn) computed read of P0-identity wrong inside handler
!   9   C: @(R0,Rn) computed read of P1-alias wrong inside handler
!
! J4 overlay opcodes:
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E   LDC r0,SPC=0x404E

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

        ! ---- VBR = _v_load - 0x420 (so VBR+0x420 = _v_load). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed known values into the data page (AT off, direct). ----
        ! data_base = 0x00010000. Lay out:
        !   [data_base + 0x000] = 0xAA11AA11   (plain @Rn target)
        !   [data_base + 0x400] = 0xBB22BB22   (@(R0,Rn) target, R0=0x400)
        mov.l   p_data_base, r2
        mov.l   p_val_plain, r3
        mov.l   r3, @r2                 ! [0x00010000] = 0xAA11AA11
        mov.l   p_data_base, r2
        mov.l   p_idx, r0
        mov.l   p_val_idx, r3
        mov.l   r3, @(r0,r2)           ! [0x00010400] = 0xBB22BB22

        ! ---- Map page 0 of code (VA 0x0000): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map data page 0x00010000: identity, full access. ----
        mov.l   p_data_pteh, r0         ! VPN for 0x00010000
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_data_ptel, r0         ! PPN(0x00010000) | 0xE8
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ==============================================================
        ! Case A: AT ON, NO handler. Computed reads of the mapped data
        ! page. No fault is in flight. Does corruption happen here?
        ! ==============================================================
        ! A.1 plain @Rn
        mov.l   p_data_base, r2
        mov.l   @r2, r5                 ! r5 = [0x00010000]
        mov.l   p_val_plain, r6
        cmp/eq  r6, r5
        mov     #1, r9
        bf      _fail_at

        ! A.2 @(R0,Rn)
        mov.l   p_data_base, r2
        mov.l   p_idx, r0
        mov.l   @(r0,r2), r5           ! r5 = [0x00010400]
        mov.l   p_val_idx, r6
        cmp/eq  r6, r5
        mov     #2, r9
        bf      _fail_at

        ! A.3 @(disp,PC) literal load (this very instruction class)
        mov.l   pcrel_marker, r5       ! r5 = 0x12345678 via PC-relative
        mov.l   p_pcrel_val, r6
        cmp/eq  r6, r5
        mov     #3, r9
        bf      _fail_at

        ! ==============================================================
        ! Case B/C: take a DMISS_R on VA 0x00100000 (bit 20 set, unmapped).
        ! The handler (VBR+0x420) performs the computed reads.
        ! ==============================================================
        mov     #4, r9                  ! sentinel: handler not reached -> 4
        mov.l   p_fault_va, r2
        mov.l   @r2, r3                 ! FAULTS -> _v_load (DMISS_R)

        ! If we reach here, NO DMISS fired -> handler never ran -> report 4
        ! (the handler resumes directly at _done on success).
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        bra     _fail
        nop

_fail_at:
        ! disable AT before reporting
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:    .long 0xDFFFFFFF
p_vbr_val:    .long _v_load - 0x420
p_mmucr:      .long 0xFF000010
p_ptel_page0: .long 0x000000E8
p_data_base:  .long 0x00010000
p_idx:        .long 0x00000400
p_val_plain:  .long 0xAA11AA11
p_val_idx:    .long 0xBB22BB22
p_fault_va:   .long 0x00100000
! data page 0x00010000 -> VPN field (PA & ~0xFFF), PPN field (PA & 0xFFFFFC00)|0xE8
p_data_pteh:  .long 0x00010000
p_data_ptel:  .long 0x000100E8
p_pcrel_val:  .long 0x12345678
        .balign 4
pcrel_marker: .long 0x12345678

#else
        bra     _done
        nop
#endif

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
        ! DMISS_R handler at VBR+0x420 (_v_load).
        ! On entry: AT is still on. We do NOT disable AT (the mmurun bug
        ! manifested with AT still on inside the handler). We perform the
        ! computed-address reads of the IDENTITY-MAPPED data page and the
        ! P1 alias, compare against known values, then disable AT, set SPC
        ! to resume past the faulting access, and RTE.
        ! ================================================================
        .balign 4
_v_load:                                ! = VBR + 0x420
        ! --- B.1: plain @Rn of data page (sanity; should be clean) ---
        mov.l   H_data_base, r2
        mov.l   @r2, r5
        mov.l   H_val_plain, r6
        cmp/eq  r6, r5
        mov     #5, r9
        bf      _h_fail

        ! --- B.2: @(R0,Rn) computed read of P0 data page ---
        mov.l   H_data_base, r2
        mov.l   H_idx, r0
        mov.l   @(r0,r2), r5           ! expect 0xBB22BB22
        mov.l   H_val_idx, r6
        cmp/eq  r6, r5
        mov     #6, r9
        bf      _h_fail

        ! --- B.3: @(disp,PC) literal load inside handler ---
        mov.l   Hpcrel_marker, r5      ! expect 0x12345678
        mov.l   H_pcrel_val, r6
        cmp/eq  r6, r5
        mov     #7, r9
        bf      _h_fail

        ! --- C: @(R0,Rn) to P0-identity (redundant w/ B.2 -> code 8) ---
        mov.l   H_data_base, r2
        mov.l   H_idx, r0
        mov.l   @(r0,r2), r5
        mov.l   H_val_idx, r6
        cmp/eq  r6, r5
        mov     #8, r9
        bf      _h_fail

        ! --- C: @(R0,Rn) to P1-alias (0x80010000 folds to PA 0x00010000) ---
        mov.l   H_p1_base, r2          ! 0x80010000
        mov.l   H_idx, r0
        mov.l   @(r0,r2), r5           ! expect 0xBB22BB22 (same PA)
        mov.l   H_val_idx, r6
        cmp/eq  r6, r5
        mov     #9, r9
        bf      _h_fail

        ! --- all handler checks passed: disable AT, resume at _done ---
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT = 0
        mov.l   H_resume, r0
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_fail:
        ! disable AT, report r9 via _fail
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   H_fail, r0
        .word   0x404E                  ! LDC r0, SPC (resume into _fail)
        rte
        nop

        .balign 4
H_data_base:    .long 0x00010000
H_p1_base:      .long 0x80010000
H_idx:          .long 0x00000400
H_val_plain:    .long 0xAA11AA11
H_val_idx:      .long 0xBB22BB22
H_pcrel_val:    .long 0x12345678
H_mmucr:        .long 0xFF000010
H_resume:       .long _done
H_fail:         .long _fail
        .balign 4
Hpcrel_marker:  .long 0x12345678

        ! fault page padding: VA 0x00010000 region already RAM; fault page
        ! 0x00100000 is unmapped in the TLB but IS within RAM so the bus does
        ! not fault before the TLB exception fires. No explicit .space needed
        ! (RAM is zero-filled by the loader up to 16 MB).

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
