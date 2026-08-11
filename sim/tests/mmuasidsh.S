! mmuasidsh.S -- ASID takes effect in the SHADOW of LDC Rm,ASIDR (J4).
!
! WHY THIS GUARD EXISTS.
!
! Phase 4a duplicates the ASIDR register inside the datapath: a second 16-bit
! copy, exported on a dedicated port, consumed ONLY by the TLB's lookup compare
! (u_tlb.asid). The copy exists purely for placement -- the master has three
! consumers (P4 readback, tlb_walk, TLB lookup) so the placer parks its flop at
! their centroid, measured as a 3.7 ns routing hop and the largest single item
! on the j4c critical path.
!
! The replica is written from this'comb -- the same next-state value, the same
! enable, the same clock edge as the master -- so it is bit-identical to the
! master in every cycle. The natural-looking wrong implementation samples the
! master's OUTPUT instead:
!
!     if rising_edge(clk) then asidr_tlb <= mmu_regs.asidr; end if;
!
! which lags. A translated access in the shadow of LDC Rm,ASIDR then looks up
! under the PREVIOUS ASID: a wrong hit or a wrong miss, with no exception and
! no diagnostic. Nothing else in the suite covers this -- ASIDR changes only at
! a context switch, and every other guard lets it settle for several
! instructions before the next translated access.
!
! HOW DEEP THE SHADOW ACTUALLY IS -- MEASURED, from VCDs of this guard
! (10 ns clock), not assumed. This bounds what any software guard can prove:
!
!   D side.  The master takes its new value one cycle BEFORE the following
!            instruction's data access is presented (master = 0x22 at 800 ns,
!            d_va = 0x4000 at 810 ns). One cycle of structural slack: the next
!            instruction's MA cannot be pulled closer to the LDC's writeback.
!   I side.  Useless as a probe, and not for the reason one would guess: the
!            fetch stream runs FAR AHEAD of execute. Measured with the LDC at
!            0x2FFE and the next instruction at 0x3000 on a page mapped only
!            under the new ASID, the fetch of 0x3000 was presented at 1630 ns
!            while the LDC did not update ASIDR until 1730 ns -- ten cycles
!            later. That fetch misses on CORRECT hardware, so an I-side
!            construction cannot distinguish a skewed replica from a good one.
!
! CONSEQUENCE, stated plainly: a ONE-cycle lag is not observable anywhere in
! this microarchitecture -- it lands exactly on the D-side boundary and is
! absorbed by that one cycle of slack. This guard therefore pins the boundary
! at TWO cycles, which is the tightest any program can reach. The one-cycle
! case is defended by construction (this'comb) and by review, not by test.
!
! LEGS. A fault carries the leg marker at P1 0x80005000; the handler reports
! that marker as the fail code when the fault was not the expected one.
!
!   1  Shadow. VPN 0x4 (VA 0x4000 -> PA 0x4000) is installed NON-GLOBAL under
!      ASID B only. With ASIDR = A, `LDC r0,ASIDR` (B) is followed IMMEDIATELY
!      by `mov.l @r2,r8` on VA 0x4000. It must HIT. Everything the load needs
!      is preloaded, so nothing sits between the LDC and the access.
!   2  Settled control: the same load after four nops. Separates "the replica
!      is skewed" (1 red, 2 green) from "the mapping was never installed"
!      (both red), so a red leg 1 cannot be waved off as a bad setup.
!   3  Negative direction: switch ASIDR back to A and immediately re-run the
!      load. It must FAULT -- a stuck-at or never-updating replica would keep
!      matching under B and sail through legs 1 and 2. The handler seeing
!      marker 3 is the ONLY pass path for the test as a whole.
!
! VBR = _v_load - 0x400, so the TLB vector (VBR+0x400) lands on _v_load.
!
! MUTATION-VERIFIED (rebuilt without -n each time):
!   this'comb -> this'register            (1-cycle lag)  -> PASS  (see above)
!   this'comb -> two-deep register chain  (2-cycle lag)  -> FAIL, code 3

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

! LDC Rm,ASIDR = 0100 mmmm 0111 1110 (decode/gen-go/spec/sh4/mmu.toml).
#define LDC_R0_ASIDR .word 0x407E
#define LDC_R0_PTEH  .word 0x405E
#define LDC_R0_PTEL  .word 0x406E
#define LDC_R0_VBR   .word 0x402E
#define LDTLB        .word 0x0038

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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_load - 0x400 (so VBR+0x400 = _v_load). ----
        mov.l   p_vbr_val, r0
        LDC_R0_VBR

        ! ---- Seed PA 0x4000 = SENTINEL via P1 (untranslated, AT-independent). ----
        mov.l   p_sentinel, r3
        mov.l   p_p1_4000, r2           ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2

        ! ---- leg marker = 0 (nothing reached yet); the handler reads it. ----
        mov.l   p_p1_leg, r2
        mov     #0, r1
        mov.l   r1, @r2

        ! ---- Map page 0 GLOBAL identity (code + handler): W|X|C|G, U cleared. ----
        mov     #0, r0
        LDC_R0_PTEH                     ! VPN 0
        mov.l   p_ptel_page0, r0        ! 0x000000CC (W7 X6 C3 G2)
        LDC_R0_PTEL
        mov.l   p_asid_a, r0
        LDC_R0_ASIDR                    ! global entries ignore ASID
        LDTLB

        ! ---- Map VPN 0x4 (VA 0x4000 -> PA 0x4000) NON-global under ASID B. ----
        mov.l   p_pteh_p4, r0           ! VPN 0x4
        LDC_R0_PTEH
        mov.l   p_ptel_p4, r0           ! 0x000040E8 (W|X|U|C, non-global)
        LDC_R0_PTEL
        mov.l   p_asid_b, r0
        LDC_R0_ASIDR                    ! tag the entry with ASID B
        LDTLB

        ! ---- Back to ASID A, well before the measurement. ----
        mov.l   p_asid_a, r0
        LDC_R0_ASIDR
        nop
        nop
        nop
        nop

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Preload everything the measured load needs, so the only thing
        ! ---- between the LDC and the translated access is the LDC itself.
        mov.l   c_va4, r2               ! r2 = 0x00004000
        mov.l   p_sentinel, r4          ! r4 = expected value
        mov.l   p_p1_leg, r5            ! r5 = P1 alias of the leg marker
        mov.l   p_asid_b, r0            ! r0 = ASID B
        mov     #1, r1
        mov.l   r1, @r5                 ! leg marker 1

        ! ================= LEG 1: the shadow access ==============
        LDC_R0_ASIDR                    ! ASID := B
        mov.l   @r2, r8                 ! <-- SHADOW ACCESS. Must HIT under B.

        cmp/eq  r8, r4
        mov     #1, r9                  ! fail 1 = shadow load did not see the new ASID
        bt      1f                      ! bt-over-bra: _fail is outside bf's +/-256B
        bra     _fail
        nop
1:

        ! ================= LEG 2: settled control ================
        mov     #2, r1
        mov.l   r1, @r5                 ! leg marker 2
        nop
        nop
        nop
        nop
        mov.l   @r2, r8                 ! same load, ASIDR long settled
        cmp/eq  r8, r4
        mov     #2, r9                  ! fail 2 = the mapping is wrong (not a skew)
        bt      2f
        bra     _fail
        nop
2:

        ! ================= LEG 3: negative direction =============
        mov.l   p_asid_a, r0
        mov     #3, r1
        mov.l   r1, @r5                 ! leg marker 3
        LDC_R0_ASIDR                    ! ASID := A
        mov.l   @r2, r8                 ! <-- must MISS -> _v_load with marker 3

        ! Fell through: the entry was still usable under ASID A.
        mov     #3, r9                  ! fail 3 = replica did not follow ASIDR back
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000CC        ! W|X|C|G, U cleared (kernel global code)
p_pteh_p4:      .long 0x00004000
p_ptel_p4:      .long 0x000040E8        ! PA 0x4000 | W|X|U|C (non-global)
p_asid_a:       .long 0x00000011
p_asid_b:       .long 0x00000022
p_sentinel:     .long 0xA51DA51D
p_p1_4000:      .long 0x80004000
p_p1_leg:       .long 0x80005000        ! P1 alias of PA 0x5000 (leg marker)
c_va4:          .long 0x00004000

#endif  ! CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ---- TLB vector at VBR+0x400. ----
        ! A fault is EXPECTED only on leg 3. Anywhere else it is the defect this
        ! guard exists to catch, and the leg marker names which leg.
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT) before anything else
        mov.l   Hleg, r0
        mov.l   @r0, r1
        mov     #3, r2
        cmp/eq  r1, r2
        bf      _h_bad                  ! fault outside leg 3 -> report the leg
        mov.l   Hresult, r0
        mov.l   Hresult_pass, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop
_h_bad:
        ! r1 = leg marker (1 or 2, or 0 if the fault preceded every leg).
        mov     r1, r9
        tst     r9, r9                  ! never write the PASS token from a fail path
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   Hresult, r0
        mov.l   r9, @r0
_h_bad_spin:
        bra     _h_bad_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hresult:        .long TEST_RESULT_ADDRESS
Hresult_pass:   .long   TEST_PASS_MAGIC
Hleg:           .long 0x80005000        ! P1 alias of the leg marker

        ! ---- Backing pages so VA/PA 0x4000 and 0x5000 exist in the image. ----
_fault_pages:
        .space 0x2000, 0

#endif  ! CONFIG_PRIV_ARCH
