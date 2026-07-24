! sh2a_movmu_pop_restart.S -- restart-safety proof for SH-2A MOVMU.L @R15+,Rn
! (multi-register pop incl. PR) under a MID-LOOP data TLB fault
! (CONFIG_SH2A_ARCH && CONFIG_MMU_ARCH).
!
! Design property under test: MOVMU.L @R15+,R4 (pop R0..R4, then PR; opcode
! 0100 0100 1111 0100 = 0x44F4) is implemented in decode_core.vhm as a
! counted loop of 5 indexed LOAD slots (@(R15+idx*4) -> R(idx), write-port
! only), followed by ONE PR-load slot (@(R15+20) -> PR), followed by ONE
! terminal slot that updates R15 by +24. R15 is not touched until the
! terminal slot. This makes the instruction restart-safe: if a load faults
! mid-sequence, the WHOLE instruction restarts from load 0 (single shared PC,
! if_issue/incpc suppressed during the loop); since R15 is still pristine,
! already-loaded registers/PR are re-loaded with identical values (idempotent)
! and R15 only commits once the instruction runs to completion without
! faulting.
!
! This test does not just fault on the FIRST load (which would be a much
! weaker proof). It straddles a page boundary so R15 is chosen such that
! loads 0..3 (R0..R3) come from a page that IS mapped, and load 4 (R4, the
! first load past the boundary) comes from the immediately following page
! which starts UNMAPPED. The PR load (idx5, VA 0x1004) is also on the
! unmapped page but is never reached on the first attempt because R4's fault
! restarts the whole instruction first.
!
!   R15 = 0x0FF0 (page 0, identity-mapped, W|X|U|C = 0xE8)
!     idx0 -> VA 0x0FF0 -> R0   (page 0, mapped: succeeds every attempt)
!     idx1 -> VA 0x0FF4 -> R1   (page 0, mapped: succeeds every attempt)
!     idx2 -> VA 0x0FF8 -> R2   (page 0, mapped: succeeds every attempt)
!     idx3 -> VA 0x0FFC -> R3   (page 0, mapped: succeeds every attempt)
!     idx4 -> VA 0x1000 -> R4   (page 1, UNMAPPED on first attempt -> DMISS_R)
!     idx5 -> VA 0x1004 -> PR   (page 1, only reached after page 1 is mapped)
!
! Flow:
!   1. AT is off initially (MMUCR default). Seed the stack words at
!      0x0FF0-0x1004 with distinct sentinels via plain stores (flat physical
!      addressing while AT=0, so writing into page-1's future VA is fine).
!   2. Map page 0 identity, enable AT (page 1 deliberately left unmapped).
!   3. Clobber R0..R4 and PR, then execute the MOVMU.L @R15+,R4 under test.
!      - Loads 0..3 (R0..R3) succeed the first time.
!      - Load 4 (R4, VA 0x1000) DMISSes: EXPEVT=0x060, TEA=0x1000. R15 is
!        NOT yet updated (still 0x0FF0).
!   4. The DMISS_R handler (VBR+0x420, the D-load vector) maps page 1
!      identity (W|X|U|C=0xE8) via PTEH/PTEL/ASIDR+LDTLB, bumps a fault
!      counter, and RTEs WITHOUT touching SPC -- relying on hardware to have
!      captured SPC = the MOVMU.L instruction's own PC (the loop shares one
!      PC; only the terminal slot advances PC), so RTE resumes AT THE START
!      of the MOVMU.L instruction.
!   5. Second attempt: R0..R3 re-load from 0x0FF0-0x0FFC (R15 unchanged, so
!      SAME addresses -> SAME sentinel values: idempotent), R4 loads from
!      0x1000 (now mapped) successfully, PR loads from 0x1004 (now mapped)
!      successfully, then the terminal slot commits R15 += 24 -> R15 =
!      0x1008.
!   6. Verify every popped register and PR against its sentinel, verify R15
!      == 0x1008, and verify the fault handler ran EXACTLY ONCE (proves a
!      genuine single mid-sequence fault+restart occurred, not zero faults
!      and not a fault-loop that happened to terminate by luck/timeout).
!
! Result codes (TEST_RESULT_ADDRESS):
!   0 pass
!   1..5  R0..R4 mismatch after restart
!   6     PR mismatch after restart
!   7     R15 not restored to start+24 after restart
!   8     fault handler did not run exactly once
!   9     DMISS EXPEVT code wrong (handler-side guard)
!   10    DMISS TEA wrong (handler-side guard)
!   15    unexpected trap / fell through to _fail
!
! MOVMU.L @r15+,r4 now uses the native SH-2A mnemonic (requires
! -Wa,--isa=sh2a). The J4/MMU control-register forms below have no gas
! mnemonic (PTEH/PTEL/ASIDR/EXPEVT are J-core-custom control regs, and
! LDTLB is not accepted under --isa=sh2a) so they remain hand-encoded via
! .word (mirrors mmufault.S / mmustore.S / sh2a_movml_pop_restart.S):
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=ldc r0,vbr   STC EXPEVT,r0=0x0052

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
        ldc     r0, vbr                 ! LDC r0, VBR

        ! ---- Clear fault counter and set up R15 for the stack region. ----
        mov.l   p_g_fault_count, r0
        mov     #0, r1
        mov.l   r1, @r0

        mov.l   p_sp0, r15              ! R15 = 0x0FF0

        ! ---- Seed sentinels at 0x0FF0..0x0FFC and 0x1000..0x1004 (AT still
        !      off: flat physical addressing, so writing the page-1 words is
        !      safe). ----
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
        mov.l   p_spr, r1
        mov.l   p_va_page1_pr, r2
        mov.l   r1, @r2                  ! VA 0x1004

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). Page 1 deliberately
        !      left UNMAPPED so the R4 load DMISSes. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Clobber R0..R4 and PR so the pop genuinely (re)reads memory
        !      both before AND after the restart. ----
        mov     #0, r0
        mov     #0, r1
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        mov     #0, r6
        lds     r6, pr
        nop

        ! --- instruction under test: MOVMU.L @r15+,r4 (pop R0..R4,PR). ---
        ! First attempt: loads 0..3 succeed, load 4 (VA 0x1000) DMISSes.
        ! The handler maps page 1 and RTEs with hardware-captured SPC still
        ! pointing at THIS instruction, so it restarts from load 0.
        movmu.l @r15+,r4

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

        ! ---- Verify PR. ----
        sts     pr, r7
        mov.l   p_spr, r6
        cmp/eq  r6, r7
        bf      _fail6

        ! ---- Verify R15 == start + 4*6 = 0x0FF0 + 24 = 0x1008. ----
        mov.l   p_sp_final, r7
        cmp/eq  r15, r7
        bf      _fail7

        ! ---- Verify the fault handler ran EXACTLY ONCE. ----
        mov.l   p_g_fault_count, r0
        mov.l   @r0, r7
        mov     #1, r6
        cmp/eq  r6, r7
        bf      _fail8

        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_dmiss - 0x420  ! VBR so VBR+0x420 = _v_dmiss (D-load vector)
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000E8        ! W|X|U|C
p_sp0:          .long 0x00000FF0        ! R15 start: straddles page 0/1
p_sp_final:     .long 0x00001008        ! R15 after pop: start + 4*6
p_va_page1:     .long 0x00001000
p_va_page1_pr:  .long 0x00001004
p_g_fault_count: .long _g_fault_count
p_s0:  .long 0xA0A0A000
p_s1:  .long 0xB1B1B111
p_s2:  .long 0xC2C2C222
p_s3:  .long 0xD3D3D333
p_s4:  .long 0xE4E4E444
p_spr: .long 0xF5F5F555

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
_fail8: mov.l p_test_result, r0
        mov #8, r9
        mov.l r9, @r0
        bra _fail8
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
        ! MOVMU.L instruction under test -- that is the property this test
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
        ! the MOVMU.L instruction's own PC so the whole instruction retries
        ! from load 0.
        rte
        nop

_h_bad_expevt:
        mov.l   Hp_test_result, r0
        mov     #9, r9
        mov.l   r9, @r0
_h_bad_expevt_spin:
        bra     _h_bad_expevt_spin
        nop

_h_bad_tea:
        mov.l   Hp_test_result, r0
        mov     #10, r9
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
        ! so the R4/PR loads (once mapped) read real memory; also gives room
        ! for the sentinel writes at 0x1000/0x1004 done while AT was off.
        ! ================================================================
_fault_pages:
        .space 0x1000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH && CONFIG_SH2A_ARCH
