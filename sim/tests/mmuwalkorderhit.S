! mmuwalkorderhit.S -- COVERAGE guard for the walker's older-instruction-first
!                      ordering gate: it constructs the ONE state in which an
!                      I-side TSB walk can be armed while an older D access
!                      still owns the data bus.
!
! ---- What it is for ----
!
! `core/cpu.vhd`'s `walk_i_miss` carries the ordering gate
!
!     and sig_db_o.en = '0' and d_fault_held = '0'
!
! and the invariant is re-stated, from the RAW ungated miss terms, by the
! permanent RTL assertion `p_walk_order_assert` in the same file. That
! assertion is the ONLY thing that catches the gate being deleted: the
! software-visible consequence of deleting it is a replayed external bus
! transaction, which is invisible on the plain SRAM this suite runs on (see
! mmuwalkorder.S's "WHAT THIS GUARD CANNOT DO" for the full measurement).
!
! MEASURED, and the reason this file exists: with the gate deleted, the
! assertion fired in exactly ONE image in the whole suite -- `m8_dsdslot_0`, a
! GENERATED fault-permutation axis that crosses the violating cycle by
! accident, twice in 29 cases. Every guard that exists TO test ordering --
! mmuidorder, mmudrain, mmumhorder, mmuwalkdside, mmuwalkorder, mmurun --
! stayed GREEN. Coverage that depends on a generated permutation image
! happening to cross a window is not coverage: reshape or skip that case and
! the invariant is silently unguarded. This guard builds the window on purpose.
!
! ---- Why the existing ordering guards do NOT reach it ----
!
! `walk_i_arm_raw` (cpu.vhd) is
!
!     walk_arm and walk_i_miss_raw and not walk_d_miss
!
! and the assertion fires on that coinciding with `sig_db_o.en = '1'` or
! `d_fault_held = '1'`. Two terms exclude every existing ordering guard:
!
!  * `not walk_d_miss`. They all pair a younger I-side miss with an older
!    D-side access that MISSES. A missing D access sets `walk_d_miss`,
!    `walk_va` prefers the D side, and the I side never arms -- so the gate can
!    be deleted and nothing in those guards changes.
!  * `walk_arm` -- tlb_walk.vhd's `arm` is `state = st_idle and req = '1' and
!    tried = '0'`. Once a walk has been armed for a miss and given up, `tried`
!    stays set while `req` is still high, so a D access that goes live LATER in
!    the same miss never produces an arming cycle. The coincidence has to exist
!    on the FIRST cycle of the I-side miss.
!
! MEASURED on this tree: the disjunct that is actually reachable is
! `sig_db_o.en = '1'` with an older STORE live and hitting. `d_fault_held` was
! never observed coincident with a raw I-side miss anywhere; it is covered by
! the same gate and the same assertion, but no software construction found here
! reaches it.
!
! ---- Construction (do NOT "simplify" it -- each variant below was measured) --
!
! Sixteen back-to-back stores fill the tail of resident page 0 and execution
! FALLS THROUGH into unmapped page 1:
!
!     0x0FE0..0x0FFE   mov.l r12, @r13   x16   ! page 2 MAPPED -> every store HITS
!     0x1000                                   ! page 1 UNMAPPED -> I-side miss
!
! The fetcher runs ahead of MA, so while the store stream is still draining the
! fetch of 0x1000 is presented and misses -- with `sig_db_o.en = '1'`,
! `walk_d_miss = '0'` and `tried = '0'` on that very cycle. Traced: at 31790ns
! `iva = 0x1000`, `dva = 0x2000`, `wr = '1'`, `arm = '1'`.
!
! Variants that were tried and DO NOT reach the window:
!   * mmuidorder's shape (a single access before a page-tail branch, its data
!     page pre-mapped so it hits): the access retires before the target fetch
!     is even issued.
!   * m8_dsdslot_0's Case B shape rebuilt by hand (branch at the page-0 tail,
!     delay slot on resident page 1, delay-slot store to resident page 2,
!     branch target on unmapped page 3): the target fetch misses ~10 cycles
!     BEFORE the delay-slot store reaches the bus, because the fault squashes
!     and re-issues the store after the handler has run.
!   * a store that takes a D-side PROTECTION fault (to reach `d_fault_held`):
!     the fault is dispatched before the next fetch is presented.
! The stream depth is what makes this one work: it keeps the data bus busy
! ACROSS the page boundary instead of around it.
!
! ---- Where the check lives ----
!
! The ordering itself is asserted in RTL, not here -- no software can observe
! it (mmuwalkorder.S documents why, with four measured mutations). This file's
! job is to make `p_walk_order_assert` REACHABLE, and to fail loudly if the
! construction stops producing the coincidence. Its PASS means "the window was
! built and the machine behaved"; the ordering verdict is the assertion's,
! delivered as a simulation failure.
!
! ---- Layout (absolute VAs via .org in the VMA-0 image, like mmuidorder.S) ----
!   Page 0 (0x0000-0x0FFF): identity-mapped code, handler, literals, log, and
!                           the store stream at its tail.
!   Page 1 (0x1000-0x1FFF): UNMAPPED -- the fall-through target.
!   Page 2 (0x2000-0x2FFF): identity-mapped BEFORE the race -- the stores' data
!                           page, so every store HITS. This is the whole point.
!   0x00010000            : the TSB, left zeroed so every walk fails OPEN and
!                           the software handler resolves the miss as before.
!
! PTEL flag bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G
! bit1=STALE bit0=V. Kernel code/data: W|X|C = 0xC8 (matching mmuidorder.S).
!
! The handler is entered with SR.RB=1 and uses only r0-r7 (bank 1); r9 and
! r11-r14 are non-banked and carry state across faults untouched.
!
! J4 overlay opcodes (the assembler does not know these forms):
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E
! A hand-assembled .word is an UNCHECKED assertion about the hardware:
! 0x2DC2 is MOV.L R12,@R13 -- MOV.L Rm,@Rn is 0010 nnnn mmmm 0010, n=13 m=12.
! mmuidorder.S spent two RTL probes on exactly this class of typo.
!
! ---- Result codes ----
!   0  pass -- the window was constructed and the machine behaved
!   1  NO fault at all -- the race never happened. ANTI-VACUITY.
!   2  no log entry for page 1 -- the fall-through fetch never missed, so the
!      coincidence under test did not occur.
!   3  page 2 IS in the log -- the stores FAULTED instead of hitting. The
!      construction has degraded into mmuidorder's shape (walk_d_miss = '1'),
!      which the assertion's `not walk_d_miss` term excludes, and this guard is
!      no longer covering the gate. THE STORES MUST HIT.
!   4  the word at 0x2000 is not the payload -- the store stream never landed,
!      so there was no live D access to race against.
!   5  cnt_walks == 0 -- the walker never armed anywhere in this image, so an
!      assertion that only samples on an ARMING cycle proves nothing here.
!      ANTI-VACUITY for the assertion itself. It is read from a deliberate
!      warm-up miss BEFORE the race, not from the race: with the gate present
!      the race must produce no arming cycle at all.
!   8  fault log full -- the run is not converging (a handler is re-faulting
!      forever). Surfaces a livelock as a result code, not a stop-time timeout.
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's
! test_result() requires TEST_PASS_MAGIC for PASS, and _fail clamps r9==0 to
! 0x7F so an un-set fail code is never mistaken for PASS.
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
#if CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0. REQUIRED: the I-side TLB fault path is gated on
        !      SR.RB='0' (core/cpu.vhd), and so is walk_req. With RB=1 (reset
        !      default) I-fetches bypass the TLB and page 1 never misses. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _vbase. All six TLB fault kinds vector to VBR+0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Fault log: empty (plain P0 stores, AT still off). ----
        mov.l   p_log_ptr, r0
        mov.l   p_log_base, r1
        mov.l   r1, @r0

        ! ---- Zero the TSB so every walk fails OPEN: the walker must be LIVE
        !      (check 5 reads its cnt_walks) but must not resolve anything, so
        !      the software handler still installs exactly as it does in
        !      mmuidorder. 64 sets x 8 words covers the configured size. ----
        mov.l   p_tsb_base, r0
        mov.l   p_tsb_words, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Map page 0 identity, W|X|C (no U: kernel fetch, SMEP). ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Map page 2 identity TOO. THIS IS THE GUARD'S POINT: the older
        !      D accesses must HIT, so that walk_d_miss stays '0' and the
        !      younger I-side miss is the one eligible to arm. Check 3
        !      re-verifies it after the fact. ----
        mov.l   p_pteh_page2, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_page2, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Point the walker at the zeroed TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Enable AT. Page 1 is deliberately NOT mapped: it is what the
        !      fall-through fetch misses on. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Walker liveness warm-up, BEFORE the race and with nothing else
        !      in flight: one load from unmapped page 3. With no D access live
        !      the walker arms, walks, finds the zeroed TSB and gives up
        !      (cnt_walks++), and the handler installs page 3 as usual.
        !
        !      This is what check 5 reads, and it is deliberately NOT the race
        !      itself: with the gate PRESENT the race must produce NO arming
        !      cycle at all -- that is the gate doing its job -- so cnt_walks
        !      from the race would be 0 on a correct build. The warm-up
        !      establishes "the walker is alive in this image" independently,
        !      which is what p_walk_order_assert needs in order to be able to
        !      sample anything.
        mov.l   c_warm_va, r0
        mov.l   @r0, r0

        ! ---- Operands for the race. r13 = the MAPPED data page the stores
        !      target, r12 = the payload they write, r14 = where page 1 bounces
        !      back to. All non-banked, so the handler (bank 1, r0-r7) cannot
        !      disturb them. ----
        mov.l   c_data_va, r13          ! 0x00002000, MAPPED -> the stores HIT
        mov.l   v_payload, r12          ! the word the stores must land
        mov.l   p_check, r14            ! where page 1 bounces back to

        ! ---- Enter the store stream at 0x0FE0. It must be entered by a JUMP,
        !      not fallen into: nothing may sit between the operand loads above
        !      and the stream, and in particular no other memory access, or the
        !      data bus is not busy at the page boundary. ----
        mov.l   c_race_va, r2
        jmp     @r2
        nop

        ! Unreachable: page 1 always bounces to _check.
        mov     #7, r9
        mov.l   p_fail, r0
        jmp     @r0
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _vbase
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C8        ! PA 0x0000 | W|X|C
p_pteh_page2:   .long 0x00002000        ! VPN of page 2, ASID 0
p_ptel_page2:   .long 0x000020C8        ! PA 0x2000 | W|X|C
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsb_base:     .long 0x00010000
p_tsb_words:    .long 512               ! 64 sets x 2 ways x 4 words
c_warm_va:      .long 0x00003000        ! page 3, UNMAPPED -- walker warm-up
c_data_va:      .long 0x00002000        ! page 2, MAPPED -> the stores HIT (OLDER)
v_payload:      .long 0x5A5AC3C3        ! must match k_dataword below
c_race_va:      .long 0x00000FE0        ! head of the store stream, page 0 tail
p_check:        .long _check
p_log_ptr:      .long _log_ptr
p_log_base:     .long _log
p_fail:         .long _fail

        ! ================= verification, back on page 0 =================
        .balign 4
_check:
        ! ---- AT off; everything below is P0 identity. ----
        mov.l   k_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! (1) ANTI-VACUITY: at least one fault was taken.
        mov.l   k_log_ptr, r0
        mov.l   @r0, r1
        mov.l   k_log_base, r2
        cmp/eq  r1, r2
        bf      1f
        mov     #1, r9
        bra     _bail
        nop
1:
        ! (2) the YOUNGER I-side fault must have fired on page 1.
        mov.l   k_page1, r4
        bsr     _log_find               ! r0 = 1 if r4 present in the log
        nop
        tst     r0, r0
        bf      2f
        mov     #2, r9
        bra     _bail
        nop
2:
        ! (3) the OLDER D accesses must have HIT: page 2 must NOT be in the log.
        !     See the header -- if it faults, walk_d_miss is '1' and the
        !     assertion's antecedent can never be satisfied.
        mov.l   k_page2, r4
        bsr     _log_find
        nop
        tst     r0, r0
        bt      3f
        mov     #3, r9
        bra     _bail
        nop
3:
        ! (4) and the stream landed its payload in page 2.
        mov.l   k_dataword, r4
        mov.l   k_data_va, r0
        mov.l   @r0, r5
        cmp/eq  r4, r5
        bt      4f
        mov     #4, r9
        bra     _bail
        nop
4:
        ! (5) ANTI-VACUITY for the RTL assertion: the walker armed at least
        !     once in this image. p_walk_order_assert only samples on an arming
        !     cycle, so a dead walker would make it unconditionally silent.
        mov.l   k_walkcnt, r0
        mov.l   @r0, r1
        shlr16  r1                      ! [31:16] = cnt_walks
        tst     r1, r1
        bf      5f
        mov     #5, r9
        bra     _bail
        nop
5:
        mov     #0, r9
        mov.l   k_done, r0
        jmp     @r0
        nop

_bail:
        mov.l   k_fail, r0
        jmp     @r0
        nop

        ! ---- _log_find: r4 = value to find. Returns r0 = 1 if present.
        !      Clobbers r0/r2/r3/r5. Lives in page 0, so it cannot fault. ----
        .balign 4
_log_find:
        mov.l   k_log_ptr, r0
        mov.l   @r0, r5                 ! r5 = write pointer (end)
        mov.l   k_log_base, r2          ! r2 = cursor
        mov     #0, r0
1:      cmp/hs  r5, r2                  ! cursor >= end -> done
        bt      2f
        mov.l   @r2, r3
        cmp/eq  r3, r4
        bf      3f
        mov     #1, r0                  ! found
        bra     2f
        nop
3:      add     #4, r2
        bra     1b
        nop
2:      rts
        nop

        .align 2
k_mmucr:        .long 0xFF000010
k_fail:         .long _fail
k_done:         .long _done
k_log_ptr:      .long _log_ptr
k_log_base:     .long _log
k_page1:        .long 0x00001000
k_data_va:      .long 0x00002000
k_page2:        .long 0x00002000
k_dataword:     .long 0x5A5AC3C3
k_walkcnt:      .long 0xFF000054        ! [31:16]=cnt_walks [15:0]=cnt_hits

        ! ---- Report epilogue. MUST live in PAGE 0. ----
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
        .org 0x0600
_vbase:
        .space 0x400, 0

        .org 0x0A00
_v_tlbmiss:                             ! _vbase + 0x400 -- ALL TLB fault kinds
        bra     _h_tlb
        nop

        ! ---- Common handler. Entered with SR.RB=1, so r0-r7 here are BANK 1
        !      and the interrupted code's r11-r14 (bank 0) are untouched.
        !      Logs the faulting page and installs an identity mapping for it. ----
        .org 0x0A60
_h_tlb:
        mov.l   Htea_addr, r0
        mov.l   @r0, r2                 ! r2 = TEA
        mov.l   Hvpn_mask, r3
        and     r3, r2                  ! r2 = VPN base -- the faulting page

        mov.l   Hlog_ptr, r1
        mov.l   @r1, r5
        mov.l   Hlog_end, r3
        cmp/hs  r3, r5                  ! log full -> the run is not converging
        bf      1f
        mov     #8, r9
        mov.l   Hfail, r0
        jmp     @r0
        nop
1:
        mov.l   r2, @r5                 ! log the faulting page
        add     #4, r5
        mov.l   r5, @r1

        mov     r2, r0
        .word   0x405E                  ! LDC r0, PTEH
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
Hlog_ptr:       .long _log_ptr
Hlog_end:       .long _log_end
Hfail:          .long _fail

        ! ---- Fault log, in page 0 (mapped, writable). ----
        .org 0x0E80
_log_ptr:       .long 0
_log:           .rept 16
                .long 0
                .endr
_log_end:

        ! ================= THE RACE, at the tail of page 0 =================
        ! Sixteen back-to-back stores to RESIDENT page 2, ending at the last
        ! halfword of page 0, with execution falling through into UNMAPPED
        ! page 1. The fetcher runs ahead of MA, so the fetch of 0x1000 is
        ! presented -- and misses -- while the stream is still draining on the
        ! data bus: sig_db_o.en='1', walk_d_miss='0', tlb_i_hit='0', and
        ! tlb_walk's `tried' still clear. That is the assertion's antecedent,
        ! and nothing shorter than a stream reaches it (see the header).
        .org 0x0FE0
        .rept 16
        .word   0x2DC2                  ! MOV.L R12, @R13   (r13 = 0x2000)
        .endr
        ! ...falls through into page 1.

        ! ---- Page 1 (UNMAPPED): fetched while the stores above are live. ----
        .org 0x1000
        jmp     @r14
        nop

        ! ---- Page 2 (MAPPED): the stores' data page. ----
        .org 0x2000
        .long   0

        .org 0x3100

#endif  ! CONFIG_PRIV_ARCH
