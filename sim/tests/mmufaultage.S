! mmufaultage.S -- RED guard for TLB fault AGE ORDERING: when a D-side fault and
! a deferred I-fetch fault are pending at the SAME decode dispatch boundary, the
! OLDER (D-side) one must be delivered first.
!
! WHY THIS SHAPE. Since deferred I-fetch fault delivery landed, an I-fetch fault
! is raised from if_fault when the instruction carrying it reaches ID, while a
! D-side fault is raised from the held texc_req for an instruction already in EX.
! EX is older than ID, so the D-side fault is ALWAYS the older of the two. But
! decode_core's next_op checks the TLB_IMISS/TLB_IPROT arms ABOVE the D-side
! arms, and texc_ack clears texc_req at the dispatch boundary WITHOUT checking
! which system op was actually latched. So when both are pending at one boundary:
!   * the younger IMISS is dispatched, and
!   * the older D-side request is silently DISCARDED -- never delivered, and its
!     instruction is never retried, because the IMISS restart PC is the YOUNGER
!     instruction's PC.
! The faulting load's destination therefore keeps its pre-load value with no
! exception ever reported: silent wrong data, not a crash.
!
! The datapath mirrors the same race: the immediate (D-side) capture and the
! deferred (I-side) capture both write tlb_exc_pc / TEA / PTEH / MMUFSR / TSBPTR,
! with no coordination, so whichever writes last owns the record for an exception
! only one of them corresponds to.
!
! HOW THIS FORCES THE COINCIDENCE. The faulting load is planted at the LAST
! halfword of a mapped code page (VA 0x0FFE) with its DATA page unmapped, so:
!   * the load at 0x0FFE takes DMISS_R on VA 0x2000  (older, in EX), and
!   * the next sequential fetch, 0x1000, is on an unmapped code page and takes
!     IMISS                                           (younger, in ID).
! Both are pending together. Nothing else is in flight.
!
! Layout (absolute VAs via .org in the VMA-0 image, like mmuidslot.S):
!   Page 0 (0x0000-0x0FFF): identity-mapped code/handlers/literals/log.
!   Page 1 (0x1000-0x1FFF): UNMAPPED -- the fetch after the load.
!   Page 2 (0x2000-0x2FFF): UNMAPPED -- the load's data page, holds the seed.
!
! STATUS: KNOWN-RED. Deliberately NOT wired into sim/mmu_sim.sh's run -- it is
! the reproduction for an OPEN defect, parked the same way m8_dsdslot_0 was.
! Measured Result=3 (the first fault delivered was not DMISS_R).
!
! WHAT THE WAVEFORM SHOWS, and why the obvious fix does not work. Adding
! `texc_req = '0'` to decode_core's I-side arms and to texc_defer_cap_o -- "let a
! held D-side request win, it is older" -- was tried and measured INSUFFICIENT.
! The deferred I-side fault is dispatched a full cycle BEFORE the older load even
! reaches EX, so there is no D-side request to yield to yet:
!     t=530  ID = 0x6542 (the load @0x0FFE)   EX = 0x0238   IMISS recorded
!     t=540  ID = 0x462B (jmp @r6 @0x1000)    EX = 0x023A   IMISS DISPATCHED
!     t=550  ---                              EX = 0x0FFE   load faults DMISS_R
!     t=570  tlb_exc_pc overwritten 0x1000 -> 0x1002 by the D-side capture
!     t=630  CPU enters the IMISS vector (VBR+0x400) carrying the D-SIDE record
!            (tlb_exc_pc=0x1002, TEA=0x2000) -> installs the wrong page and
!            returns PAST the load; page 1 is still unmapped, so it thrashes.
! The real problem is that a deferred I-fetch fault is delivered at the ID
! dispatch boundary, but ID runs AHEAD of EX: older instructions are still in
! flight and can still fault. Any fix has to hold the I-side delivery until no
! older instruction can still raise an exception -- which is a pipeline-ordering
! change, not a gating tweak.
!
! PASS requires all three:
!   * the FIRST fault delivered is DMISS_R, not IMISS   (fail 3) -- the age rule
!   * r5 == seed after the dust settles                 (fail 4) -- the symptom
!   * exactly 2 faults were taken                       (fail 5) -- no re-fault
!     storm, and neither fault was silently dropped
!
! J4 overlay opcodes (the assembler does not know these forms):
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS, so _fail clamps r9==0 to 0x7F: a fault
! reaching _fail before any sub-test ran can never report PASS by accident.
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

        ! Stay in .vect (linker VMA 0) so .org below places code at ABSOLUTE VAs.

        .org 0x0200
ENTRY(start)
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0. REQUIRED: the I-side TLB fault path is gated on
        !      SR.RB='0' (core/cpu.vhd). With RB=1 (reset default) I-fetches
        !      bypass the TLB and page 1 never IMISSes. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _vbase. Hardware adds +0x400 IMISS / +0x420 DMISS_R /
        !      +0x440 DMISS_W, so each kind lands on its own stub and the
        !      handler knows which fault it is without reading EXPEVT. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Zero the fault log BEFORE AT is on (plain P0 stores). ----
        mov.l   p_log_first, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   p_log_count, r0
        mov.l   r1, @r0

        ! ---- Map page 0 identity, W|X|C (no U: kernel fetch, SMEP). ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. Pages 1 and 2 are deliberately NOT mapped. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Set up the faulting load's operands and the page-1 return path.
        !      r4 = 0x2000 (unmapped data page), r5 = 0xAA sentinel (must be
        !      REPLACED by the seed), r6 = where page 1 bounces back to. ----
        mov.l   c_data_va, r4
        mov     #0xAA, r5
        mov.l   p_check, r6

        ! ---- Enter at 0x0FFE via jmp, so 0x0FFE is a branch TARGET (NOT a
        !      delay slot -- the nop below is) and the next sequential fetch
        !      after it is 0x1000, on the unmapped page. ----
        mov.l   c_load_va, r0
        jmp     @r0
        nop

        ! Unreachable unless nothing faulted at all.
        mov     #7, r9
        mov.l   p_fail, r0
        jmp     @r0
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _vbase
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C8        ! PA 0x0000 | W|X|C
c_data_va:      .long 0x00002000        ! page 2, unmapped -> DMISS_R
c_load_va:      .long 0x00000FFE        ! last halfword of page 0
p_check:        .long _check
p_log_first:    .long _log_first
p_log_count:    .long _log_count
p_fail:         .long _fail

        ! ================= verification, back on page 0 =================
        .balign 4
_check:
        ! (1) AGE RULE: the FIRST fault delivered must be DMISS_R (0x60), not
        !     IMISS (0x40). If IMISS came first the older D-side request was
        !     preempted -- and, because texc_ack clears it anyway, dropped.
        mov.l   k_log_first, r0
        mov.l   @r0, r2
        mov     #0x60, r3
        cmp/eq  r3, r2
        bt      1f
        mov     #3, r9
        mov.l   k_fail, r0
        jmp     @r0
        nop
1:
        ! (2) THE SYMPTOM: the load must have been retried and landed. If the
        !     D-side fault was dropped, 0x0FFE never re-executed and r5 is
        !     still the 0xAA sentinel.
        mov.l   k_seed_va, r0
        mov.l   @r0, r2                 ! r2 = seed, read directly (page 2 is
                                        !      mapped by now)
        cmp/eq  r2, r5
        bt      2f
        mov     #4, r9
        mov.l   k_fail, r0
        jmp     @r0
        nop
2:
        ! (3) Exactly two faults: DMISS_R then IMISS. More means a re-fault
        !     storm; fewer means one was swallowed.
        mov.l   k_log_count, r0
        mov.l   @r0, r2
        mov     #2, r3
        cmp/eq  r3, r2
        bt      3f
        mov     #5, r9
        mov.l   k_fail, r0
        jmp     @r0
        nop
3:
        mov     #0, r9
        mov.l   k_done, r0
        jmp     @r0
        nop

        .align 2
k_fail:         .long _fail
k_done:         .long _done
k_log_first:    .long _log_first
k_log_count:    .long _log_count
k_seed_va:      .long 0x00002000

        ! ---- Report epilogue. MUST live in PAGE 0: emitted after .org 0x2100
        !      it would sit in the deliberately-unmapped page 2, so every report
        !      path would take extra IMISSes and break the fault-count assert. ----
ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

        ! ===================== Exception vectors =====================
        ! One stub per kind so the handler needs no EXPEVT read. Each records
        ! its kind, then falls into the common install-the-page-for-TEA body.
        .org 0x0600
_vbase:
        .space 0x400, 0

        .org 0x0A00
_v_imiss:                               ! _vbase + 0x400
        bra     _h_common
        mov     #0x40, r1               ! delay slot: kind = IMISS

        .org 0x0A20
_v_dmiss_r:                             ! _vbase + 0x420
        bra     _h_common
        mov     #0x60, r1               ! delay slot: kind = DMISS_R

        .org 0x0A40
_v_dmiss_w:                             ! _vbase + 0x440
        bra     _h_common
        mov     #0x80, r1               ! delay slot: kind = DMISS_W

        ! ---- Common handler. Entered with SR.RB=1, so r0-r7 here are BANK 1
        !      and the interrupted code's r4/r5/r6 (bank 0) are untouched.
        !      Installs an identity mapping for the page containing TEA, which
        !      serves both the I-side (page 1) and D-side (page 2) faults. ----
        .org 0x0A60
_h_common:
        ! ---- Log: record the FIRST kind seen, and count every entry. ----
        mov.l   Hlog_count, r0
        mov.l   @r0, r2
        add     #1, r2
        mov.l   r2, @r0
        mov     #1, r3
        cmp/eq  r3, r2
        bf      1f                      ! not the first fault -> leave first alone
        mov.l   Hlog_first, r0
        mov.l   r1, @r0
1:
        ! ---- PTEH = TEA & 0xFFFFF000 (VPN of the faulting page). ----
        mov.l   Htea_addr, r0
        mov.l   @r0, r2                 ! r2 = TEA
        mov.l   Hvpn_mask, r3
        and     r3, r2                  ! r2 = VPN base
        mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
        ! ---- PTEL = same PA (identity) | W|X|C. ----
        mov.l   Hptel_flags, r3
        mov     r2, r0
        or      r3, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        rte                             ! PC <- SPC (hardware restart PC)
        nop

        .align 2
Htea_addr:      .long 0xFF00000C
Hvpn_mask:      .long 0xFFFFF000
Hptel_flags:    .long 0x000000C8
Hlog_first:     .long _log_first
Hlog_count:     .long _log_count

        ! ---- Fault log, in page 0 (mapped, writable). ----
        .org 0x0E80
_log_first:     .long 0                 ! EXPEVT-ish kind byte of the FIRST fault
_log_count:     .long 0                 ! number of handler entries

        ! ---- The faulting load: LAST halfword of page 0, so the very next
        !      sequential fetch is 0x1000 on the unmapped page. ----
        .org 0x0FFE
        .word   0x6542                  ! MOV.L @r4, r5   (r4 = 0x2000 -> DMISS_R)

        ! ---- Page 1 (UNMAPPED): reached only after BOTH faults are serviced.
        !      Bounces straight back to page 0 with r5 intact. ----
        .org 0x1000
        jmp     @r6                     ! r6 = _check
        nop

        ! ---- Page 2 (UNMAPPED): the load's data. ----
        .org 0x2000
        .long   0x5A5AA5A5              ! seed -- r5 must end up holding this

        .org 0x2100

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
