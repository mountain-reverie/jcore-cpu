! sh2a_movml_pop_restart.S -- restart-safety proof for SH-2A MOVML.L @R15+,Rn
! (multi-register pop) under a MID-LOOP data TLB fault (CONFIG_SH2A_ARCH &&
! CONFIG_MMU_ARCH).
!
! Design property under test: MOVML.L @R15+,R4 (pop R0..R4, opcode
! 0100 0100 1111 0101 = 0x44F5) is implemented in decode_core.vhm as a
! counted loop of 5 indexed LOAD slots (@(R15+idx*4) -> R(idx), write-port
! only) followed by ONE terminal slot that updates R15 by +20. R15 is not
! touched during the loop -- only in the terminal slot. This makes the
! instruction restart-safe: if a load faults mid-loop, the WHOLE instruction
! restarts from load 0 (single shared PC, if_issue/incpc suppressed during
! the loop); since R15 is still pristine, already-loaded registers are
! re-loaded with identical values (idempotent) and R15 only commits once the
! instruction runs to completion without faulting.
!
! This test does not just fault on the FIRST load (which would be a much
! weaker proof). It straddles a page boundary so R15 is chosen such that
! loads 0..3 (R0..R3) come from a page that IS mapped, and load 4 (R4) comes
! from the immediately following page which starts UNMAPPED:
!
!   R15 = 0x0FF0 (page 0, identity-mapped, W|X|U|C = 0xE8)
!     idx0 -> VA 0x0FF0 -> R0   (page 0, mapped: succeeds every attempt)
!     idx1 -> VA 0x0FF4 -> R1   (page 0, mapped: succeeds every attempt)
!     idx2 -> VA 0x0FF8 -> R2   (page 0, mapped: succeeds every attempt)
!     idx3 -> VA 0x0FFC -> R3   (page 0, mapped: succeeds every attempt)
!     idx4 -> VA 0x1000 -> R4   (page 1, UNMAPPED on first attempt -> DMISS_R)
!
! Flow:
!   1. AT is off initially (MMUCR default). Seed the stack words at
!      0x0FF0-0x1000 with distinct sentinels via plain stores (flat physical
!      addressing while AT=0, so writing into page-1's future VA is fine).
!   2. Map page 0 identity, enable AT (page 1 deliberately left unmapped).
!   3. Clobber R0..R4, then execute the MOVML.L @R15+,R4 under test.
!      - Loads 0..3 (R0..R3) succeed the first time.
!      - Load 4 (R4, VA 0x1000) DMISSes: EXPEVT=0x060, TEA=0x1000. R15 is
!        NOT yet updated (still 0x0FF0).
!   4. The DMISS_R handler (VBR+0x420, the D-load vector) maps page 1
!      identity (W|X|U|C=0xE8)
!      via PTEH/PTEL/ASIDR+LDTLB, bumps a fault counter, and RTEs WITHOUT
!      touching SPC -- relying on hardware to have captured SPC = the
!      MOVML.L instruction's own PC (the loop shares one PC; only the
!      terminal slot advances PC), so RTE resumes AT THE START of the
!      MOVML.L instruction.
!   5. Second attempt: R0..R3 re-load from 0x0FF0-0x0FFC (R15 unchanged, so
!      SAME addresses -> SAME sentinel values: idempotent), R4 loads from
!      0x1000 (now mapped) successfully, then the terminal slot commits
!      R15 += 20 -> R15 = 0x1004.
!   6. Verify every popped register against its sentinel, verify R15 ==
!      0x1004, and verify the fault handler ran EXACTLY ONCE (proves a
!      genuine single mid-loop fault+restart occurred, not zero faults and
!      not a fault-loop that happened to terminate by luck/timeout).
!
! Result codes (TEST_RESULT_ADDRESS):
!   0 pass
!   1..5  R0..R4 mismatch after restart
!   6     R15 not restored to start+20 after restart
!   7     fault handler did not run exactly once
!   8     DMISS EXPEVT code wrong (handler-side guard)
!   9     DMISS TEA wrong (handler-side guard)
!  15     unexpected trap / fell through to _fail
!
! sh2-elf-as (-m2) does not know SH-2A MOVML.L or the J4 LDC/STC MMU control
! forms, so both are hand-encoded via .word (mirrors sh2a_movml_pop.S and
! mmufault.S / mmustore.S):
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E   STC EXPEVT,r0=0x0052
!   MOVML.L @r15+,r4 (pop R0..R4) = 0x44F5

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_dmiss - 0x420 (so VBR+0x420 = _v_dmiss = the D-load
        !      vector: DMISS_R/DPROT_R dispatch to VBR+0x420, NOT VBR+0x060 --
        !      0x060 is the EXPEVT *code*, not the vector offset; the Option-A
        !      vector layout is I-fetch->VBR+0x400, D-load->VBR+0x420,
        !      D-store->VBR+0x440; see decode/gen-go/spec/sh4/exceptions.toml). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Clear fault counter and set up R15 for the stack region. ----
        mov.l   p_g_fault_count, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov.l   p_sp0, r15              ! R15 = 0x0FF0

        ! ---- Seed sentinels at 0x0FF0..0x0FFC and 0x1000 (AT still off: flat
        !      physical addressing, so writing the page-1 word is safe). ----
        mov.l   p_s0, r1
        mov.l   r1, @(0,r15)             ! VA 0x0FF0
        mov.l   p_s1, r1
        mov.l   r1, @(4,r15)             ! VA 0x0FF4
        mov.l   p_s2, r1
        mov.l   r1, @(8,r15)             ! VA 0x0FF8
        mov.l   p_s3, r1
        mov.l   r1, @(12,r15)            ! VA 0x0FFC
        mov.l   p_s4, r1
        mov.l   p_va_page1, r2
        mov.l   r1, @r2                  ! VA 0x1000

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). Page 1 deliberately
        !      left UNMAPPED so the last load of the pop DMISSes. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Clobber R0..R4 so the pop genuinely (re)reads memory both
        !      before AND after the restart. ----
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        nop

        ! --- instruction under test: MOVML.L @r15+,r4 (pop R0..R4). ---
        ! First attempt: loads 0..3 succeed, load 4 (VA 0x1000) DMISSes.
        ! The handler maps page 1 and RTEs with hardware-captured SPC still
        ! pointing at THIS instruction, so it restarts from load 0.
        .word   0x44F5

        ! ---- Verify every popped register against its sentinel. ----
        mov.l   p_s0, r7
        cmp/eq  r0, r7
        bf      _fail1
        mov.l   p_s1, r7
        cmp/eq  r1, r7
        bf      _fail2
        mov.l   p_s2, r7
        cmp/eq  r2, r7
        bf      _fail3
        mov.l   p_s3, r7
        cmp/eq  r3, r7
        bf      _fail4
        mov.l   p_s4, r7
        cmp/eq  r4, r7
        bf      _fail5

        ! ---- Verify R15 == start + 4*5 = 0x0FF0 + 20 = 0x1004. ----
        mov.l   p_sp_final, r7
        cmp/eq  r15, r7
        bf      _fail6

        ! ---- Verify the fault handler ran EXACTLY ONCE. ----
        mov.l   p_g_fault_count, r0
        mov.l   @r0, r7
        mov     #1, r6
        cmp/eq  r6, r7
        bf      _fail7

        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_dmiss - 0x420  ! VBR so VBR+0x420 = _v_dmiss (D-load vector)
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000E8        ! W|X|U|C
p_sp0:          .long 0x00000FF0        ! R15 start: straddles page 0/1
p_sp_final:     .long 0x00001004        ! R15 after pop: start + 4*5
p_va_page1:     .long 0x00001000
p_g_fault_count: .long _g_fault_count
p_s0:  .long 0xA0A0A000
p_s1:  .long 0xB1B1B111
p_s2:  .long 0xC2C2C222
p_s3:  .long 0xD3D3D333
p_s4:  .long 0xE4E4E444

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH

        .global _done
ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop

_fail1: mov.l p_test_result, r0
        mov #1, r9
        mov.l r9, @r0
        bra _fail1
        nop
_fail2: mov.l p_test_result, r0
        mov #2, r9
        mov.l r9, @r0
        bra _fail2
        nop
_fail3: mov.l p_test_result, r0
        mov #3, r9
        mov.l r9, @r0
        bra _fail3
        nop
_fail4: mov.l p_test_result, r0
        mov #4, r9
        mov.l r9, @r0
        bra _fail4
        nop
_fail5: mov.l p_test_result, r0
        mov #5, r9
        mov.l r9, @r0
        bra _fail5
        nop
_fail6: mov.l p_test_result, r0
        mov #6, r9
        mov.l r9, @r0
        bra _fail6
        nop
_fail7: mov.l p_test_result, r0
        mov #7, r9
        mov.l r9, @r0
        bra _fail7
        nop

        .global _fail
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov     #15, r9
        mov.l   r9, @r0
        bra     _fail
        nop

        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH

        ! ================================================================
        ! DMISS_R handler at VBR+0x420 (D-load vector) = _v_dmiss.
        ! Maps page 1 identity, bumps the fault counter, RTEs WITHOUT
        ! touching SPC (hardware-captured SPC must already point at the
        ! MOVML.L instruction under test -- that is the property this test
        ! proves).
        ! ================================================================
        .balign 4
        .space 0x360, 0
        .balign 4
_v_dmiss:                               ! = VBR + 0x420
        ! Sanity-guard: EXPEVT must be DMISS_R (0x060).
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hc_dmiss_r, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt

        ! Sanity-guard: TEA must be VA 0x1000 (the R4 load address).
        mov.l   Hp_tea_addr, r0
        mov.l   @r0, r2
        mov.l   Hc_page1_va, r1
        cmp/eq  r1, r2
        bf      _h_bad_tea

        ! Bump fault counter.
        mov.l   Hp_g_fault_count, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0

        ! Map page 1 (VA 0x1000-0x1FFF): identity, W+X+U+C = 0xE8.
        mov.l   Hc_page1_va, r0
        .word   0x405E                  ! LDC r0, PTEH (VPN=1, ASID=0)
        mov.l   Hp_ptel_page1, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! Return WITHOUT touching SPC: the hardware-captured SPC must be
        ! the MOVML.L instruction's own PC so the whole instruction retries
        ! from load 0.
        rte
        nop

_h_bad_expevt:
        mov.l   Hp_test_result, r0
        mov     #8, r9
        mov.l   r9, @r0
_h_bad_expevt_spin:
        bra     _h_bad_expevt_spin
        nop

_h_bad_tea:
        mov.l   Hp_test_result, r0
        mov     #9, r9
        mov.l   r9, @r0
_h_bad_tea_spin:
        bra     _h_bad_tea_spin
        nop

        .balign 4
Hc_dmiss_r:         .long 0x00000060
Hc_page1_va:        .long 0x00001000
Hp_tea_addr:        .long 0xFF00000C
Hp_ptel_page1:      .long 0x000010E8        ! PPN=PTEL[31:10]=0x1000>>10 (identity) | W|X|U|C
Hp_g_fault_count:   .long _g_fault_count
Hp_test_result:     .long TEST_RESULT_ADDRESS

        ! ================================================================
        ! Shared handler globals.
        ! ================================================================
        .balign 4
_g_fault_count: .long 0

        ! ================================================================
        ! Page-1 physical backing (VA 0x1000-0x1FFF): must exist on the bus
        ! so the R4 load (once mapped) reads real memory; also gives room
        ! for the sentinel write at 0x1000 done while AT was off.
        ! ================================================================
_fault_pages:
        .space 0x1000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH
