! mmufaultage.S -- GREEN guard locking the precise-exception SQUASH of a
! faulting load when a D-side fault is raised inside the window opened by an
! I-side fault. The RTL under test is core/datapath.vhm's g_squash_ifetch:
!
!     elsif squash_arm = '1' and tlb_exc_ifetch = '0' then
!       squash_ifetch_r <= '0';
!
! (committed as 0280b7e). This clear ensures a faulting load's writeback is
! suppressed when the squash fires, so its base register survives intact and
! a later retry can produce the correct value.
!
! MUTATION EVIDENCE (measured, not theoretical): removing that `elsif` clear
! from g_squash_ifetch turns this guard RED with Result=4 -- the PRIMARY
! check (r5 == 0xFFFFFFA1) fails. Without the squash, the faulting load
! wrongly commits once before its fault is serviced; since the load's base
! and destination are the same register (see below), that wrong commit
! destroys the value any retry needs, and no subsequent retry can recover
! it. With the squash intact (current RTL), this guard PASSES.
!
! WHAT THIS GUARD DOES NOT SHOW. An earlier version of this file framed the
! scenario around TLB fault AGE ORDERING -- the claim that when a D-side
! fault (older, EX) and a deferred I-side fault (younger, ID) are pending at
! the same dispatch boundary, delivering the younger one first is a
! user-visible defect. That framing has been retired: MEASURED on this exact
! non-idempotent scenario, mis-ordered/co-mingled fault delivery is BENIGN --
! the squash fix (above) makes the outcome correct regardless of which
! exception's record is serviced or delivered first, because the base
! register is never destroyed by a wrong commit in the first place. This
! guard therefore locks the squash fix, not an ordering guarantee. Any
! wording below describing an "ordering defect" is retained only as
! historical narrative of how this test scenario was constructed and
! debugged -- it is not a claim this guard currently substantiates or
! depends on.
!
! HOW THIS FORCES THE COINCIDENCE. The faulting load is planted at the LAST
! halfword of a mapped code page (VA 0x0FFE) with its DATA page unmapped, so:
!   * the load at 0x0FFE takes DMISS_R on VA 0x2000  (older, in EX), and
!   * the next sequential fetch, 0x1000, is on an unmapped code page and takes
!     IMISS                                           (younger, in ID).
! Both are pending together. Nothing else is in flight.
!
! WHY THE LOAD IS NON-IDEMPOTENT (this is what makes the guard OBSERVE the
! defect instead of surviving it). The load at 0x0FFE is `MOV.B @(0,R0),R0`
! (encoding 0x8400): its BASE (R0, holding 0x00002000) and its DESTINATION
! (R0) are the SAME register. An earlier version of this guard used
! `MOV.L @r4, r5` -- base r4, destination r5, DISJOINT registers -- which is
! IDEMPOTENT: re-executing it after the wrong page was eventually installed
! at the wrong address still produced the correct answer, because r4 was
! never touched by a wrongly-committed first attempt. MEASURED on that
! shape: the machine delivered IMISS before the older DMISS_R and installed
! the wrong page from the wrong TEA, yet the load's value still landed
! correctly -- the scenario was RECOVERABLE and the guard PASSED on
! known-defective RTL, proving nothing. With base==destination, a
! wrongly-committed first execution overwrites the very operand ANY retry
! needs: R0 becomes 0xFFFFFFA1 (the correct sign-extended result) or garbage
! depending on what got read, and a second execution reads from THAT value
! instead of 0x00002000. A dropped or mis-ordered fault is therefore
! PERMANENT and OBSERVABLE in the final register value -- it cannot be
! papered over by retry.
!
! Layout (absolute VAs via .org in the VMA-0 image, like mmuidslot.S):
!   Page 0 (0x0000-0x0FFF): identity-mapped code/handlers/literals/log.
!   Page 1 (0x1000-0x1FFF): UNMAPPED -- the fetch after the load.
!   Page 2 (0x2000-0x2FFF): UNMAPPED -- the load's data page, holds the seed.
!
! STATUS: GREEN. Wired into sim/mmu_sim.sh alongside the other single-fault
! MMU guards; it locks the squash fix described above, not an ordering claim.
!
! WHY FAULT-KIND ORDER CANNOT BE OBSERVED VIA VECTOR OFFSET IN THIS CORE.
! CONFIRMED in decode/gen-go/spec/sh4/exceptions.toml (lines 415, 459, 499,
! 539, 580, 620): ALL SIX TLB fault kinds (IMISS, DMISS_R, DMISS_W, IPROT,
! DPROT_R, DPROT_W) vector to the SAME PC <- VBR+0x400. They are distinguished
! only by EXPEVT (IMISS=0x040, DMISS_R=0x060, DMISS_W=0x080, IPROT=0x0A0,
! DPROT_R/W=0x0C0), never by vector offset. A three-stub layout at
! VBR+0x400/+0x420/+0x440 is simply wrong for this hardware: only the +0x400
! stub can ever be entered, so a "first kind seen" log fed from separate stubs
! is always 0x40 and a check comparing it against DMISS_R (0x60) can never
! pass -- not on correct silicon, not on broken silicon. That check was not a
! valid instrument and has been removed (see CORRECTION below).
!
! We do NOT attempt to reimplement kind discrimination by reading EXPEVT
! here: a prior investigation measured `STC EXPEVT` returning 0 in this
! configuration for reasons that are not understood, and chasing that is out
! of scope for this guard. Instead this guard proves correctness INDIRECTLY:
!
!   r5 (a copy of r0 taken at 0x1000, before the jmp back) == 0xFFFFFFA1 is
!   the proof that the squash fix worked. Because the load's base and
!   destination are the SAME register (see above), this can only be true if
!   the load committed EXACTLY ONCE, against the correctly-installed page 2,
!   after both faults were serviced. If the squash fix were absent or broken,
!   the load could wrongly commit before its fault is serviced, destroying
!   the base register a retry needs, and r5 would NOT be 0xFFFFFFA1. Unlike
!   the retired idempotent shape, there is no path by which a wrongly-
!   committed first execution self-repairs.
!
! HISTORICAL NOTE (investigative narrative, not a current claim about this
! guard): an earlier version of this guard's check (1) compared
! `_log_first` (a kind byte assumed to come from separate per-kind vector
! stubs) against DMISS_R, and reported Result=3. That result was NOT evidence
! of anything -- it was an artifact of the broken three-stub scheme described
! above, which could never observe DMISS_R at all. During debugging, the
! waveform showed mis-ordered/co-mingled fault delivery (the CPU entering the
! IMISS vector at VBR+0x400 carrying the D-side fault record). That mis-
! ordering was part of how this scenario was investigated, but it is NOT what
! this guard locks or claims as a defect -- see the header CORRECTION above:
! with the squash fix in place, this scenario passes regardless of delivery
! order, because the base register is never destroyed by a wrong commit.
!
! FOR HISTORICAL REFERENCE ONLY (not a live claim): at one point during
! debugging, adding `texc_req = '0'` to decode_core's I-side arms was tried as
! a targeted "let the older D-side request win" fix and measured insufficient
! on its own, before the actual fix -- the datapath squash clear in
! g_squash_ifetch -- was identified. That squash clear is what this guard now
! locks; see the header for the mutation evidence.
!
! PASS requires both:
!   * r5 == 0xFFFFFFA1 after the dust settles            (fail 4) -- PRIMARY:
!     the non-idempotent load committed exactly once, against the correctly
!     installed page. This is the proof that the squash fix (g_squash_ifetch,
!     see header) is intact; unlike the retired idempotent shape, a wrongly
!     committed first execution cannot self-repair into this value.
!   * _log_count /= 0                                    (fail 5) -- ANTI-
!     VACUITY: at least one fault was actually taken, so the PRIMARY check
!     is not trivially satisfied by the code never faulting at all. This
!     deliberately does NOT assert an exact count: the non-idempotent retry
!     may legitimately change how many faults occur, and pinning an exact
!     count would risk masking the PRIMARY (value) result.
! (fail codes 4 and 5 are kept as-is; 3 is retired along with check (1). Codes
! do not collide with #7 -- fell through without faulting -- or _fail's 0x7F
! clamp.)
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
#if CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH

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

        ! ---- VBR = _vbase. All six TLB fault kinds vector to the SAME
        !      PC <- VBR+0x400 on this core (see header); there is one
        !      handler and it does not attempt to discriminate kind. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Zero the fault log BEFORE AT is on (plain P0 stores). ----
        mov.l   p_log_count, r0
        mov     #0, r1
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
        !      r0 = 0x2000 (unmapped data page): the instruction at 0x0FFE is
        !      MOV.B @(0,R0),R0 -- its BASE and its DESTINATION are the SAME
        !      register, making it NON-IDEMPOTENT (see header). r5 = 0xAA
        !      sentinel, overwritten at 0x1000 with a copy of r0 for safekeeping
        !      before the jmp back to page 0. r6 = where page 1 bounces back to. ----
        mov.l   c_data_va, r0
        mov     #0xAA, r5
        mov.l   p_check, r6

        ! ---- Enter at 0x0FFE via jmp, so 0x0FFE is a branch TARGET (NOT a
        !      delay slot -- the nop below is) and the next sequential fetch
        !      after it is 0x1000, on the unmapped page. Use r1 (not r0) for
        !      the jump target: r0 must hold 0x00002000 unclobbered when
        !      0x0FFE executes. ----
        mov.l   c_load_va, r1
        jmp     @r1
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
p_log_count:    .long _log_count
p_fail:         .long _fail

        ! ================= verification, back on page 0 =================
        .balign 4
_check:
        ! (1) PRIMARY: r5 holds the copy of r0 taken at 0x1000, AFTER the
        !     load at 0x0FFE and its retry (if any). Because the load's base
        !     and destination are the SAME register (r0), a wrongly-committed
        !     first execution is NOT repairable by retry: if the mis-ordered
        !     IMISS/DMISS_R delivery let the load commit against the wrong
        !     (pre-fault, unmapped) address space, or commit twice, r0 will
        !     NOT be 0xFFFFFFA1. Only a correctly-ordered single retry against
        !     the properly-installed page 2 produces 0xFFFFFFA1 (sign-extended
        !     0xA1 byte). See header for the exact failure signature.
        mov.l   k_expect, r2            ! r2 = 0xFFFFFFA1
        cmp/eq  r2, r5
        bt      1f
        mov     #4, r9
        mov.l   k_fail, r0
        jmp     @r0
        nop
1:
        ! (2) ANTI-VACUITY: at least one fault was actually taken. Do NOT
        !     assert an exact count -- the non-idempotent retry may
        !     legitimately change how many faults occur; a wrong-count
        !     assertion would mask the value result in (1).
        mov.l   k_log_count, r0
        mov.l   @r0, r2
        tst     r2, r2
        bf      2f
        mov     #5, r9
        mov.l   k_fail, r0
        jmp     @r0
        nop
2:
        mov     #0, r9
        mov.l   k_done, r0
        jmp     @r0
        nop

        .align 2
k_fail:         .long _fail
k_done:         .long _done
k_log_count:    .long _log_count
k_expect:       .long 0xFFFFFFA1

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
        ! ALL SIX TLB fault kinds vector here -- PC <- VBR+0x400 -- on this
        ! core (see header); there is no per-kind stub and no attempt to
        ! discriminate kind (that would require reading EXPEVT, which is
        ! out of scope -- see header).
        .org 0x0600
_vbase:
        .space 0x400, 0

        .org 0x0A00
_v_tlbmiss:                             ! _vbase + 0x400 -- ALL TLB fault kinds
        bra     _h_common
        nop

        ! ---- Common handler. Entered with SR.RB=1, so r0-r7 here are BANK 1
        !      and the interrupted code's r4/r5/r6 (bank 0) are untouched.
        !      Installs an identity mapping for the page containing TEA, which
        !      serves both the I-side (page 1) and D-side (page 2) faults. ----
        .org 0x0A60
_h_common:
        ! ---- Log: count every entry. ----
        mov.l   Hlog_count, r0
        mov.l   @r0, r2
        add     #1, r2
        mov.l   r2, @r0
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
Hlog_count:     .long _log_count

        ! ---- Fault log, in page 0 (mapped, writable). ----
        .org 0x0E80
_log_count:     .long 0                 ! number of handler entries

        ! ---- The faulting load: LAST halfword of page 0, so the very next
        !      sequential fetch is 0x1000 on the unmapped page. NON-IDEMPOTENT:
        !      MOV.B @(0,R0),R0 -- base and destination are the SAME register,
        !      so a wrongly-committed first execution corrupts the operand a
        !      retry needs (see header). ----
        .org 0x0FFE
        .word   0x8400                  ! MOV.B @(0,R0),R0  (r0 = 0x2000 -> DMISS_R)

        ! ---- Page 1 (UNMAPPED): reached only after BOTH faults are serviced.
        !      Copy r0 to r5 BEFORE bouncing back, since r0 is needed by the
        !      harness / _check and MUST be preserved across the jmp. ----
        .org 0x1000
        mov     r0, r5
        jmp     @r6                     ! r6 = _check
        nop

        ! ---- Page 2 (UNMAPPED): the load's data. First byte MUST be 0xA1 so
        !      a correct load sign-extends to r0 = 0xFFFFFFA1. ----
        .org 0x2000
        .byte   0xA1, 0x00, 0x00, 0x00   ! seed -- r0 must end up holding 0xFFFFFFA1

        .org 0x2100

#endif  ! CONFIG_PRIV_ARCH && CONFIG_PRIV_ARCH
